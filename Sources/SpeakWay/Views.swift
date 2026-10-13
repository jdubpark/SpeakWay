import SwiftUI
import SpeakWayCore

let speakBlue = Color(nsColor: NSColor(name: "SpeakWayAccent") { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.51, green: 0.66, blue: 1, alpha: 1)
        : NSColor(red: 0.19, green: 0.33, blue: 0.80, alpha: 1)
})
// A pale foreground accent is legible on dark surfaces, but not behind white labels.
let actionBlue = Color(red: 0.19, green: 0.33, blue: 0.80)

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var voice: VoiceController
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            if model.showingHistory { HistoryView(revision: model.historyRevision) }
            else if model.showingSettings { SettingsView(model: model, voice: voice) }
            else { workspace }
        }
        .frame(minWidth: 820, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(speakBlue)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.title2.weight(.semibold)).foregroundStyle(speakBlue)
                Text("SpeakWay").font(.system(size: 21, weight: .semibold))
            }.padding(.top, 14)
            VStack(spacing: 6) {
                ForEach(VoiceMode.allCases) { mode in
                    Button {
                        model.mode = mode; model.showingSettings = false; model.showingHistory = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.symbol).frame(width: 21)
                            Text(mode.title).fontWeight(.medium)
                            Spacer()
                        }.padding(.horizontal, 12).padding(.vertical, 11)
                            .background(!model.showingSettings && !model.showingHistory && model.mode == mode ? speakBlue.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(!model.showingSettings && !model.showingHistory && model.mode == mode ? speakBlue : .primary)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(voice.busy)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                ForEach(VoiceMode.allCases) { mode in
                    HStack { Text(mode.title); Spacer(); Text(mode.shortcut).font(.system(size: 11, weight: .medium, design: .monospaced)) }
                }
                Text("Press fn again to send").font(.caption).padding(.top, 3)
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 5)
            Divider()
            Button { model.openHistory() } label: {
                Label("History", systemImage: "clock").frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(model.showingHistory ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(voice.busy)
            Button { model.openSettings() } label: {
                Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(model.showingSettings ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(voice.busy)
        }.padding(20).frame(width: 184).background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.mode.title).font(.system(size: 28, weight: .semibold))
                    Text(model.mode.explanation).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.mode.shortcut).font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 6).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            if !model.pendingContext.preContext.isEmpty && !voice.busy {
                TranscriptionContextView(text: model.pendingContext.preContext, clear: model.clearContext)
            } else if voice.busy && !voice.preContext.isEmpty {
                TranscriptionContextView(text: voice.preContext)
            } else if model.mode != .dictate { context }
            if voice.mode == model.mode, let result = voice.result, !model.choosingContinuation {
                resultView(result)
            } else {
                captureView
            }
            if let error = voice.error {
                Label(error, systemImage: "exclamationmark.circle").font(.callout)
                    .foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if !voice.transcript.isEmpty {
                    Button("Copy captured transcript") { TextAccess.copy(voice.transcript); model.delivery = "Transcript copied" }
                }
            }
            if !model.delivery.isEmpty { Text(model.delivery).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            if !model.shortcutReady {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard").font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Enable your Fn shortcuts").fontWeight(.medium)
                        Text("Allow Accessibility and Input Monitoring.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Set up") { model.requestPermissions() }
                }.padding(14).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 8) {
                Image(systemName: model.settings.speechProvider == .local ? "laptopcomputer" : "network")
                Text(model.settings.privacySummary).font(.caption)
            }.foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.selectedText.isEmpty ? "Selected text" : "From \(model.selectionApp)", systemImage: "text.cursor")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if !model.selectedText.isEmpty {
                    Button("Clear") { model.clearContext() }.disabled(voice.busy)
                }
                if model.contextExcluded {
                    Button("Use selection") { model.useSelection() }.disabled(voice.busy)
                }
                Button("Use clipboard") { model.useClipboard() }.disabled(voice.busy)
            }
            Text(model.contextExcluded ? "Selection cleared. Use selection or clipboard to add text again." : model.selectedText.isEmpty ? "Select text in another app, then use \(model.mode.shortcut)." : model.selectedText)
                .font(.callout).foregroundStyle(model.selectedText.isEmpty ? .secondary : .primary)
                .lineLimit(3).textSelection(.enabled)
        }.padding(14).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var captureView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)
            Image(systemName: voice.phase == .listening ? "waveform" : model.mode.symbol)
                .font(.system(size: 33, weight: .light)).foregroundStyle(speakBlue)
                .frame(width: 80, height: 80).background(speakBlue.opacity(0.09), in: Circle())
                .accessibilityHidden(true)
            Text(statusTitle).font(.system(size: 21, weight: .medium))
            if voice.phase == .listening {
                LevelMeter(level: voice.level).frame(height: 22)
                Text(voice.transcript.isEmpty ? "Speak naturally. Press fn when you’re done." : voice.transcript)
                    .foregroundStyle(.secondary).lineLimit(4).frame(maxWidth: 420)
            } else if voice.phase == .preparing || voice.phase == .processing {
                ProgressView().controlSize(.small)
                Text(voice.phase == .preparing ? "Starting your microphone. The connection opens in parallel." : "Finishing your transcript and processing your words.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Text(example).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            }
            HStack(spacing: 12) {
                Button(voice.phase == .listening ? "Send" : "Start \(model.mode == .dictate ? "dictating" : "speaking")", systemImage: voice.phase == .listening ? "arrow.up" : "mic.fill") { model.toggle() }
                    .buttonStyle(.borderedProminent).tint(actionBlue).controlSize(.large)
                    .disabled(voice.phase == .preparing || voice.phase == .processing)
                    .accessibilityIdentifier("recordButton")
                if voice.busy { Button("Cancel") { model.cancel() }.keyboardShortcut(.escape, modifiers: []) }
            }
            Spacer(minLength: 10)
        }.frame(maxWidth: .infinity, minHeight: model.mode == .dictate ? 320 : 260)
    }

    private func resultView(_ result: TextResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("\(voice.mode == .ask ? "Answer" : voice.mode == .translate ? "Translation" : "Ready to use")", systemImage: "checkmark.circle")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(speakBlue)
                Spacer()
                if voice.mode == .dictate { Button("Edit", systemImage: "pencil") { model.beginResultEditing() } }
                Button("Copy", systemImage: "doc.on.doc") { model.copyResult() }
            }
            if model.editingResult { ResultEditingView(model: model).frame(minHeight: 220) }
            else { ScrollView {
                ResultContentView(result: result, mode: voice.mode)
            }.frame(minHeight: 160, maxHeight: 260) }
            DisclosureGroup("Original speech") { Text(voice.transcript).textSelection(.enabled).font(.callout).foregroundStyle(.secondary).padding(.top, 6) }
            HStack {
                Button("Speak again", systemImage: "mic.fill") { model.toggle() }.buttonStyle(.borderedProminent).tint(actionBlue)
                if voice.mode == .dictate {
                    Button("Continue", systemImage: "arrow.turn.down.right") { model.continueFromTranscription() }
                        .help("Use the corrected transcription as context for your next recording")
                }
                Button("Clear") { model.cancel() }
            }
        }.padding(20).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusTitle: String {
        switch voice.phase {
        case .preparing: return "Getting ready…"
        case .listening: return "Listening"
        case .processing: return "Working on it…"
        default: return model.mode == .dictate ? "Ready when you are." : model.mode == .ask ? "What’s on your mind?" : "Choose your words. Change the language."
        }
    }
    private var example: String {
        switch model.mode {
        case .dictate: return "“Let’s meet on Tuesday… actually, Wednesday at two.”\nKeep the final thought. Leave the fillers behind."
        case .ask: return "“Explain this in plain English.”\nAsk about selected text, or ask a question on its own."
        case .translate: return "“Translate this into Korean, with a friendly tone.”"
        }
    }
}

