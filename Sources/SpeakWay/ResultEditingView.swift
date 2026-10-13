import SwiftUI

struct ResultEditingView: View {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $model.resultDraft)
                .font(.system(size: 15)).scrollContentBackground(.hidden)
                .padding(8).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .focused($focused).accessibilityLabel("Transcription text")
                .accessibilityIdentifier("transcriptionEditor")
            Text("Use Markdown for lists and formatting. Save updates this result and history. Copy your edit to paste it elsewhere.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.editError.isEmpty {
                Text(model.editError).font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                Button("Save changes") { model.saveResultEdit() }
                    .buttonStyle(.borderedProminent).tint(actionBlue)
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityIdentifier("saveTranscriptionEdit")
                Button("Cancel") { model.cancelResultEditing() }
                Spacer()
                Text("⌘S to save").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Let the explicitly activated panel install this editor first.
            await Task.yield()
            focused = true
        }
    }
}
