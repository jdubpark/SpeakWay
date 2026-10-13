import Foundation
import Combine

@MainActor public protocol SpeechSession: AnyObject {
    func start(onText: @escaping (String) -> Void, onLevel: @escaping (Float) -> Void, onFailure: @escaping (Error) -> Void) async throws
    func finish() async throws -> String
    func cancel()
}

@MainActor public final class VoiceController: ObservableObject {
    public enum Phase: String { case idle, preparing, listening, processing, ready, failed }
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var mode: VoiceMode = .dictate
    @Published public private(set) var transcript = ""
    @Published public private(set) var preContext = ""
    @Published public private(set) var result: TextResult?
    @Published public private(set) var resultWasEdited = false
    @Published public private(set) var error: String?
    @Published public private(set) var level: Float = 0
    @Published public private(set) var liveDictationStatus: LiveDictationStatus = .off
    public var busy: Bool { [.preparing, .listening, .processing].contains(phase) }
    public var didFinish: ((VoiceMode, TextResult) -> Void)?
    private var generation: UUID?
    private var session: (any SpeechSession)?
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var process: ((TextRequest) async throws -> TextResult)?
    private var selection = ""
    private var targetLanguage = "English"
    private var webSearch = false
    private var liveSession: LiveDictationSession?
    private var liveUpdate: Task<Void, Never>?
    public init() {}

    public func start(mode: VoiceMode, selection: String, preContext: String = "", settings: Settings, session: any SpeechSession,
                      liveTarget: (any LiveDictationTarget)? = nil,
                      process: @escaping (TextRequest) async throws -> TextResult) {
        guard !busy else { return }
        if mode == .translate && selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && preContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reject("Select text in another app first. If the app does not expose its selection, copy it and use ‘Use clipboard’.")
            return
        }
        guard selection.count <= 24_000 else { reject("Select a shorter passage (up to 24,000 characters)."); return }
        guard preContext.count <= 24_000 else { reject("Use a shorter transcription as context (up to 24,000 characters)."); return }
        self.mode = mode; self.selection = mode == .dictate ? "" : selection
        self.preContext = preContext
        self.targetLanguage = settings.targetLanguage; self.webSearch = settings.webSearch
        self.process = process; self.session = session
        liveUpdate?.cancel(); liveUpdate = nil; liveSession?.stop(); liveSession = nil
        liveDictationStatus = .off
        if mode == .dictate && settings.autoInsert && settings.liveDictation {
            liveSession = liveTarget.flatMap { LiveDictationSession(target: $0) }
            liveDictationStatus = liveSession == nil ? .unavailable : .typing
        }
        transcript = ""; result = nil; resultWasEdited = false; error = nil; level = 0
        let id = UUID(); generation = id; phase = .preparing
        work = Task { [self] in
            do {
                try await session.start(onText: { [weak self] text in
                    guard let self, self.generation == id else { return }
                    self.transcript = text
                    self.scheduleLiveUpdate(id: id)
                }, onLevel: { [weak self] level in
                    guard let self, self.generation == id else { return }
                    self.level = level
                }, onFailure: { [weak self] error in self?.fail(error, id: id) })
                guard generation == id, !Task.isCancelled else { session.cancel(); return }
                phase = .listening
                deadline = Task {
                    try? await Task.sleep(for: .seconds(300))
                    if !Task.isCancelled, generation == id, phase == .listening { finish() }
                }
            } catch { fail(error, id: id) }
        }
    }

    public func finish() {
        guard phase == .listening, let id = generation, let session, let process else { return }
        phase = .processing; level = 0; deadline?.cancel()
        work = Task {
            do {
                let finalText = try await session.finish()
                guard generation == id, !Task.isCancelled else { return }
                transcript = finalText
                scheduleLiveUpdate(id: id)
                let request = TextRequest(mode: mode, transcript: finalText, selection: selection,
                                          preContext: preContext,
                                          targetLanguage: targetLanguage, webSearch: webSearch)
                try request.validate()
                let output = try await process(request)
                guard generation == id, !Task.isCancelled else { return }
                guard !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SpeakWayError.message("The model returned no text. Your transcript is still available.")
                }
                liveUpdate?.cancel(); liveUpdate = nil
                result = output; phase = .ready; self.session = nil
                didFinish?(mode, output)
            } catch { fail(error, id: id) }
        }
    }

    public func cancel() {
        generation = nil; work?.cancel(); deadline?.cancel(); session?.cancel()
        liveUpdate?.cancel(); liveUpdate = nil; liveSession?.cancel(); liveSession = nil
        liveDictationStatus = .off
        work = nil; session = nil; process = nil; level = 0; phase = .idle
        transcript = ""; result = nil; error = nil; selection = ""; preContext = ""
    }

    public func reject(_ message: String) {
        guard !busy else { return }
        liveUpdate?.cancel(); liveUpdate = nil; liveSession?.stop(); liveSession = nil
        liveDictationStatus = .off
        result = nil; transcript = ""; preContext = ""; error = message; phase = .failed
    }

    private func fail(_ error: Error, id: UUID) {
        guard generation == id else { return }
        generation = nil; deadline?.cancel(); session?.cancel(); session = nil
        liveUpdate?.cancel(); liveUpdate = nil; liveSession?.stop()
        if let liveSession { liveDictationStatus = liveSession.status }
        self.error = error.localizedDescription; level = 0; phase = .failed
    }

    @discardableResult public func editResult(_ text: String) -> Bool {
        guard phase == .ready, mode == .dictate, let result,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 24_000 else { return false }
        self.result = TextResult(text: text, sources: result.sources)
        resultWasEdited = true
        // Editing never replays automatic insertion or changes raw speech.
        return true
    }

    /// Called after the result is published, instead of inserting it a second time.
    public func completeLiveDictation() {
        guard phase == .ready, mode == .dictate, let result, let liveSession else { return }
        liveSession.finish(RichTextDocument(result.text).plainText)
        liveDictationStatus = liveSession.status
    }

    private func scheduleLiveUpdate(id: UUID) {
        guard liveDictationStatus == .typing, liveUpdate == nil else { return }
        // Coalesce streaming deltas; no extra model requests or per-token AX work.
        liveUpdate = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled, generation == id, busy else { return }
            liveUpdate = nil
            liveSession?.update(transcript)
            if let liveSession { liveDictationStatus = liveSession.status }
        }
    }
}
