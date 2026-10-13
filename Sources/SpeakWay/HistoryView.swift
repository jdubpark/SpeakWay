import SwiftUI
import AVFoundation
import SpeakWayCore

struct HistoryView: View {
    let revision: Int
    @State private var entries: [HistoryEntry] = []
    @State private var selection: UUID?
    @State private var loading = true
    @State private var error: String?
    @State private var player: AVAudioPlayer?
    @State private var editingID: UUID?
    @State private var draft = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("History").font(.system(size: 28, weight: .semibold))
                    Text("Corrected text, original speech, and recordings saved on this Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open folder", systemImage: "folder") { openFolder() }
            }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if entries.isEmpty {
                ContentUnavailableView("No saved recordings", systemImage: "clock", description: Text("Completed recordings appear here when local history is enabled in Settings."))
            } else {
                Picker("Recording", selection: $selection) {
                    ForEach(entries) { entry in
                        Text("\(entry.createdAt.formatted(date: .abbreviated, time: .standard)) · \(entry.mode.title)").tag(Optional(entry.id))
                    }
                }.disabled(editingID != nil)
                if let entry = entries.first(where: { $0.id == selection }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let text = entry.displayText {
                                Text(entry.editedText != nil ? "Edited text" : entry.mode == .dictate ? "Corrected text" : entry.mode == .translate ? "Translation" : "Answer")
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                                if editingID == entry.id {
                                    TextEditor(text: $draft).font(.system(size: 15)).frame(minHeight: 180)
                                        .accessibilityLabel("Saved transcription text").disabled(saving)
                                    HStack {
                                        Button(saving ? "Saving…" : "Save changes") { saveEdit(entry) }
                                            .buttonStyle(.borderedProminent).tint(actionBlue).disabled(saving)
                                        Button("Cancel") { editingID = nil; error = nil }.disabled(saving)
                                    }
                                } else {
                                FormattedText(document: RichTextDocument(text))
                                    HStack {
                                        Button("Copy text", systemImage: "doc.on.doc") { TextAccess.copy(RichTextDocument(text)) }
                                        if entry.mode == .dictate {
                                            Button("Edit", systemImage: "pencil") { draft = text; editingID = entry.id; error = nil }
                                        }
                                    }
                                }
                                if entry.editedText != nil, let original = entry.correctedText {
                                    DisclosureGroup("Original correction") { FormattedText(document: RichTextDocument(original)) }
                                        .font(.caption)
                                }
                            }
                            if let processingError = entry.processingError { Text(processingError).font(.callout).foregroundStyle(.secondary) }
                            Divider()
                            Text("Raw transcription").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            Text(entry.rawTranscript.isEmpty ? "No transcript was captured." : entry.rawTranscript)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                Button("Copy raw text") { TextAccess.copy(entry.rawTranscript) }.disabled(entry.rawTranscript.isEmpty)
                                if let audio = entry.audioFilename {
                                    Button("Play audio", systemImage: "play.fill") { play(entry: entry, filename: audio) }
                                    Button("Stop", systemImage: "stop.fill") { player?.stop(); player = nil }.disabled(player == nil)
                                }
                                Spacer()
                                Button("Show files") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: RecordingHistory.folder(for: entry.id).path) }
                            }
                            if let audioError = entry.audioError { Text(audioError).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 8).padding(.trailing, 8)
                    }
                }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
        }
        .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: revision) {
            let result = await Task.detached(priority: .utility) { Result { try RecordingHistory.load() } }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let items):
                entries = items; error = nil
                if !items.contains(where: { $0.id == selection }) { selection = items.first?.id }
            case .failure(let failure): error = failure.localizedDescription
            }
            loading = false
        }
        .onChange(of: selection) { _, _ in player?.stop(); player = nil }
        .onDisappear { player?.stop() }
    }

    private func openFolder() {
        // Opening an empty history uses the parent without creating files on the UI thread.
        let directory = RecordingHistory.directory
        if FileManager.default.fileExists(atPath: directory.path) { NSWorkspace.shared.open(directory) }
        else { error = "The history folder is created after your first saved recording." }
    }
    private func saveEdit(_ entry: HistoryEntry) {
        saving = true
        let text = draft
        Task {
            do {
                let updated = try await RecordingHistory.saveEdit(id: entry.id, text: text)
                if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = updated }
                editingID = nil; error = nil
            } catch { self.error = error.localizedDescription }
            saving = false
        }
    }
    private func play(entry: HistoryEntry, filename: String) {
        do {
            player?.stop()
            // The app writes a single fixed filename; never follow paths from edited metadata.
            guard filename == "audio.wav" else { return }
            player = try AVAudioPlayer(contentsOf: RecordingHistory.folder(for: entry.id).appendingPathComponent(filename))
            player?.play()
        } catch { self.error = "This recording couldn’t be played: \(error.localizedDescription)" }
    }
}
