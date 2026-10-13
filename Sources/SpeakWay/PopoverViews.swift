import SwiftUI
import SpeakWayCore

struct OverlayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var voice: VoiceController

    var body: some View {
        Group {
            if voice.busy { captureBar }
            else if model.choosingContinuation { ScrollView { launcher } }
            else if let result = voice.result { resultPanel(result) }
            else if let error = voice.error { errorPanel(error) }
            else { launcher }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: voice.busy ? 22 : 16))
        .tint(speakBlue)
        .onExitCommand { model.dismissPopover() }
    }

    private var captureBar: some View {
        HStack(spacing: 12) {
            if voice.phase == .listening {
                Image(systemName: "mic.fill").font(.system(size: 17)).foregroundStyle(speakBlue)
                    .accessibilityHidden(true)
            } else { ProgressView().controlSize(.small).frame(width: 20) }
            VStack(alignment: .leading, spacing: 4) {
                Text(captureTitle).font(.system(size: 13, weight: .semibold))
                Text(captureDetail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if voice.phase == .listening {
                LevelMeter(level: voice.level, barCount: 9).frame(width: 59, height: 28)
                Button { voice.finish() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 30, height: 30)
                        .background(actionBlue, in: Circle())
                }
                .buttonStyle(.plain).help("Finish recording (fn)")
                .accessibilityLabel("Finish recording").accessibilityIdentifier("finishRecording")
            }
            dismissButton
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(voice.mode.title): \(captureTitle)")
        .help(voice.phase == .listening ? "Audio streams to OpenAI. Press fn to finish or Escape to cancel." : captureDetail)
    }

    private var captureTitle: String {
        switch voice.phase {
        case .preparing: return "Getting ready…"
        case .listening: return "Listening"
        default: return voice.mode == .translate ? "Translating…" : voice.mode == .ask ? "Finding an answer…" : "Polishing your words…"
        }
    }

    private var captureDetail: String {
        switch voice.phase {
        case .preparing: return "Starting microphone"
        case .listening:
            if model.terminalDeliveryPending { return "cmux · final text" }
            switch voice.liveDictationStatus {
            case .typing: return voice.preContext.isEmpty ? "Live typing · fn to finish" : "Live typing · with context"
            case .paused: return "Typing stopped"
            case .unavailable: return "Copy after recording"
            default: return voice.preContext.isEmpty ? "\(voice.mode.title) · fn to finish" : "With context · fn to finish"
            }
        default: return "Microphone off · esc to cancel"
        }
    }

    private var launcher: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(speakBlue)
                Text(model.choosingContinuation ? "Continue with context" : "SpeakWay").font(.system(size: 17, weight: .semibold))
                Spacer()
                historyButton
                settingsButton
                dismissButton
            }
            if model.choosingContinuation {
                TranscriptionContextView(text: model.pendingContext.preContext, clear: model.clearContext)
            }
            VStack(spacing: 4) {
                ForEach(VoiceMode.allCases) { mode in
                    Button {
                        model.mode = mode; model.start()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.symbol).foregroundStyle(speakBlue).frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title).font(.system(size: 13, weight: .medium))
                                Text(modeDetail(mode))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(mode.shortcut).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 9).padding(.horizontal, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(PopoverRowStyle())
                    .accessibilityLabel("Start \(mode.title)")
                    .accessibilityIdentifier("start\(mode.title)")
                }
            }
            Divider()
            if !model.savedKeys.contains(.openAI) {
                HStack {
                    Text("Add an OpenAI key to begin.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Set up") { model.openSettings() }.buttonStyle(.borderedProminent).tint(actionBlue)
                }
            } else {
                HStack {
                    Text(model.shortcutReady ? "Press a shortcut from any app." : "Enable Fn shortcuts in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }.padding(20)
    }

    private func modeDetail(_ mode: VoiceMode) -> String {
        if model.choosingContinuation {
            switch mode {
            case .dictate: return "New words with this background"
            case .ask: return "Ask about this transcription"
            case .translate: return "Translate this transcription"
            }
        }
        return mode == .dictate ? "Write into your current app" : mode == .ask ? "Answers and web results" : "Translate selected text"
    }

    private func resultPanel(_ result: TextResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: voice.mode.symbol).foregroundStyle(speakBlue)
                Text(model.editingResult ? "Edit transcription" : voice.mode == .dictate ? (voice.resultWasEdited ? "Edited text" : "Corrected text") : voice.mode == .translate ? "Translation" : result.sources.isEmpty ? "Answer" : "Search results")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if voice.mode == .dictate && !model.editingResult {
                    Button("Edit", systemImage: "pencil") { model.beginResultEditing() }
                        .accessibilityIdentifier("editTranscription")
                }
                settingsButton.disabled(model.editingResult)
                dismissButton
            }.padding(20)
            Divider()
            if model.editingResult {
                ResultEditingView(model: model)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ResultContentView(result: result, mode: voice.mode)
                    if !voice.transcript.isEmpty {
                        DisclosureGroup("Raw transcription") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(voice.transcript).font(.callout).foregroundStyle(.secondary)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                Button("Copy raw text") { TextAccess.copy(voice.transcript) }
                                if voice.mode == .dictate {
                                    Button("Use raw as context") { model.continueFromTranscription(useRaw: true) }
                                }
                            }.padding(.top, 8)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(result.text)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Label(model.delivery.isEmpty ? "Ready to copy" : model.delivery,
                      systemImage: model.delivery.hasPrefix("Inserted") || model.delivery == "Copied" ? "checkmark.circle" : "text.bubble")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(model.delivery == "Copied" ? "Copied" : "Copy", systemImage: model.delivery == "Copied" ? "checkmark" : "doc.on.doc") { model.copyResult() }
                        .buttonStyle(.borderedProminent).tint(actionBlue)
                        .accessibilityIdentifier("copyResult")
                    Button("Speak again", systemImage: "mic") { model.mode = voice.mode; model.start() }
                    if voice.mode == .dictate {
                        Button("Continue", systemImage: "arrow.turn.down.right") { model.continueFromTranscription() }
                            .help("Use the corrected transcription as context for your next recording")
                            .accessibilityIdentifier("continueFromTranscription")
                    }
                    Spacer()
                    historyButton
                }
                if !model.historyStatus.isEmpty {
                    Text(model.historyStatus).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(20)
            }
        }
    }

    private func errorPanel(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("\(model.mode.title) couldn’t finish", systemImage: "exclamationmark.circle")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                dismissButton
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).font(.callout).textSelection(.enabled)
                    if !voice.transcript.isEmpty {
                        Text("Captured speech").font(.caption).foregroundStyle(.secondary)
                        Text(voice.transcript).font(.callout).textSelection(.enabled)
                    }
                    if !model.pendingContext.preContext.isEmpty {
                        TranscriptionContextView(text: model.pendingContext.preContext, clear: model.clearContext)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if !model.savedKeys.contains(.openAI) {
                    Button("Open Settings") { model.openSettings() }.buttonStyle(.borderedProminent).tint(actionBlue)
                } else {
                    Button("Try again") { model.start() }.buttonStyle(.borderedProminent).tint(actionBlue)
                    if model.mode != .dictate {
                        Button("Use clipboard") { model.useClipboard() }
                    }
                    settingsButton
                }
                if !voice.transcript.isEmpty {
                    Button("Copy speech") { TextAccess.copy(voice.transcript); model.delivery = "Transcript copied" }
                }
            }
            if !model.delivery.isEmpty { Text(model.delivery).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }.padding(20)
    }

    private var dismissButton: some View {
        Button { model.dismissPopover() } label: {
            Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 24, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(voice.busy ? "Cancel (esc)" : "Dismiss (esc)")
        .accessibilityLabel(voice.busy ? "Cancel recording" : "Dismiss popover")
        .accessibilityIdentifier("dismissPopover")
    }

    private var settingsButton: some View {
        Button { model.openSettings() } label: {
            Image(systemName: "gearshape").font(.system(size: 13))
                .foregroundStyle(.secondary).frame(width: 24, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
    }

    private var historyButton: some View {
        Button { model.openHistory() } label: {
            Image(systemName: "clock").font(.system(size: 13))
                .foregroundStyle(.secondary).frame(width: 24, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).help("History").accessibilityLabel("History")
    }
}

struct TranscriptionContextView: View {
    let text: String
    var clear: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Transcription context", systemImage: "text.bubble")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if let clear {
                    Button("Clear", action: clear).accessibilityIdentifier("clearTranscriptionContext")
                }
            }
            Text(RichTextDocument(text).plainText).font(.callout).lineLimit(3).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(clear == nil ? "Included in this recording." : "Included in your next recording only.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PopoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }
    private struct Row: View {
        let configuration: Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }
        }
    }
}
