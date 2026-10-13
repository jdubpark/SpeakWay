import Foundation

/// A deliberate context choice survives setup errors and is consumed only when
/// a context-using recording actually starts listening. Clear is different from
/// never choosing context: it must suppress the automatic external selection.
public struct PendingContext {
    private enum Choice { case automatic, excluded, clipboard(String), transcription(String) }
    private var choice: Choice = .automatic
    public init() {}

    public mutating func useClipboard(_ text: String) { choice = .clipboard(text) }
    public mutating func useTranscription(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeakWayError.message("There is no transcription to continue from.")
        }
        guard text.count <= 24_000 else {
            throw SpeakWayError.message("This transcription is too long to use as context (up to 24,000 characters).")
        }
        choice = .transcription(text)
    }
    public mutating func clear() { choice = .excluded }
    public mutating func recordingBegan() { choice = .automatic }
    public var usesClipboard: Bool { if case .clipboard = choice { return true }; return false }
    public var excludesSelection: Bool { if case .excluded = choice { return true }; return false }
    public var preContext: String { if case .transcription(let text) = choice { return text }; return "" }

    public func resolve(externalSelection: String) -> String {
        switch choice {
        case .automatic: return externalSelection
        case .excluded, .transcription: return ""
        case .clipboard(let text): return text
        }
    }
}
