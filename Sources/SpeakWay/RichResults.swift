import SwiftUI
import LinkPresentation
import SpeakWayCore

struct ResultContentView: View {
    let result: TextResult
    let mode: VoiceMode
    private var document: RichTextDocument { RichTextDocument(result.text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FormattedText(document: document)
            if mode == .ask && !result.sources.isEmpty {
                Divider()
                Text("Sources").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(result.sources) { source in
                        SourcePreview(source: source)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in RichTextDocument.isWebURL(url) ? .systemAction : .discarded })
    }
}

struct FormattedText: View {
    let document: RichTextDocument
    private var rows: [[RichTextDocument.Paragraph]] {
        var rows: [[RichTextDocument.Paragraph]] = []
        for paragraph in document.paragraphs {
            if let row = paragraph.tableRow, rows.last?.first?.tableRow == row {
                rows[rows.count - 1].append(paragraph)
            } else { rows.append([paragraph]) }
        }
        return rows
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows, id: \.first!.id) { row in
                if row.first?.tableRow != nil {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row) { cell in
                            Text(cell.text).fontWeight(cell.isTableHeader ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.vertical, 6)
                    Divider()
                } else if let paragraph = row.first {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let marker = paragraph.marker { Text(marker).foregroundStyle(.secondary).frame(minWidth: 16, alignment: .trailing) }
                        Text(paragraph.text)
                            .font(paragraph.isCode ? .system(size: 13, design: .monospaced) : .system(size: paragraph.heading == nil ? 15 : paragraph.heading == 1 ? 21 : 17, weight: paragraph.heading == nil ? .regular : .semibold))
                            .foregroundStyle(paragraph.isQuote ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(max(0, paragraph.listDepth - 1)) * 16)
                    .padding(paragraph.isCode ? 12 : 0)
                    .background(paragraph.isCode ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.font(.system(size: 15)).lineSpacing(4).textSelection(.enabled)
    }
}

/// Native link previews load independently after the answer is visible. A failed
/// fetch leaves a working title/URL card; it never delays or replaces the answer.
private struct SourcePreview: View {
    let source: SourceLink
    @State private var image: NSImage?
    @State private var provider: LPMetadataProvider?

    var body: some View {
        Link(destination: source.url) {
            HStack(spacing: 14) {
                Group {
                    if let image { Image(nsImage: image).resizable().scaledToFill() }
                    else { Image(systemName: "globe").font(.system(size: 26)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.primary.opacity(0.04)) }
                }
                .frame(width: 104, height: 80).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(source.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(3)
                    Text(source.url.host ?? source.url.absoluteString).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(source.url.absoluteString)
        .task(id: source.id) {
            guard RichTextDocument.isWebURL(source.url) else { return }
            let loader = LPMetadataProvider(); loader.timeout = 8; provider = loader
            guard let metadata = try? await loader.startFetchingMetadata(for: source.url), !Task.isCancelled,
                  let imageProvider = metadata.imageProvider ?? metadata.iconProvider,
                  imageProvider.canLoadObject(ofClass: NSImage.self) else { return }
            let loaded: NSImage? = await withCheckedContinuation { continuation in
                imageProvider.loadObject(ofClass: NSImage.self) { object, _ in continuation.resume(returning: object as? NSImage) }
            }
            if !Task.isCancelled { image = loaded }
        }
        .onDisappear { provider?.cancel(); provider = nil }
    }
}
