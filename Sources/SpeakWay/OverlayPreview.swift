#if DEBUG
import Foundation
import AppKit
import ApplicationServices
import SpeakWayCore

/// Developer-only native previews. No microphone, credentials, or archive.
/// The explicit live-typing fixture writes only into a labeled TextEdit document.
@MainActor enum OverlayPreview {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("--preview-overlay") || Bundle.main.object(forInfoDictionaryKey: "SpeakWayPreview") as? Bool == true
    }
    static func present(_ state: String, model: AppModel, popover: PopoverController) {
        if state == "live typing" { presentLiveTyping(model: model, popover: popover); return }
        if state == "cmux insertion" { presentCmuxInsertion(model: model, popover: popover); return }
        if state == "launcher" { DispatchQueue.main.async { popover.show() }; return }
        if state == "error" { model.voice.reject("Preview: the connection was interrupted before speech could be captured. Try recording again."); return }
        let mode: VoiceMode = state == "translation" ? .translate : state == "search" ? .ask : .dictate
        model.mode = mode
        let speech = PreviewSpeech(preparing: state == "preparing")
        let text: String
        var sources: [SourceLink] = []
        switch mode {
        case .translate: text = "Preview translation\n\n수요일 오후 두 시에 큰 회의실에서 만나요.\n\n- 디자인 검토\n- 다음 단계 확인"
        case .ask:
            text = "## Preview: designing for the Mac\n\nKeep **keyboard focus** in the app where someone is working. Show a compact listening indicator, then let the result expand from the same position.\n\n1. Speak from any app.\n2. Review the answer and its sources.\n3. Copy only what you need."
            sources = [SourceLink(title: "Human Interface Guidelines", url: URL(string: "https://developer.apple.com/design/human-interface-guidelines")!),
                       SourceLink(title: "SwiftUI", url: URL(string: "https://developer.apple.com/swiftui/")!)]
        case .dictate:
            text = "## Preview meeting notes\n\nMeet in the **large room on Wednesday at two**.\n\n- Review the design.\n- Confirm the next steps.\n\n1. Send the draft to Bob.\n2. Book the room."
        }
        let previewResult = TextResult(text: state == "long" ? Array(repeating: text, count: 8).joined(separator: "\n\n") : text, sources: sources)
        model.voice.didFinish = { _, _ in model.delivery = "Preview · No text was inserted or saved" }
        model.voice.start(mode: mode, selection: mode == .translate ? "Meet on Wednesday." : "", settings: Settings(), session: speech) { _ in
            if state == "processing" { try await Task.sleep(for: .seconds(300)) }
            return previewResult
        }
        if state != "listening" && state != "preparing" {
            Task {
                while model.voice.phase == .preparing { await Task.yield() }
                if model.voice.phase == .listening { model.voice.finish() }
            }
        }
    }

    private static func presentLiveTyping(model: AppModel, popover: PopoverController) {
        // CUA can invoke menus without activating their app. The explicit test
        // scenario activates TextEdit, then still verifies its document marker.
        guard let editor = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
            model.voice.reject("Open the labeled TextEdit test document first."); return
        }
        model.prepareForCapture?(); popover.hide(); editor.activate()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            startLiveTyping(model: model, popover: popover)
        }
    }

    private static func presentCmuxInsertion(model: AppModel, popover: PopoverController) {
        guard let terminal = NSRunningApplication.runningApplications(withBundleIdentifier: "com.cmuxterm.app").first else { return }
        model.prepareForCapture?(); popover.hide(); terminal.activate()
        Task { @MainActor [model] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let target = model.textAccess.capture(), target.isCmuxTerminal else {
                model.voice.reject("Focus the cmux test terminal first."); return
            }
            var window: CFTypeRef?; var title: CFTypeRef?
            if AXUIElementCopyAttributeValue(target.element, kAXWindowAttribute as CFString, &window) == .success,
               let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
                AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
            }
            guard (title as? String)?.contains("SpeakWay input check") == true else {
                model.voice.reject("Preview writes only in a cmux workspace named ‘SpeakWay input check’."); return
            }
            model.mode = .dictate
            model.voice.didFinish = { [weak model] _, output in
                Task { @MainActor in
                    await Task.yield()
                    guard let model, model.voice.phase == .ready else { return }
                    let outcome = model.textAccess.insert(RichTextDocument(output.text), into: target)
                    model.delivery = outcome == .terminalSent ? "Preview · Final text sent to cmux as one line" : "Preview · cmux input changed; no text sent"
                }
            }
            model.voice.start(mode: .dictate, selection: "", settings: Settings(), session: LivePreviewSpeech()) { _ in
                TextResult(text: "Wednesday at two.\n\n- Bring notes\n- Book the room")
            }
        }
    }

    private static func startLiveTyping(model: AppModel, popover: PopoverController) {
        guard let target = model.textAccess.capture() else { model.voice.reject("Preview could not read the focused field."); return }
        guard target.app.bundleIdentifier == "com.apple.TextEdit" else { model.voice.reject("Preview target is \(target.app.localizedName ?? "unknown"). Focus TextEdit first."); return }
        guard target.value?.hasPrefix("SpeakWay live test:") == true else { model.voice.reject("Preview needs a TextEdit document beginning with ‘SpeakWay live test:’."); return }
        guard let liveTarget = model.textAccess.liveTarget(for: target) else { model.voice.reject("Preview target does not support verified text-range replacement."); return }
        model.mode = .dictate
        var settings = Settings(); settings.liveDictation = true; settings.saveHistory = false
        model.prepareForCapture?(); popover.hide(); target.app.activate()
        model.voice.didFinish = { [weak model] _, _ in
            Task { @MainActor in
                await Task.yield()
                guard let model, model.voice.phase == .ready else { return }
                model.voice.completeLiveDictation()
                model.delivery = model.voice.liveDictationStatus == .finished ? "Preview · Live text updated in TextEdit" : "Preview · Live typing stopped; text left unchanged"
            }
        }
        model.voice.start(mode: .dictate, selection: "", settings: settings, session: LivePreviewSpeech(), liveTarget: liveTarget) { _ in
            TextResult(text: "Wednesday at two.\n\n- Bring notes\n- Book the room")
        }
    }

    @MainActor private final class LivePreviewSpeech: SpeechSession {
        private var update: Task<Void, Never>?
        func start(onText: @escaping (String) -> Void, onLevel: @escaping (Float) -> Void, onFailure: @escaping (Error) -> Void) async throws {
            onText("Tuesday at three."); onLevel(0.35)
            update = Task {
                // Keep synthetic callbacks coming so manual edits can exercise
                // the interrupted listening state without a timing race.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    onText("Tuesday at three. Actually Wednesday at two.")
                }
            }
        }
        func finish() async throws -> String { update?.cancel(); return "Tuesday at three. Actually Wednesday at two. Make a list: bring notes, book the room." }
        func cancel() { update?.cancel() }
    }

    @MainActor private final class PreviewSpeech: SpeechSession {
        let preparing: Bool
        init(preparing: Bool) { self.preparing = preparing }
        func start(onText: @escaping (String) -> Void, onLevel: @escaping (Float) -> Void, onFailure: @escaping (Error) -> Void) async throws {
            if preparing { try await Task.sleep(for: .seconds(300)) }
            onText("Preview: book the small room for Tuesday. Oh wait, that’s incorrect. I meant the large room on Wednesday at two. Make these bullet points: review the design, confirm the next steps. Number one, send the draft to Alice, sorry Bob. Number two, book the room.")
            onLevel(0.45)
        }
        func finish() async throws -> String { "Preview: the small room Tuesday… oh wait, I meant the large room Wednesday at two. Send it to Alice, sorry, Bob. Make the actions a list." }
        func cancel() {}
    }
}
#endif
