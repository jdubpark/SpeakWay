import AppKit
import Combine
import SpeakWayCore

@MainActor final class AppModel: ObservableObject {
    let voice = VoiceController()
    let textAccess = TextAccess()
    let shortcuts = FnKeyMonitor()
    @Published var mode: VoiceMode = .dictate
    @Published var settings: Settings
    @Published var showingSettings = false
    @Published var showingHistory = false
    @Published var selectedText = ""
    @Published var selectionApp = ""
    @Published var delivery = ""
    @Published var shortcutReady = false
    @Published var accessibilityReady = false
    @Published var savedKeys: Set<CredentialProvider> = []
    @Published var historyStatus = ""
    @Published var historyRevision = 0
    @Published private(set) var terminalDeliveryPending = false
    @Published var editingResult = false
    @Published var resultDraft = ""
    @Published var editError = ""
    var focusResultEditor: (() -> Void)?
    var showWindow: (() -> Void)?
    var showOverlay: (() -> Void)?
    var hideOverlay: (() -> Void)?
    var prepareForCapture: (() -> Void)?
    private var target: TextAccess.Target?
    private var recordingArchive: RecordingArchive?
    private var historyEntryID: UUID?
    private var deliveryTask: Task<Void, Never>?
    private var turnID = UUID()
    @Published private(set) var pendingContext = PendingContext()
    private var listeningObserver: AnyCancellable?
    private var keys: [CredentialProvider: String] = [:]
    private var permissionTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"), let stored = try? JSONDecoder().decode(Settings.self, from: data) { settings = stored }
        else { settings = Settings() }
        listeningObserver = voice.$phase.sink { [weak self] phase in
            guard let self else { return }
            if phase == .listening, voice.mode != .dictate || !voice.preContext.isEmpty {
                pendingContext.recordingBegan()
            }
            if phase == .failed {
                if voice.liveDictationStatus != .off { delivery = liveDelivery }
                archiveCurrentTurn(result: nil, error: voice.error)
            }
        }
        #if DEBUG
        // Native UI previews use synthetic speech and never load keys, start an
        // event tap, write preferences, or request microphone access.
        if OverlayPreview.isEnabled { return }
        #endif
        let key = Keychain.read(.openAI)
        if !key.isEmpty { keys[.openAI] = key; savedKeys.insert(.openAI) }
        saveSettings()
        shortcuts.isRecording = { [weak voice] in voice?.phase == .listening }
        shortcuts.isBusy = { [weak voice] in voice?.busy == true }
        shortcuts.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .start(let mode):
                guard !voice.busy else { return }; self.mode = mode; start()
            case .finish: voice.finish()
            case .cancel: dismissPopover()
            }
        }
        voice.didFinish = { [weak self] mode, output in
            guard let self else { return }
            let shouldInsert = mode == .dictate && settings.autoInsert
            let isLive = voice.liveDictationStatus != .off
            delivery = isLive ? liveDelivery : shouldInsert ? "Ready to insert" : mode == .dictate ? "Ready to copy · Auto-insert is off" : "Only shown here · Copy when you need it"
            showOverlay?()
            // Publish the corrected result first. Delivery takes the next main-actor
            // turn; archival only enqueues background work and cannot gate it.
            let id = turnID
            deliveryTask = Task { [weak self] in
                await Task.yield()
                guard let self, !Task.isCancelled, turnID == id, voice.phase == .ready else { return }
                if isLive {
                    voice.completeLiveDictation()
                    delivery = liveDelivery
                } else if shouldInsert {
                    let outcome = target.map { self.textAccess.insert(RichTextDocument(output.text), into: $0) } ?? .unavailable
                    let appName = target?.app.localizedName ?? "your app"
                    switch outcome {
                    case .inserted: delivery = "Inserted into \(appName)"
                    case .pasteRequested: delivery = "Paste sent to \(appName). Copy if it didn’t appear."
                    case .terminalSent: delivery = "Sent to cmux as one line. Copy keeps line breaks and formatting."
                    case .unavailable: delivery = "Not inserted. The original text field is unavailable or changed."
                    }
                }
            }
            archiveCurrentTurn(result: output)
        }
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "settings") }
    }
    func saveKey(_ value: String, for provider: CredentialProvider) throws {
        try Keychain.save(value, for: provider)
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        keys[provider] = key
        if key.isEmpty { savedKeys.remove(provider) } else { savedKeys.insert(provider) }
    }
    func refreshPermissions() {
        accessibilityReady = TextAccess.trusted
        if accessibilityReady { shortcuts.start() }
        shortcutReady = shortcuts.connected
    }
    func requestPermissions() {
        TextAccess.requestPermission()
        if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }
        refreshPermissions()
    }
    func toggle() {
        if voice.phase == .listening { voice.finish() }
        else if !voice.busy { start() }
    }
    func start() {
        guard !voice.busy else { return }
        editingResult = false; editError = ""; historyEntryID = nil
        deliveryTask?.cancel(); turnID = UUID()
        recordingArchive?.discard(); recordingArchive = nil
        saveSettings(); delivery = ""; historyStatus = ""
        target = textAccess.capture()
        terminalDeliveryPending = mode == .dictate && settings.autoInsert && target?.isCmuxTerminal == true
        selectedText = mode == .dictate ? "" : pendingContext.resolve(externalSelection: target?.selection ?? "")
        selectionApp = pendingContext.usesClipboard ? "Clipboard" : target?.app.localizedName ?? ""
        guard savedKeys.contains(.openAI) else {
            voice.reject("Add your OpenAI API key in Settings to start recording.")
            showOverlay?(); return
        }
        prepareForCapture?()
        let snapshot = settings
        let key = keys[.openAI] ?? ""
        recordingArchive = snapshot.saveHistory ? RecordingArchive() : nil
        historyEntryID = recordingArchive?.id
        let speech = LiveSpeech(key: key, settings: snapshot, archive: recordingArchive)
        let liveTarget = mode == .dictate && snapshot.autoInsert && snapshot.liveDictation
            ? target.flatMap { textAccess.liveTarget(for: $0) } : nil
        var captureSettings = snapshot
        if terminalDeliveryPending { captureSettings.liveDictation = false }
        voice.start(mode: mode, selection: selectedText, preContext: pendingContext.preContext, settings: captureSettings, session: speech, liveTarget: liveTarget) { request in
            try await TextProcessor.run(request, settings: snapshot, key: key)
        }
        showOverlay?()
    }
    func useClipboard() {
        guard !voice.busy else { return }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.isEmpty else { delivery = "The clipboard has no text."; return }
        guard text.count <= 24_000 else { delivery = "Copy a shorter passage (up to 24,000 characters)."; return }
        pendingContext.useClipboard(text); selectedText = text; selectionApp = "Clipboard"
        delivery = "Clipboard text will be included in your next question or translation."
    }
    var contextExcluded: Bool { pendingContext.excludesSelection }
    var choosingContinuation: Bool { !pendingContext.preContext.isEmpty && !voice.busy && voice.phase != .failed }
    func continueFromTranscription(useRaw: Bool = false) {
        guard voice.phase == .ready, voice.mode == .dictate, let result = voice.result else { return }
        do {
            try pendingContext.useTranscription(useRaw ? voice.transcript : result.text)
            selectedText = ""; selectionApp = ""; delivery = ""
            showOverlay?()
        } catch { delivery = error.localizedDescription }
    }
    func useSelection() {
        guard !voice.busy else { return }
        pendingContext = PendingContext()
        let selection = textAccess.capture()
        selectedText = selection?.selection ?? ""; selectionApp = selection?.app.localizedName ?? ""
        delivery = selectedText.isEmpty ? "No selection is available. Select text in another app or use the clipboard." : ""
    }
    func clearContext() {
        guard !voice.busy else { return }
        let hadTranscription = !pendingContext.preContext.isEmpty
        pendingContext.clear(); selectedText = ""; selectionApp = ""; delivery = ""
        if hadTranscription { showOverlay?() }
    }
    func openSettings() {
        guard !voice.busy else { return }
        showingHistory = false; showingSettings = true; showWindow?()
    }
    func openHistory() {
        guard !voice.busy else { return }
        showingSettings = false; showingHistory = true; showWindow?()
    }
    func dismissPopover() {
        if editingResult { cancelResultEditing(); return }
        if voice.busy { cancel() } else { hideOverlay?() }
    }
    func cancel() {
        editingResult = false; editError = ""; historyEntryID = nil
        deliveryTask?.cancel(); turnID = UUID()
        voice.cancel(); pendingContext = PendingContext(); selectedText = ""; selectionApp = ""
        recordingArchive?.discard(); recordingArchive = nil
        target = nil; delivery = ""; historyStatus = ""; hideOverlay?()
        terminalDeliveryPending = false
    }
    func copyResult() {
        guard let result = voice.result else { return }
        TextAccess.copy(RichTextDocument(result.text)); delivery = "Copied"
    }

    func beginResultEditing() {
        guard voice.phase == .ready, voice.mode == .dictate, let result = voice.result else { return }
        deliveryTask?.cancel()
        resultDraft = result.text; editError = ""; editingResult = true
        focusResultEditor?()
    }

    func cancelResultEditing() { editingResult = false; resultDraft = ""; editError = "" }

    func saveResultEdit() {
        guard editingResult, voice.editResult(resultDraft) else {
            editError = "Enter between 1 and 24,000 characters."; return
        }
        let text = resultDraft
        editingResult = false; editError = ""
        delivery = "Edited. Copy to use your changes in the original app."
        guard let entryID = historyEntryID else { return }
        let turn = turnID
        historyStatus = "Saving your edit…"
        Task { [weak self] in
            do {
                _ = try await RecordingHistory.saveEdit(id: entryID, text: text)
                guard let self else { return }
                historyRevision += 1
                if turnID == turn { historyStatus = "Edit saved on this Mac" }
            } catch {
                guard let self, turnID == turn else { return }
                historyStatus = "Your edit is ready to copy, but history couldn’t be updated."
            }
        }
    }

    private var liveDelivery: String {
        switch voice.liveDictationStatus {
        case .typing: return "Applying corrections to your live text…"
        case .finished: return "Updated dictation in \(target?.app.localizedName ?? "your app"). Copy for rich formatting."
        case .paused: return "Live typing stopped. Review your text in the original app; the result is available to copy."
        case .unavailable: return "Live typing needs a supported text field with no selection. Your result is available to copy."
        case .off: return ""
        }
    }

    private func archiveCurrentTurn(result: TextResult?, error: String? = nil) {
        guard let archive = recordingArchive else { return }
        recordingArchive = nil
        let id = turnID
        historyStatus = "Saving history on this Mac…"
        archive.save(mode: mode, rawTranscript: voice.transcript, result: result, error: error) { [weak self] outcome in
            Task { @MainActor in
                guard let self else { return }
                // A previous turn can finish saving while another turn is active.
                // Refresh open history without replacing the current turn's status.
                if case .success(let entry) = outcome, entry != nil { self.historyRevision += 1 }
                guard self.turnID == id else { return }
                switch outcome {
                case .success(let entry):
                    self.historyStatus = entry == nil ? "" : entry?.audioError ?? "Saved on this Mac"
                case .failure:
                    self.historyStatus = "History couldn’t be saved. Your result is still available to copy."
                }
            }
        }
    }
}
