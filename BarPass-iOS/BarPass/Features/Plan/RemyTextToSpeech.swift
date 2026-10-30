import AVFoundation
import Foundation

/// Habla las respuestas de Remy en voz alta usando AVSpeechSynthesizer —
/// 100% nativo, 0ms de latencia de red, $0 de costo (owner Build 143,
/// 2026-10-28 "dale perfect" al TTS de Apple como primera versión).
///
/// Diseño:
///   · Elige la mejor voz disponible según el idioma de la respuesta
///     (es-* o en-*). Si el usuario descargó una voz "Enhanced" o
///     "Premium" en Ajustes → Accesibilidad → Contenido hablado → Voces,
///     la usamos — mejora enorme sobre la voz Siri default.
///   · Honra silence switch / modo auricular — misma AVAudioSession
///     que el recorder, así no choca con el input de voz.
///   · Cuando empieza una nueva respuesta, cortamos la anterior en seco
///     (nunca dos voces encimadas).
///   · El usuario puede silenciar manualmente desde el UI (toggle).
///
/// Costo real: $0 por respuesta. Siempre. Voz robótica si no bajás una
/// mejor en Ajustes, pero funciona offline y nunca te cobra nada.
@MainActor
final class RemyTextToSpeech: NSObject, ObservableObject {

    @Published private(set) var isSpeaking: Bool = false

    /// Caracteres ya enviados a `speak()` en esta ráfaga — usado por el
    /// modo streaming para no re-hablar lo mismo. Reset en `startStream()`.
    private var charsSpokenInStream: Int = 0
    /// Flag que indica si estamos en modo streaming (hablando como van
    /// llegando chunks) vs modo one-shot (`speak(text)` hablando una vez).
    private var isStreaming: Bool = false
    /// Si el usuario silenció manualmente desde el UI. Persiste a disco
    /// para que la preferencia aguante entre aperturas de la app.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Callback que dispara CUANDO termina de hablar — el chat lo usa para
    /// reabrir el mic automáticamente en modo conversación (owner Build
    /// 145, 2026-10-28: "necesito que tenga respuesta y que me dé
    /// resultados en el chat, no que me pida que hable y toque"). Sin
    /// esto, cada turno de voz era un dictado separado; con esto, es una
    /// conversación corrida: hablás → Remy responde → mic se abre solo
    /// → hablás de nuevo.
    var onSpeechComplete: (() -> Void)?

    private static let enabledKey = "RemyTTS.isEnabled"

    private let synth = AVSpeechSynthesizer()

    override init() {
        // Default: encendido. Si el usuario lo apaga, UserDefaults lo
        // guarda y lo recupera en la próxima apertura.
        let stored = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool
        self.isEnabled = stored ?? true
        super.init()
        synth.delegate = self
    }

    /// Habla el texto. Si TTS está apagado por el usuario, no-op.
    /// Si ya hay algo hablando, lo corta y arranca lo nuevo.
    func speak(_ text: String) {
        guard isEnabled else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        // Interrumpimos cualquier audio en curso. .immediate corta de una,
        // no espera a la próxima frase (que es lo que haría .word).
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }

        // Elige voz según el idioma detectado del texto.
        let languageCode = Self.detectLanguage(of: clean)
        let voice = Self.bestVoice(for: languageCode)

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = voice
        // Velocidad: default AVSpeechUtteranceDefaultSpeechRate es ~0.5.
        // Un poco más rápido (0.52) suena menos somnoliento sin
        // perderse el entendimiento.
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        // Pausas naturales entre oraciones.
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.1

