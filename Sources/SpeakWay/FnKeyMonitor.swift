import AppKit
import SpeakWayCore

@MainActor final class FnKeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var router = FnShortcut()
    var isRecording: () -> Bool = { false }
    var isBusy: () -> Bool = { false }
    var isPopoverVisible: () -> Bool = { false }
    var onAction: (FnShortcut.Action) -> Void = { _ in }
    var connected: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                Unmanaged<FnKeyMonitor>.fromOpaque(info).takeUnretainedValue().handle(type, event: event)
            }
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: CGEventMask(mask), callback: callback,
                               userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            router.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        var action: FnShortcut.Action?
        var consume = false
        if type == .flagsChanged {
            action = router.flags(fn: event.flags.contains(.maskSecondaryFn), shift: event.flags.contains(.maskShift), recording: isRecording())
            consume = code == 63
        } else if type == .keyDown {
            let fnSpace = code == 49 && router.isFnHeld
            let canDismiss = isBusy() || isPopoverVisible()
            let escape = code == 53 && canDismiss
            action = router.keyDown(space: code == 49, escape: code == 53,
                                    repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, busy: canDismiss)
            consume = fnSpace || escape
        } else if type == .keyUp { consume = code == 49 && router.isFnHeld }
        if let action { onAction(action) }
        return consume ? nil : Unmanaged.passUnretained(event)
    }
}
