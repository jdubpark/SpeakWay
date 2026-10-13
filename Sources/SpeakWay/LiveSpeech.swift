import AVFoundation
import SpeakWayCore

@MainActor final class LiveSpeech: SpeechSession {
    private let key: String
    private let settings: Settings
    private let capture = AudioCapture()
    private var socket: URLSessionWebSocketTask?
    private var networkSession: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var sender: BufferedAudioSender?
    private var transcript = RealtimeTranscript()
    private var cartesiaTranscript = CartesiaTranscript()
    private var isCartesia: Bool { settings.speechProvider == .cartesia }
    private var providerName: String { isCartesia ? "Cartesia" : "OpenAI" }
    private var ready = false
    private var cancelled = false
    private var failure: Error?
    private var byteCount = 0
    private let archive: RecordingArchive?
    init(key: String, settings: Settings, archive: RecordingArchive? = nil) {
        self.key = key; self.settings = settings; self.archive = archive
    }

    func start(onText: @escaping (String) -> Void, onLevel: @escaping (Float) -> Void,
               onFailure: @escaping (Error) -> Void) async throws {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        var request: URLRequest
        if isCartesia {
            if settings.cartesiaModel != "ink-whisper", !["en", "fr", "hi", "ja", "es"].contains(String(settings.locale.prefix(2))) {
                throw SpeakWayError.message("Ink 2 supports English, French, Hindi, Japanese and Spanish. Choose Ink Whisper for this speech language, or use another provider.")
            }
            var url = URLComponents(string: "wss://api.cartesia.ai/stt/websocket")!
            url.queryItems = [URLQueryItem(name: "model", value: settings.cartesiaModel),
                URLQueryItem(name: "encoding", value: "pcm_s16le"), URLQueryItem(name: "sample_rate", value: "24000"),
                URLQueryItem(name: "cartesia_version", value: "2026-08-14")]
            if settings.cartesiaModel == "ink-whisper" { url.queryItems?.append(URLQueryItem(name: "language", value: String(settings.locale.prefix(2)))) }
            request = URLRequest(url: url.url!)
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        } else {
            request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let network = URLSession(configuration: configuration); networkSession = network
        let socket = network.webSocketTask(with: request); self.socket = socket
        socket.maximumMessageSize = 2 * 1024 * 1024
        socket.resume()
        receiveTask = Task {
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    let data: Data
                    switch message { case .string(let value): data = Data(value.utf8); case .data(let value): data = value; @unknown default: continue }
                    guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    if event["type"] as? String == "session.updated" { ready = true }
                    if isCartesia {
                        try cartesiaTranscript.consume(event); onText(cartesiaTranscript.text)
                    } else {
                        try transcript.consume(event); onText(transcript.text)
                    }
                }
            } catch {
                if !cancelled && !Task.isCancelled { failure = error; onFailure(error) }
            }
        }
        // Do not gate the microphone on a network round trip. Early audio queues
        // locally and is sent only after the provider accepts its configuration.
        let sender = BufferedAudioSender(prepare: { [self] in
            if isCartesia {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    socket.sendPing { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                ready = true
            } else {
                try await send(ProviderWire.transcriptionConfiguration(model: settings.transcriptionModel, locale: settings.locale))
                try await waitUntil(seconds: 15) { self.ready }
            }
        }, send: { [self] data in
            if isCartesia { try await socket.send(.data(data)) }
            else { try await send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()]) }
            byteCount += data.count
        }, onFailure: { [weak self] error in
            guard let self, !cancelled else { return }
            failure = error; onFailure(error)
        })
        self.sender = sender
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
        let archive = archive
        try await capture.start(format: format, onBuffer: { buffer in
            guard let samples = buffer.int16ChannelData?[0] else { return }
            let data = Data(bytes: samples, count: Int(buffer.frameLength) * 2)
            archive?.append(data)
            sender.append(data)
        }, onLevel: onLevel, onFailure: onFailure)
    }

    func finish() async throws -> String {
        capture.stop()
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled {
                failure = SpeakWayError.message("\(providerName) timed out while finishing your recording.")
                socket?.cancel(with: .goingAway, reason: nil)
            }
        }
        defer { watchdog.cancel(); cancel() }
        try await sender?.finish()
        guard byteCount >= 4800 else { cancel(); throw SpeakWayError.message("The recording was too short. Speak for at least a moment, then press Fn again.") }
        if isCartesia { try await socket?.send(.string("finalize")) }
        else { try await send(["type": "input_audio_buffer.commit"]) }
        try await waitUntil(seconds: 25) { self.isCartesia ? self.cartesiaTranscript.completed : self.transcript.completed }
        let text = isCartesia ? cartesiaTranscript.text : transcript.text
        if isCartesia { try? await socket?.send(.string("close")) }
        return text
    }

    private func send(_ event: [String: Any]) async throws {
        guard let socket, !cancelled else { throw CancellationError() }
        let data = try JSONSerialization.data(withJSONObject: event)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func waitUntil(seconds: Double, _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(Int(seconds * 1000)))
        while !predicate() {
            if let failure { throw failure }
            if cancelled { throw CancellationError() }
            guard ContinuousClock.now < deadline else { throw SpeakWayError.message("\(providerName) live timed out. Check your connection and model access in Settings.") }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    func cancel() {
        cancelled = true; capture.stop(); sender?.cancel(); receiveTask?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil); networkSession?.invalidateAndCancel()
    }
}