        // Reservar el audio session en modo "playback" para que suene
        // aunque el silence switch del iPhone esté en silent. Idéntico a
        // lo que hace Siri y los players de audio normales.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        synth.speak(utterance)
    }

    /// Para en seco. Usado cuando el usuario toca para silenciar en el
    /// medio de una respuesta, o cuando sale de la pantalla de Remy.
    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        isStreaming = false
        charsSpokenInStream = 0
    }

    /// Owner Build 148, 2026-10-28 "necesito una voz inmediata": modo
    /// streaming — llamalo cada vez que `chat.currentReply` crezca y
    /// envía las oraciones nuevas a la cola de TTS apenas tenemos
    /// puntuación. La primera oración puede sonar en <2s de que el
    /// usuario parara de hablar, en vez de esperar los 5-10s de la
    /// respuesta completa.
    func feedStreaming(_ fullTextSoFar: String) {
        guard isEnabled else { return }
        if !isStreaming {
            // Nueva ráfaga: resetear tracking y arrancar la sesión de audio.
            isStreaming = true
            charsSpokenInStream = 0
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true, options: [])
        }
        guard fullTextSoFar.count > charsSpokenInStream else { return }

        // El texto NUEVO desde la última llamada.
        let newChunk = String(fullTextSoFar.suffix(fullTextSoFar.count - charsSpokenInStream))

        // Buscamos oraciones completas (termina en . ! ? ; o nueva línea).
        // Si no hay sentencia completa todavía, esperamos al próximo delta.
        let terminators: Set<Character> = [".", "!", "?", ";", "\n"]
        guard let lastSentenceEndIdx = newChunk.lastIndex(where: { terminators.contains($0) }) else {
            return
        }
        let completePart = String(newChunk[newChunk.startIndex...lastSentenceEndIdx])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !completePart.isEmpty else { return }

        charsSpokenInStream += newChunk.distance(from: newChunk.startIndex, to: lastSentenceEndIdx) + 1

        // Idioma + voz
        let languageCode = Self.detectLanguage(of: completePart)
        let voice = Self.bestVoice(for: languageCode)

        let utterance = AVSpeechUtterance(string: completePart)
        utterance.voice = voice
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        // Las sucesivas se encolan automáticamente — el delegate dispara
        // `didFinish` cuando TODA la cola termina (no por utterance), así
        // que `onSpeechComplete` espera al último chunk.
        synth.speak(utterance)
    }

    /// Fin del stream — habla cualquier colita suelta y marca que el
    /// próximo `feedStreaming` arranca una nueva ráfaga.
    func finishStreaming(_ fullText: String) {
        guard isStreaming else { return }
        guard isEnabled else { isStreaming = false; return }
        if fullText.count > charsSpokenInStream {
            let tail = String(fullText.suffix(fullText.count - charsSpokenInStream))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                let utterance = AVSpeechUtterance(string: tail)
                utterance.voice = Self.bestVoice(for: Self.detectLanguage(of: tail))
                utterance.rate = 0.52
                synth.speak(utterance)
                charsSpokenInStream = fullText.count
            }
        }
        isStreaming = false
    }

    // MARK: - Voice selection

    /// Detección simple de idioma por heurística básica — buscamos
    /// marcadores inequívocos de español (acentos, ñ, palabras funcionales
    /// como "qué", "está", "noche") vs. inglés. No usamos NLLanguageRecognizer
    /// porque es overkill para 2 idiomas y requiere linkear Natural
    /// Language framework. Fallback a es (Remy habla español la mayoría del
    /// tiempo con usuarios de Miami).
    private static func detectLanguage(of text: String) -> String {
        let lower = text.lowercased()
        // Marcadores claros de español
        let spanishMarkers = ["á", "é", "í", "ó", "ú", "ñ", "¿", "¡",
                              " está ", " esta ", " qué ", " noche ", " música ",
                              " cerveza ", " trago ", " amigos ", " viernes "]
        for marker in spanishMarkers where lower.contains(marker) {
            return "es"
        }
        // Marcadores inequívocos de inglés — palabras cortas que casi nunca
        // aparecen en español natural.
        let englishMarkers = [" the ", " and ", " you ", " tonight ", " drinks ",
                              " let's ", " there's ", " i'll ", " we'll "]
        for marker in englishMarkers where lower.contains(marker) {
            return "en"
        }
        return "es"   // default
    }

    /// Mejor voz disponible para el idioma. Prioridad:
    ///   1. Voz "premium" / "enhanced" que el usuario haya descargado
    ///      (Ajustes → Accesibilidad → Contenido hablado → Voces).
    ///   2. Voz "siri" (natural neural) si existe en el locale.
    ///   3. Voz "default" del locale.
    ///   4. Fallback: AVSpeechSynthesisVoice(language: lang)
    private static func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let locales: [String]
        if languageCode == "en" {
            locales = ["en-US", "en-GB"]
        } else {
            // es-MX primero (latino, lo que la mayoría de usuarios de
            // Miami/BarPass hablan), después es-US (U.S. Spanish),
            // después es-ES (España).
            locales = ["es-MX", "es-US", "es-ES"]
        }
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        for locale in locales {
            let matching = allVoices.filter { $0.language == locale }
            if let premium = matching.first(where: { $0.quality == .premium }) { return premium }
            if let enhanced = matching.first(where: { $0.quality == .enhanced }) { return enhanced }
            if let standard = matching.first { return standard }
        }
        return AVSpeechSynthesisVoice(language: locales.first ?? "es-MX")
    }
}

extension RemyTextToSpeech: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.onSpeechComplete?()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
