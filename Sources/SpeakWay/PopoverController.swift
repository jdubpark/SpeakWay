import AppKit
import SwiftUI
import SpeakWayCore

final class FloatingPanel: NSPanel {
    var acceptsKeyboard = false
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
}

@MainActor final class PopoverController {
    let panel: FloatingPanel
    private let model: AppModel
    private var screen: NSScreen?
    private var layout: PopoverLayout?
    private var displayObserver: NSObjectProtocol?
    private var escapeMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = FloatingPanel(contentRect: .zero,
                              styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                              backing: .buffered, defer: false)
        panel.title = "SpeakWay popover"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let host = NSHostingView(rootView: OverlayView(model: model, voice: model.voice))
        host.sizingOptions = []
        panel.contentView = host
        panel.dismiss = { [weak model] in model?.dismissPopover() }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, panel.isVisible else { return event }
            model.dismissPopover(); return nil
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                // Keep the same display when possible; recover if it was unplugged.
                self.screen = NSScreen.screens.first { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == self.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }
                self.show()
            }
        }
    }

    func show() {
        let next: PopoverLayout
        if model.choosingContinuation { next = .continuation }
        else {
            switch model.voice.phase {
            case .idle: next = .launcher
            case .preparing, .listening, .processing: next = .capture
            case .ready: next = .result(model.voice.mode)
            case .failed: next = .failure
            }
        }
        if screen == nil || !panel.isVisible || (next == .capture && layout != .capture) {
            let point = NSEvent.mouseLocation
            screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        }
        guard let screen else { return }
        let frame = next.frame(in: screen.visibleFrame)
        panel.acceptsKeyboard = next != .capture
        // A clicked result may be key. Release it before the next capture so typing
        // and delivery continue to belong to the source application.
        if next == .capture && panel.isKeyWindow { panel.orderOut(nil) }
        let animate = panel.isVisible && layout != next && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        layout = next
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.2 : 0
            panel.setFrame(frame, display: true, animate: animate)
        }
        // Never activate SpeakWay or make the panel key while presenting a result.
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    func focusForEditing() {
        guard !model.voice.busy else { return }
        show()
        panel.acceptsKeyboard = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
