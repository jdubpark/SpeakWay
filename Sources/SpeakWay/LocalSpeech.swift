import AVFoundation
import Speech
import SpeakWayCore

@MainActor final class LocalSpeech: SpeechSession {
    private let locale: String
    private let capture = AudioCapture()
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Error>?
    private var finalText = ""
    private var liveText = ""
    private var cancelled = false

    init(locale: String) { self.locale = locale }

    private func makeTranscriber() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else {
            throw SpeakWayError.message("Local speech does not support this language on this Mac. Choose another speech language or OpenAI live in Settings.")
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()
        }
        try checkCancellation()
        return transcriber
    }

    private func checkCancellation() throws {
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }
    }

    private func collect(_ transcriber: SpeechTranscriber, onText: @escaping (String) -> Void,
                         onFailure: @escaping (Error) -> Void) {
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    try checkCancellation()
                    let text = String(result.text.characters)
                    if result.isFinal { finalText += text; liveText = "" }
                    else { liveText = text }
                    onText(finalText + liveText)
                }
            } catch {
                if !cancelled && !Task.isCancelled { onFailure(error) }
                throw error
            }
        }
    }

    func start(onText: @escaping (String) -> Void, onLevel: @escaping (Float) -> Void,
               onFailure: @escaping (Error) -> Void) async throws {
        let transcriber = try await makeTranscriber()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeakWayError.message("The local speech model has no compatible microphone format.")
        }
        try checkCancellation()
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(200))
        self.continuation = continuation
        collect(transcriber, onText: onText, onFailure: onFailure)
        try await analyzer.prepareToAnalyze(in: format)
        try checkCancellation()
        try await analyzer.start(inputSequence: stream)
        try checkCancellation()
        try await capture.start(format: format, onBuffer: { buffer in
            if case .dropped = continuation.yield(AnalyzerInput(buffer: buffer)) {
                Task { @MainActor in onFailure(SpeakWayError.message("Local speech could not keep up with the microphone. Try a shorter recording.")) }
            }
        }, onLevel: onLevel, onFailure: onFailure)
    }

    func finish() async throws -> String {
        capture.stop(); continuation?.finish()
        guard let analyzer else { throw SpeakWayError.message("The speech session was not started.") }
        var timedOut = false
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled { timedOut = true; await analyzer.cancelAndFinishNow() }
        }
        defer { watchdog.cancel() }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await resultsTask?.value
        try checkCancellation()
        guard !timedOut else { throw SpeakWayError.message("Local speech timed out. The partial transcript is available to copy; try a shorter recording.") }
        // Only committed local text is eligible for processing or insertion.
        guard liveText.isEmpty else { throw SpeakWayError.message("Local speech did not finalize. The partial transcript is available to copy; try again.") }
        return finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        cancelled = true; capture.stop(); continuation?.finish(); resultsTask?.cancel()
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
    }

    /// Also useful for evaluating the real speech model against saved, consented audio.
    func transcribeFile(_ url: URL) async throws -> String {
        let transcriber = try await makeTranscriber()
        let analyzer = SpeechAnalyzer(modules: [transcriber]); self.analyzer = analyzer
        collect(transcriber, onText: { _ in }, onFailure: { _ in })
        let file = try AVAudioFile(forReading: url)
        let last = try await analyzer.analyzeSequence(from: file)
        if let last { try await analyzer.finalizeAndFinish(through: last) }
        else { await analyzer.cancelAndFinishNow() }
        try await resultsTask?.value
        return finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
