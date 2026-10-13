import Foundation

public struct TextInputSnapshot: Equatable {
    public let text: String
    public let selection: NSRange
    public init(text: String, selection: NSRange) { self.text = text; self.selection = selection }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Accessibility ranges use UTF-16 offsets. Canonical String equality can
        // hide a change in those offsets (for example, a composed accent).
        lhs.selection == rhs.selection && lhs.text.utf16.elementsEqual(rhs.text.utf16)
    }
}

public struct LiveTextEdit {
    public let before: TextInputSnapshot
    public let range: NSRange
    public let text: String
    public let after: TextInputSnapshot
}

@MainActor public protocol LiveDictationTarget: AnyObject {
    var initialSnapshot: TextInputSnapshot? { get }
    /// Returns nil if the original app/field is no longer focused or readable.
    func read() -> TextInputSnapshot?
    /// Rechecks `before`, replaces only `range`, and reads back the result.
    /// A target must never use an unverified paste or backspace fallback.
    func replace(_ edit: LiveTextEdit) -> TextInputSnapshot?
}

public enum LiveDictationStatus: Equatable { case off, typing, paused, unavailable, finished }

/// Owns only the span inserted at the initial, empty caret. Any external edit,
/// selection change, or failed acknowledgement permanently ends this lease.
@MainActor final class LiveDictationSession {
    private let target: any LiveDictationTarget
    private let prefix: String
    private let suffix: String
    private var expected: TextInputSnapshot
    private var owned: NSRange
    private(set) var status: LiveDictationStatus = .typing

    init?(target: any LiveDictationTarget) {
        guard let initial = target.initialSnapshot, initial.selection.length == 0,
              initial.selection.location >= 0, initial.selection.location <= initial.text.utf16.count,
              let range = Range(initial.selection, in: initial.text) else { return nil }
        let prefix = String(initial.text[..<range.lowerBound])
        let suffix = String(initial.text[range.upperBound...])
        guard prefix.utf16.count == initial.selection.location,
              (prefix + suffix).utf16.elementsEqual(initial.text.utf16) else { return nil }
        self.target = target; expected = initial; owned = initial.selection
        self.prefix = prefix; self.suffix = suffix
    }

    func update(_ text: String) {
        guard status == .typing else { return }
        guard target.read() == expected else { status = .paused; return }
        let after = TextInputSnapshot(text: prefix + text + suffix,
                                      selection: NSRange(location: owned.location + text.utf16.count, length: 0))
        guard after != expected else { return }
        let edit = LiveTextEdit(before: expected, range: owned, text: text, after: after)
        guard target.replace(edit) == after else { status = .paused; return }
        expected = after; owned.length = text.utf16.count
    }

    func finish(_ text: String) {
        update(text)
        if status == .typing { status = .finished }
    }

    func cancel() {
        // Once the user edits/moves, even rollback is forbidden.
        if status == .typing { update("") }
        stop()
    }

    func stop() { if status == .typing { status = .paused } }
}
