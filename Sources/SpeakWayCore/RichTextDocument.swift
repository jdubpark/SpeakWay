import Foundation

/// One Markdown interpretation for display, rich paste, and readable plain-text fallbacks.
/// HTML is generated from parsed text and intents; model-supplied HTML is never executed.
public struct RichTextDocument {
    public struct Paragraph: Identifiable {
        public let id: Int
        public var text: AttributedString
        public let intents: [PresentationIntent.IntentType]
        public var heading: Int? {
            for intent in intents { if case .header(let level) = intent.kind { return level } }
            return nil
        }
        public var isCode: Bool { intents.contains { if case .codeBlock = $0.kind { return true }; return false } }
        public var isQuote: Bool { intents.contains { $0.kind == .blockQuote } }
        public var listDepth: Int { intents.filter { $0.kind == .orderedList || $0.kind == .unorderedList }.count }
        public var marker: String? {
            for (index, intent) in intents.enumerated() {
                if case .listItem(let ordinal) = intent.kind {
                    return intents.dropFirst(index + 1).first?.kind == .orderedList ? "\(ordinal)." : "•"
                }
            }
            return nil
        }
        public var tableRow: Int? {
            for intent in intents {
                if case .tableRow = intent.kind { return intent.identity }
                if case .tableHeaderRow = intent.kind { return intent.identity }
            }
            return nil
        }
        public var isTableHeader: Bool { intents.contains { $0.kind == .tableHeaderRow } }
    }

    public let paragraphs: [Paragraph]
    public let plainText: String
    public let html: String
    public let hasFormatting: Bool

    public init(_ markdown: String) {
        var parsed = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        // Only web links are actionable in both the app and exported rich text.
        for run in parsed.runs {
            if let url = run.link, !Self.isWebURL(url) { parsed[run.range].link = nil }
        }
        var paragraphs: [Paragraph] = []
        var body = ""
        var stack: [PresentationIntent.IntentType] = []
        var formatted = false
        for run in parsed.runs {
            let intents = run.presentationIntent?.components ?? []
            let id = intents.first?.identity ?? 0
            let fragment = AttributedString(parsed[run.range])
            if paragraphs.last?.id == id { paragraphs[paragraphs.count - 1].text.append(fragment) }
            else { paragraphs.append(Paragraph(id: id, text: fragment, intents: intents)) }

            let next = Array(intents.reversed())
            let shared = zip(stack, next).prefix { $0.identity == $1.identity }.count
            for intent in stack.dropFirst(shared).reversed() { body += Self.tag(intent.kind, closing: true) }
            for intent in next.dropFirst(shared) { body += Self.tag(intent.kind, closing: false) }
            stack = next
            var text = Self.escape(String(fragment.characters)).replacingOccurrences(of: "\n", with: "<br>")
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.code) { text = "<code>\(text)</code>" }
            if inline.contains(.stronglyEmphasized) { text = "<strong>\(text)</strong>" }
            if inline.contains(.emphasized) { text = "<em>\(text)</em>" }
            if inline.contains(.strikethrough) { text = "<s>\(text)</s>" }
            if let url = run.link { text = "<a href=\"\(Self.escape(url.absoluteString))\">\(text)</a>" }
            body += text
            formatted = formatted || !inline.isEmpty || run.link != nil || intents.contains { $0.kind != .paragraph }
        }
        for intent in stack.reversed() { body += Self.tag(intent.kind, closing: true) }
        self.paragraphs = paragraphs
        var plain = ""
        var previous: Paragraph?
        for paragraph in paragraphs {
            if let previous {
                if let row = paragraph.tableRow, row == previous.tableRow { plain += "\t" }
                else if paragraph.marker != nil || paragraph.tableRow != nil { plain += "\n" }
                else { plain += "\n\n" }
            }
            if let marker = paragraph.marker {
                plain += String(repeating: "  ", count: max(0, paragraph.listDepth - 1)) + marker + " "
            }
            plain += String(paragraph.text.characters)
            previous = paragraph
        }
        plainText = plain
        html = "<!doctype html><html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>"
        hasFormatting = formatted
    }

    public static func isWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty && url.user == nil && url.password == nil
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func tag(_ kind: PresentationIntent.Kind, closing: Bool) -> String {
        let name: String
        switch kind {
        case .paragraph: name = "p"
        case .header(let level): name = "h\(min(6, max(1, level)))"
        case .orderedList: name = "ol"
        case .unorderedList: name = "ul"
        case .listItem(let ordinal): return closing ? "</li>" : "<li value=\"\(ordinal)\">"
        case .codeBlock: name = "pre"
        case .blockQuote: name = "blockquote"
        case .thematicBreak: return closing ? "" : "<hr>"
        case .table: name = "table"
        case .tableHeaderRow, .tableRow: name = "tr"
        case .tableCell: name = "td"
        @unknown default: name = "div"
        }
        return closing ? "</\(name)>" : "<\(name)>"
    }
}
