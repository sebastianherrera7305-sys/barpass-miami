import AVFoundation
import Foundation

/// Captura de voz para Remy — rollback al pipeline de Build 148 (owner
/// Build 150/151, 2026-10-30 "crashea apenas le doy a voice"):
/// SFSpeechRecognizer / AVAudioEngine daban NSException no capturables.
/// AVAudioRecorder + upload a `/api/concierge/voice` (Whisper en Groq)
/// NUNCA crasheó — el problema previo era audio silencioso en el teléfono
/// del owner, probablemente por routing de mic a un BT device.
///
/// Fixes nuevos vs Build 148:
///   1. Fuerza el built-in mic (no BT) via `preferredInput` seleccionando
///      `.builtInMic`. Si AirPods están conectados, iOS igual usa el mic
///      del iPhone.
///   2. Mide peak dB después de grabar. Si está muy bajo, muestra error
///      claro con el nivel para diagnosticar.
///   3. Session `.record` + `.measurement` (vs `.default`) — `.measurement`
///      es el modo que Apple recomienda para capturar voz y disables
///      cualquier procesamiento del DSP que podría atenuar la señal.
@MainActor
final class RemyVoiceRecorder: ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var seconds: Int = 0

    var errorMessageOrNil: String? {
        if case .error(let msg) = state { return msg }
        return nil
    }

    private static let maxSeconds: Int = 60

    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var timer: Timer?

    func startRecording() async throws {
        switch state {
        case .idle, .error: break
        case .recording, .transcribing: return
        }

        // Permiso de micrófono
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            if AVAudioApplication.shared.recordPermission == .granted {
                micGranted = true
            } else if AVAudioApplication.shared.recordPermission == .denied {
                micGranted = false
            } else {
                micGranted = await AVAudioApplication.requestRecordPermission()
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            if session.recordPermission == .granted {
                micGranted = true
            } else if session.recordPermission == .denied {
                micGranted = false
            } else {
                micGranted = await withCheckedContinuation { c in
                    session.requestRecordPermission { ok in c.resume(returning: ok) }
                }
            }
        }
        guard micGranted else {
            state = .error("Permití el micrófono en Ajustes → BarPass para hablarle a Remy.")
            throw VoiceError.micDenied
        }

        // Audio session en modo .record + .measurement (recomendado por
        // Apple para capturar voz sin que el DSP la atenue).
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: [])

        // Fuerza el built-in mic del iPhone — si hay AirPods / BT, iOS
        // elegiría ESOS por default, y pueden estar silenciados por otra
        // app (lo que generaba el "No te escuché" del Build 148).
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtIn)
        }

        // Config del recorder: AAC 16kHz mono (óptimo para Whisper).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("remy-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey:              Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey:            16_000.0,
            AVNumberOfChannelsKey:      1,
            AVEncoderAudioQualityKey:   AVAudioQuality.medium.rawValue,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        rec.prepareToRecord()
        guard rec.record() else {
            state = .error("No se pudo iniciar la grabación. Reintentá.")
            throw VoiceError.couldNotStart
        }
        recorder = rec
        audioURL = url
        seconds = 0
        state = .recording

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

    func stopAndTranscribe() async throws -> String {
        guard state == .recording, let rec = recorder, let url = audioURL else { return "" }

        // Lee peak dB ANTES de parar — si está muy bajo, sabemos que el
        // mic grabó silencio y damos un error claro.
        rec.updateMeters()
        let peakDb = rec.peakPower(forChannel: 0)

        rec.stop()
        timer?.invalidate(); timer = nil
        recorder = nil
        state = .transcribing

        let duration = rec.currentTime
        defer {
            try? FileManager.default.removeItem(at: url)
            audioURL = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }

        guard duration >= 0.4 else {
            state = .idle
            return ""
        }

        let data = try Data(contentsOf: url)

        // Chequeo de peak dB — menor a -50dB significa silencio efectivo.
        // (0 dB = max, -∞ = silencio total; -50 ya es casi inaudible)
        if peakDb < -50 {
            state = .error("El micrófono grabó silencio (peak \(String(format: "%.0f", peakDb)) dB). Si tenés AirPods conectados, desconectalos y reintentá.")
            throw VoiceError.transcribeFailed("silent")
        }

        if data.count < 2_000 {
            state = .error("Audio demasiado chico (\(data.count) bytes). Reintentá.")
            throw VoiceError.transcribeFailed("tiny file")
        }

        let text = try await uploadForTranscription(audio: data, filename: url.lastPathComponent)
        state = .idle
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            state = .error("No te escuché bien. Acercá el iPhone y hablá más fuerte.")
        }
        return clean
    }

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

    private func uploadForTranscription(audio: Data, filename: String) async throws -> String {
        let endpoint = APIClient.baseURL.appendingPathComponent("concierge/voice")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        let boundary = "----BPFormBoundary\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

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
            state = .error("No se pudo transcribir. \(bodyText.prefix(140))")
            throw VoiceError.transcribeFailed(bodyText)
        }

        struct VoiceResponse: Decodable { let text: String }
        let decoded = try JSONDecoder().decode(VoiceResponse.self, from: data)
        return decoded.text
    }

    enum VoiceError: Error {
        case micDenied
        case couldNotStart
        case transcribeFailed(String)
    }
}