struct LevelMeter: View {
    let level: Float
    var barCount = 15
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule().fill(speakBlue.opacity(level > 0.01 ? 1 : 0.25))
                    .frame(width: 3, height: 4 + CGFloat(level) * CGFloat(12 + (index * 7 % 17)))
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: level)
            .accessibilityLabel("Microphone level").accessibilityValue(level > 0.03 ? "Sound detected" : "Quiet")
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var voice: VoiceController
    @State private var newKey = ""
    @State private var keyStatus = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.system(size: 28, weight: .semibold)).padding(.horizontal, 30).padding(.top, 30)
            Form {
                Section("Speech recognition") {
                    LabeledContent("Provider", value: "OpenAI")
                    Picker("Spoken language", selection: $model.settings.locale) {
                        Text("English (US)").tag("en-US"); Text("Korean").tag("ko-KR"); Text("Spanish").tag("es-ES")
                        Text("Japanese").tag("ja-JP"); Text("French").tag("fr-FR"); Text("German").tag("de-DE"); Text("Chinese (Mandarin)").tag("zh-CN")
                        Text("Portuguese (Brazil)").tag("pt-BR")
                    }
                    TextField("Speech model", text: $model.settings.transcriptionModel)
                    Text("Audio streams to OpenAI while you speak. Fn finalizes your transcript.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Cleanup, answers & translation") {
                    LabeledContent("Provider", value: "OpenAI")
                    TextField("Text model", text: $model.settings.openAIModel)
                    Toggle("Allow web search when Ask needs it", isOn: $model.settings.webSearch)
                    Text("Ask searches only when the question needs current or external information. Dictation and translation never search.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Your transcript and selected text are processed after you press Fn again. API usage is billed by OpenAI.").font(.caption).foregroundStyle(.secondary)
                    TextField("Default translation language", text: $model.settings.targetLanguage)
                    Toggle("Insert dictation into the original text field", isOn: $model.settings.autoInsert)
                    Text("Only inserts if focus and text are unchanged. All results appear in the popover. Answers and translations are never inserted.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Type dictation as I speak", isOn: $model.settings.liveDictation)
                        .disabled(!model.settings.autoInsert)
                    Text("Dictate only. Updates its own text, then applies the final correction. Start with an empty cursor in a supported text field. Live typing stops if the field, text, or selection no longer matches.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Live typing uses plain text; Copy keeps rich formatting. Cancel removes the draft only while its text and cursor remain unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("cmux receives the final corrected text when you finish, as one line to avoid submitting a command. Edit the result afterward, or Copy to keep line breaks.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("OpenAI API key") {
                    // Grouped forms render the title as a row label, so the hint must be the prompt or the empty field is invisible.
                    SecureField("API key", text: $newKey, prompt: Text(model.savedKeys.contains(.openAI) ? "Replace saved key" : "Paste your OpenAI API key"))
                        .textContentType(.password)
                    HStack {
                        Button("Save to Keychain") { saveKey(newKey) }.disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if model.savedKeys.contains(.openAI) { Button("Remove key", role: .destructive) { saveKey("") } }
                        Spacer()
                        Text(model.savedKeys.contains(.openAI) ? "Key saved" : "No key saved").font(.caption).foregroundStyle(.secondary)
                    }
                    if !keyStatus.isEmpty { Text(keyStatus).font(.caption) }
                    Link("Get an OpenAI API key", destination: CredentialProvider.openAI.keyURL)
                }
                Section("Mac permissions & shortcuts") {
                    LabeledContent("Accessibility", value: model.accessibilityReady ? "Allowed" : "Required for selected text and insertion")
                    LabeledContent("Fn shortcuts", value: model.shortcutReady ? "Connected" : "Permission required")
                    HStack {
                        Button("Enable permissions") { model.requestPermissions() }
                        Button("Keyboard settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
                    }
                    Text("Set ‘Press Globe key to’ to ‘Do Nothing’ if macOS also opens emoji or dictation. Fn starts Dictate, Fn + Shift starts Translate, Fn + Space starts Ask. Fn again sends. Escape cancels.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Local history") {
                    Toggle("Save recordings and transcripts on this Mac", isOn: $model.settings.saveHistory)
                    Text("Corrected text, raw transcription, and audio save in the background after a turn. Cancelled recordings are discarded. Files stay until you remove them from the history folder; turning this off affects future recordings.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("View history", systemImage: "clock") { model.openHistory() }
                    Text("OpenAI applies its own retention policies; store:false is requested for text responses. Source previews contact the cited websites after an Ask result appears.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).disabled(voice.busy)
        }.frame(maxWidth: .infinity).onChange(of: model.settings) { _, _ in model.saveSettings() }
    }
    private func saveKey(_ value: String) {
        do { try model.saveKey(value, for: .openAI); newKey = ""; keyStatus = value.isEmpty ? "Key removed." : "Saved securely in Keychain." }
        catch { keyStatus = error.localizedDescription }
    }
}

