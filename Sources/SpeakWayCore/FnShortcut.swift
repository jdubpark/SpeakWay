import Foundation

/// Fn is resolved on release so a following Shift or Space can choose the mode.
/// While recording, the first Fn press ends the turn; its release cannot start another.
public struct FnShortcut {
    public enum Action: Equatable { case start(VoiceMode), finish, cancel }
    private var held = false
    private var consumed = false
    private var translated = false
    public init() {}

    public mutating func flags(fn: Bool, shift: Bool, recording: Bool) -> Action? {
        if fn && !held {
            held = true; consumed = false; translated = shift
            if recording { consumed = true; return .finish }
        } else if fn && held {
            translated = translated || shift
        } else if !fn && held {
            held = false
            defer { consumed = false; translated = false }
            if !consumed { return .start(translated ? .translate : .dictate) }
        }
        return nil
    }

    public mutating func keyDown(space: Bool, escape: Bool, repeating: Bool, busy: Bool) -> Action? {
        if escape && busy { consumed = true; return .cancel }
        guard held, !consumed else { return nil }
        // Fn + arrows, Delete, or another key belongs to macOS, not dictation.
        guard space else { consumed = true; return nil }
        guard !repeating else { return nil }
        consumed = true
        return .start(.ask)
    }
    public var isFnHeld: Bool { held }
    public mutating func reset() { self = Self() }
}
