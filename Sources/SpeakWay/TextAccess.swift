import AppKit
import ApplicationServices
import SpeakWayCore

@MainActor final class TextAccess {
    enum InsertionOutcome { case inserted, pasteRequested, terminalSent, unavailable }

    struct Target {
        let app: NSRunningApplication
        let element: AXUIElement
        let value: String?
        let range: CFRange?
        let selection: String
        let isCmuxTerminal: Bool
        let inputRevision: UInt64
    }

    private(set) var lastExternalApp: NSRunningApplication?
    private var observer: NSObjectProtocol?
    private var inputMonitor: Any?
    private var inputRevision: UInt64 = 0

    init() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApp = app
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.lastExternalApp?.processIdentifier != app.processIdentifier { self.inputRevision &+= 1 }
                self.lastExternalApp = app
            }
        }
    }

    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private func focused(in app: NSRunningApplication) -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.1)
        guard let value = attribute(kAXFocusedUIElementAttribute, of: application), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func range(of element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, of: element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var range = CFRange(); guard AXValueGetValue(ax, .cfRange, &range) else { return nil }
        return range
    }

    private func secure(_ element: AXUIElement) -> Bool {
        let subrole = attribute(kAXSubroleAttribute, of: element) as? String
        return subrole == kAXSecureTextFieldSubrole
    }

    func capture() -> Target? {
        guard Self.trusted else { return nil }
        if inputMonitor == nil {
            inputMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] _ in
                MainActor.assumeIsolated { self?.inputRevision &+= 1 }
            }
        }
        let front = NSWorkspace.shared.frontmostApplication
        let app = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternalApp : front
        guard let app, !app.isTerminated, let element = focused(in: app), !secure(element) else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.1)
        return Target(app: app, element: element, value: attribute(kAXValueAttribute, of: element) as? String,
                      range: range(of: element), selection: attribute(kAXSelectedTextAttribute, of: element) as? String ?? "",
                      isCmuxTerminal: isCmuxTerminal(element, app: app), inputRevision: inputRevision)
    }

    private func isCmuxTerminal(_ element: AXUIElement, app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.cmuxterm.app"
            && attribute(kAXRoleAttribute, of: element) as? String == kAXTextAreaRole
            && attribute(kAXHelpAttribute, of: element) as? String == "Terminal content area"
    }

    func insert(_ document: RichTextDocument, into target: Target) -> InsertionOutcome {
        // Never write to a newly focused field or overwrite text edited while AI was working.
        guard Self.trusted, !target.app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier,
              let current = focused(in: target.app), CFEqual(current, target.element), !secure(current) else { return .unavailable }
        if target.isCmuxTerminal {
            // cmux 0.64 exposes AXValue as append-at-cursor, not a replaceable
            // document. Never use this exception for another editor or control.
            guard inputMonitor != nil, inputRevision == target.inputRevision,
                  isCmuxTerminal(current, app: target.app), target.selection.isEmpty,
                  (attribute(kAXSelectedTextAttribute, of: current) as? String ?? "").isEmpty,
                  let text = TerminalDictation.insertionText(document.plainText) else { return .unavailable }
            var writable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(current, kAXValueAttribute as CFString, &writable) == .success,
                  writable.boolValue else { return .unavailable }
            return AXUIElementSetAttributeValue(current, kAXValueAttribute as CFString, text as CFString) == .success ? .terminalSent : .unavailable
        }
        guard
              let original = target.value, let originalRange = target.range,
              attribute(kAXValueAttribute, of: current) as? String == original,
              let currentRange = range(of: current), currentRange.location == originalRange.location,
              currentRange.length == originalRange.length else { return .unavailable }
        var settable = DarwinBoolean(false)
        if !document.hasFormatting, AXUIElementIsAttributeSettable(current, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue {
            return AXUIElementSetAttributeValue(current, kAXSelectedTextAttribute as CFString, document.plainText as CFString) == .success ? .inserted : .unavailable
        }
        // Some editors expose selection but only accept standard Paste. Never simulate Return.
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return .unavailable }
        Self.copy(document)
        let ownChange = pasteboard.changeCount
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if pasteboard.changeCount == ownChange {
                pasteboard.clearContents(); pasteboard.writeObjects(previous)
            }
        }
        return .pasteRequested
    }

    func liveTarget(for target: Target) -> (any LiveDictationTarget)? {
        guard !target.isCmuxTerminal else { return nil }
        AXUIElementSetMessagingTimeout(target.element, 0.1)
        for name in [kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute] {
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(target.element, name as CFString, &settable) == .success,
                  settable.boolValue else { return nil }
        }
        return LiveTarget(access: self, target: target)
    }

    private final class LiveTarget: LiveDictationTarget {
        let access: TextAccess
        let target: Target
        var initialSnapshot: TextInputSnapshot? {
            guard let value = target.value, let range = target.range else { return nil }
            return TextInputSnapshot(text: value, selection: NSRange(location: range.location, length: range.length))
        }
        init(access: TextAccess, target: Target) { self.access = access; self.target = target }

        func read() -> TextInputSnapshot? {
            guard TextAccess.trusted, !target.app.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier,
                  let current = access.focused(in: target.app), CFEqual(current, target.element), !access.secure(current),
                  let text = access.attribute(kAXValueAttribute, of: current) as? String,
                  let range = access.range(of: current) else { return nil }
            if let selections = access.attribute(kAXSelectedTextRangesAttribute, of: current) as? [Any], selections.count > 1 { return nil }
            return TextInputSnapshot(text: text, selection: NSRange(location: range.location, length: range.length))
        }

        func replace(_ edit: LiveTextEdit) -> TextInputSnapshot? {
            guard read() == edit.before else { return nil }
            if edit.range != edit.before.selection, !select(edit.range) { return nil }
            // Selection and replacement are separate AX calls. Recheck the field,
            // complete value, and exact owned selection immediately before writing.
            let selected = TextInputSnapshot(text: edit.before.text, selection: edit.range)
            guard read() == selected else { return nil }
            guard AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, edit.text as CFString) == .success else {
                if read() == selected { _ = select(edit.before.selection) }
                return nil
            }
            return read()
        }

        private func select(_ range: NSRange) -> Bool {
            var value = CFRange(location: range.location, length: range.length)
            guard let axRange = AXValueCreate(.cfRange, &value) else { return false }
            return AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, axRange) == .success
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }

    static func copy(_ document: RichTextDocument) {
        let item = NSPasteboardItem()
        item.setString(document.plainText, forType: .string)
        item.setString(document.html, forType: .html)
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([item])
    }
}
