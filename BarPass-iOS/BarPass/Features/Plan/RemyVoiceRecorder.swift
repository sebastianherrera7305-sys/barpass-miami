import AVFoundation
import Foundation

/// Recorder + transcript para la entrada de voz del chat de Remy (owner
/// Build 142, 2026-10-28: "estamos haciendo el agente en este chat de
/// remy — agregá voz").
///
/// Flujo:
///   1. `startRecording()` — pide permiso de micrófono si hace falta, abre
///      la sesión de audio, graba a /tmp/.../remy-voice.m4a (AAC 44.1kHz).
///   2. `stopAndTranscribe()` — cierra la grabación, sube el .m4a al
///      endpoint `/api/concierge/voice` (Whisper en Groq), devuelve el
///      texto reconocido.
///
/// Diseño honesto:
///   · Si el usuario niega el permiso del mic → tira `micDenied`; la UI
///     tiene que mostrar "andá a Settings → BarPass → Mic" en vez de
///     intentar grabar de nuevo en silencio.
///   · El audio se graba localmente y se borra apenas se sube el request
///     — no persiste en disco ni se mantiene en memoria.
///   · La duración está capada en 60 segundos: Whisper acepta más pero
///     este chat es para pedidos cortos ("algo más barato", "estamos 6"),
///     no para dictados largos.
@MainActor
final class RemyVoiceRecorder: ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    @Published private(set) var state: State = .idle
    /// Elapsed de grabación en segundos — la UI lo usa para el contador.
    @Published private(set) var seconds: Int = 0

    /// Tope de duración por grabación. Después de este tiempo, el recorder
    /// se corta solo y transcribe lo que haya.
    private static let maxSeconds: Int = 60

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var audioURL: URL?

    /// Pide permiso de mic (si no fue dado) + arranca a grabar. Returns
    /// true si la grabación empezó; false si el permiso fue negado.
    func startRecording() async throws {
        switch state {
        case .idle, .error:
            break   // permitido arrancar / re-arrancar tras error
        case .recording, .transcribing:
            return  // ya corriendo, ignorar tap duplicado
        }

        // Permiso: iOS 17+ usa AVAudioApplication; antes AVAudioSession.
        let granted: Bool
        if #available(iOS 17.0, *) {
            if AVAudioApplication.shared.recordPermission == .granted {
                granted = true
            } else if AVAudioApplication.shared.recordPermission == .denied {
                granted = false
            } else {
                granted = await AVAudioApplication.requestRecordPermission()
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            if session.recordPermission == .granted {
                granted = true
            } else if session.recordPermission == .denied {
                granted = false
            } else {
                granted = await withCheckedContinuation { cont in
                    session.requestRecordPermission { ok in cont.resume(returning: ok) }
                }
            }
        }
        guard granted else {
            state = .error("Permití el micrófono en Ajustes → BarPass para hablarle a Remy.")
            throw VoiceError.micDenied
        }

        // Sesión de audio en modo de grabación. `.playAndRecord` para que
        // una respuesta hablada futura (TTS) no choque — hoy solo grabamos.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: [])

        // AAC a 44.1kHz mono — formato que Groq Whisper admite directo
        // (.m4a), y chico (~250KB para 30s). Si en el futuro queremos
        // menor tamaño, bajamos a 16kHz sin perder transcripción.
        let settings: [String: Any] = [
            AVFormatIDKey:              Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey:            44_100.0,
            AVNumberOfChannelsKey:      1,
            AVEncoderAudioQualityKey:   AVAudioQuality.medium.rawValue,
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("remy-voice-\(UUID().uuidString).m4a")
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.prepareToRecord()
        guard rec.record() else {
            state = .error("No se pudo iniciar la grabación. Reintentá.")
            throw VoiceError.couldNotStart
        }

        recorder = rec
        audioURL = url
        seconds = 0
        state = .recording

        // Timer de contador + auto-cut a los 60 seg.
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seconds += 1
                if self.seconds >= Self.maxSeconds {
                    _ = try? await self.stopAndTranscribe()
                }
            }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    /// Cierra la grabación, sube el audio al endpoint de voice y devuelve
    /// el transcript. Si la grabación duró <0.4s se descarta — es casi
    /// seguro un tap accidental.
    func stopAndTranscribe() async throws -> String {
        guard case .recording = state, let rec = recorder, let url = audioURL else {
            return ""
        }
        rec.stop()
        timer?.invalidate(); timer = nil
        recorder = nil
        state = .transcribing

        let duration = rec.currentTime  // segundos
        defer {
            try? FileManager.default.removeItem(at: url)
            audioURL = nil
            // Devolvemos la sesión al modo default para no mantener la
            // ruta de altavoz forzada después del upload.
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }

        guard duration >= 0.4 else {
            state = .idle
            return ""
        }

        let data = try Data(contentsOf: url)
        let text = try await uploadForTranscription(audio: data, filename: url.lastPathComponent)
        state = .idle
        return text
    }

    /// Cancela sin transcribir — p.ej. el usuario largó el botón pronto
    /// o cambió de pantalla. Borra el audio y vuelve a `.idle`.
    func cancel() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate(); timer = nil
        if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
            audioURL = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        state = .idle
        seconds = 0
    }

    // MARK: - Upload

    private func uploadForTranscription(audio: Data, filename: String) async throws -> String {
        // `APIClient.baseURL` ya termina en `/api`, así que el path acá
        // es sólo `/concierge/voice` (sin repetir `/api/`).
        let endpoint = APIClient.baseURL.appendingPathComponent("concierge/voice")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        let boundary = "----BPFormBoundary\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mp4", forHTTPHeaderField: "Accept")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            state = .error("No se pudo transcribir el audio. \(bodyText.prefix(140))")
            throw VoiceError.transcribeFailed(bodyText)
        }

        struct VoiceResponse: Decodable { let text: String }
        let decoded = try JSONDecoder().decode(VoiceResponse.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum VoiceError: Error {
        case micDenied
        case couldNotStart
        case transcribeFailed(String)
    }
}
