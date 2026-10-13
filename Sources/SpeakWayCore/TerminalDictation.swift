import Foundation

public enum TerminalDictation {
    /// Terminal insertion can interpret newlines as Return. Deliver one line
    /// and reject control sequences; Copy still offers the full document.
    public static func insertionText(_ text: String) -> String? {
        var result = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) || scalar == "\t" {
                if !result.hasSuffix(" ") { result.append(" ") }
            } else {
                guard !CharacterSet.controlCharacters.contains(scalar) else { return nil }
                result.unicodeScalars.append(scalar)
            }
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
