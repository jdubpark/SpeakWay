import AppKit
import SwiftUI
import Combine
import Speech
import FoundationModels
import AVFoundation
import SpeakWayCore

@main struct SpeakWayMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var window: NSWindow!
    private var popover: PopoverController!
    private var status: NSStatusItem!
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        #if DEBUG
        if arguments.contains("--benchmark-capture") {
            Task { @MainActor in
                guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { exit(2) }
                let capture = AudioCapture()
                let start = ContinuousClock.now
                do {
                    let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
                    try await capture.start(format: format, onBuffer: { _ in }, onLevel: { _ in }, onFailure: { _ in })
                    let elapsed = start.duration(to: .now)
                    capture.stop()
                    let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
                    print("Microphone ready: \(Int(ms)) ms (local capture only; no network or archive)")
                    exit(0)
                } catch { capture.stop(); fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        #endif
        if arguments.contains("--diagnostics") || arguments.contains("--transcribe-file") || arguments.contains("--local-process") {
            runCommand(arguments); return
        }
        installMainMenu()
        model = AppModel()
        popover = PopoverController(model: model)
        model.showWindow = { [weak self] in self?.showWindow() }
        model.showOverlay = { [weak self] in self?.popover.show() }
        model.hideOverlay = { [weak self] in self?.popover.hide() }
        model.focusResultEditor = { [weak self] in self?.popover.focusForEditing() }
        model.shortcuts.isPopoverVisible = { [weak self] in self?.popover.panel.isVisible == true }
        model.prepareForCapture = { [weak self] in
            guard let self else { return }
            if window?.isKeyWindow == true {
                window.orderOut(nil)
            }
            if popover.panel.isKeyWindow || NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                popover.hide()
                model.textAccess.lastExternalApp?.activate()
            }
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SpeakWay")
        status.button?.target = self; status.button?.action = #selector(statusClicked(_:))
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.toolTip = "Click to speak · Right-click for modes and settings"
        model.voice.$phase.receive(on: RunLoop.main).sink { [weak self] phase in
            self?.status.button?.image = NSImage(systemSymbolName: phase == .listening ? "stop.circle.fill" : "waveform", accessibilityDescription: phase == .listening ? "Send speech" : "SpeakWay")
            if phase == .idle { self?.popover.hide() }
            else { self?.popover.show() }
        }.store(in: &cancellables)
        #if DEBUG
        if OverlayPreview.isEnabled {
            let index = arguments.firstIndex(of: "--preview-overlay")
            let state = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "launcher"
            OverlayPreview.present(state, model: model, popover: popover)
            return
        }
        #endif
        // First-time setup starts in the small launcher. Configured launches stay
        // in the menu bar until a shortcut, click, or explicit reopen.
        if !model.savedKeys.contains(.openAI) {
            DispatchQueue.main.async { [weak self] in self?.popover.show() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard popover != nil else { return false }
        popover.show(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model?.cancel() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.cancel()
        RecordingArchive.whenSaved { MainActor.assumeIsolated { sender.reply(toApplicationShouldTerminate: true) } }
        return .terminateLater
    }

    private func installMainMenu() {
        let main = NSMenu()
        let application = NSMenuItem(); main.addItem(application)
        let appMenu = NSMenu(); application.submenu = appMenu
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self; appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit SpeakWay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let edit = NSMenuItem(); main.addItem(edit)
        let editMenu = NSMenu(title: "Edit"); edit.submenu = editMenu
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        #if DEBUG
        if OverlayPreview.isEnabled {
            let preview = NSMenuItem(); main.addItem(preview)
            let menu = NSMenu(title: "Preview"); preview.submenu = menu
            for state in ["launcher", "preparing", "listening", "processing", "dictation", "translation", "search", "long", "error", "live typing", "cmux insertion"] {
                let item = NSMenuItem(title: state.capitalized, action: #selector(previewState(_:)), keyEquivalent: "")
                item.representedObject = state; item.target = self; menu.addItem(item)
            }
            menu.addItem(.separator())
            for name in ["Light", "Dark"] {
                let item = NSMenuItem(title: name, action: #selector(previewAppearance(_:)), keyEquivalent: "")
                item.target = self; menu.addItem(item)
            }
        }
        #endif
        NSApp.mainMenu = main
    }

    #if DEBUG
    @objc private func previewState(_ sender: NSMenuItem) {
        guard let state = sender.representedObject as? String else { return }
        model.cancel(); OverlayPreview.present(state, model: model, popover: popover)
    }
    @objc private func previewAppearance(_ sender: NSMenuItem) {
        NSApp.appearance = NSAppearance(named: sender.title == "Dark" ? .darkAqua : .aqua)
    }
    #endif

    private func showWindow() {
        if window == nil {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "SpeakWay"; window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: WorkspaceView(model: model, voice: model.voice))
            window.isReleasedWhenClosed = false; window.center()
        }
        popover.hide()
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }

    @objc private func statusClicked(_ sender: Any) {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() }
        else { model.toggle() }
    }
    private func showMenu() {
        let menu = NSMenu()
        for mode in VoiceMode.allCases {
            let item = NSMenuItem(title: "\(mode.title)   \(mode.shortcut)", action: #selector(chooseMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue; item.target = self
            item.state = model.mode == mode ? .on : .off; item.isEnabled = !model.voice.busy
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: model.voice.result == nil ? "Show SpeakWay" : "Show result", action: #selector(openMain), keyEquivalent: ""); open.target = self; menu.addItem(open)
        let workspace = NSMenuItem(title: "Open workspace…", action: #selector(openWorkspace), keyEquivalent: ""); workspace.target = self; workspace.isEnabled = !model.voice.busy; menu.addItem(workspace)
        let history = NSMenuItem(title: "History…", action: #selector(openHistory), keyEquivalent: ""); history.target = self; history.isEnabled = !model.voice.busy; menu.addItem(history)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","); settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SpeakWay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: status.button?.bounds.height ?? 20), in: status.button)
    }
    @objc private func chooseMode(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let mode = VoiceMode(rawValue: raw) { model.mode = mode; model.start() } }
    @objc private func openMain() { popover.show() }
    @objc private func openWorkspace() { guard !model.voice.busy else { return }; model.showingSettings = false; model.showingHistory = false; showWindow() }
    @objc private func openHistory() { model.openHistory() }
    @objc private func openSettings() { model.openSettings() }

    private func runCommand(_ arguments: [String]) {
        Task {
            do {
                if arguments.contains("--diagnostics") {
                    let data: [String: Any] = ["localSpeechAvailable": SpeechTranscriber.isAvailable,
                        "installedSpeechLocales": await SpeechTranscriber.installedLocales.map(\.identifier).sorted(),
                        "localAI": TextProcessor.localAvailability, "accessibility": TextAccess.trusted,
                        "inputMonitoring": CGPreflightListenEventAccess()]
                    print(String(decoding: try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
                } else if let index = arguments.firstIndex(of: "--transcribe-file"), arguments.count > index + 1 {
                    let speech = LocalSpeech(locale: "en-US")
                    print(try await speech.transcribeFile(URL(fileURLWithPath: arguments[index + 1])))
                } else if let index = arguments.firstIndex(of: "--local-process"), arguments.count > index + 1 {
                    var settings = Settings(); settings.textProvider = .apple
                    let mode = arguments.contains("--ask") ? VoiceMode.ask : arguments.contains("--translate") ? .translate : .dictate
                    let selectionIndex = arguments.firstIndex(of: "--selection")
                    let selection = selectionIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? ""
                    let result = try await TextProcessor.run(TextRequest(mode: mode, transcript: arguments[index + 1], selection: selection), settings: settings, key: "")
                    print(result.text)
                } else { throw SpeakWayError.message("Missing command argument.") }
                exit(0)
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
    }
}
