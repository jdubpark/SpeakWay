import Foundation
import Testing
@testable import SpeakWayCore

@MainActor private final class EditableField: LiveDictationTarget {
    var text: NSMutableString
    var selection: NSRange
    var focused = true
    var writes = 0
    var rejectWrites = false
    let initialSnapshot: TextInputSnapshot?

    init(_ value: String = "Before | after", caret: Int = 7, selectionLength: Int = 0) {
        text = NSMutableString(string: value)
        selection = NSRange(location: caret, length: selectionLength)
        initialSnapshot = TextInputSnapshot(text: value, selection: selection)
    }
    func read() -> TextInputSnapshot? {
        focused ? TextInputSnapshot(text: text as String, selection: selection) : nil
    }
    func replace(_ edit: LiveTextEdit) -> TextInputSnapshot? {
        guard !rejectWrites, read() == edit.before else { return nil }
        writes += 1
        text.replaceCharacters(in: edit.range, with: edit.text)
        selection = NSRange(location: edit.range.location + (edit.text as NSString).length, length: 0)
        return read()
    }
}

@Test @MainActor func liveCorrectionsReplaceOnlyOwnedTextIncludingUnicode() throws {
    let prefix = "Keep 🧑🏽‍💻 cafe\u{301}: "
    let field = EditableField(prefix + " | Keep this suffix 🔒", caret: (prefix as NSString).length)
    let live = try #require(LiveDictationSession(target: field))
    live.update("Tuesday at three")
    #expect(field.text as String == prefix + "Tuesday at three | Keep this suffix 🔒")
    live.update("Wednesday 👋🏽")
    #expect(field.text as String == prefix + "Wednesday 👋🏽 | Keep this suffix 🔒")
    live.finish("Wednesday.")
    #expect(field.text as String == prefix + "Wednesday. | Keep this suffix 🔒")
    #expect(live.status == .finished)
    live.cancel(); live.update("late")
    #expect(field.text as String == prefix + "Wednesday. | Keep this suffix 🔒")
    #expect(field.writes == 3)
}

@Test @MainActor func cancelRemovesOnlyTheUnchangedLiveSpan() throws {
    let field = EditableField()
    let live = try #require(LiveDictationSession(target: field))
    live.update("draft 🫶🏽"); live.update("short")
    live.cancel(); live.update("late speech")
    #expect(field.text as String == "Before | after")
    #expect(field.selection == NSRange(location: 7, length: 0))
    #expect(field.writes == 3)
}

@Test @MainActor func externalChangesPermanentlyStopReplacementAndRollback() throws {
    let changes: [(EditableField) -> Void] = [
        { $0.text.insert("User ", at: 0) },
        { $0.text.replaceCharacters(in: NSRange(location: 7, length: 5), with: "Mine!") },
        { $0.text.append(" User suffix") },
        { $0.selection = NSRange(location: 0, length: 0) },
        { $0.selection = NSRange(location: 0, length: 6) },
        { $0.focused = false }
    ]
    for change in changes {
        let field = EditableField()
        let live = try #require(LiveDictationSession(target: field))
        live.update("draft"); change(field)
        let userText = field.text as String
        live.update("revised")
        #expect(live.status == .paused)
        field.focused = true
        live.finish("final"); live.cancel()
        #expect(field.text as String == userText)
        #expect(field.writes == 1)
    }
}

@Test @MainActor func selectedTextInvalidOffsetsAndUnacknowledgedWritesAreNeverRetried() throws {
    for field in [EditableField(selectionLength: 4), EditableField(caret: 500), EditableField("😀", caret: 1)] {
        #expect(LiveDictationSession(target: field) == nil)
        #expect(field.writes == 0)
    }
    let field = EditableField()
    let live = try #require(LiveDictationSession(target: field))
    live.update("draft"); field.rejectWrites = true
    live.update("correction"); field.rejectWrites = false
    live.finish("final"); live.cancel()
    #expect(live.status == .paused)
    #expect(field.text as String == "Before draft| after" && field.writes == 1)

    let unicode = EditableField("Cafe\u{301} | suffix", caret: 6)
    let unicodeLive = try #require(LiveDictationSession(target: unicode))
    unicode.text.setString("Café | suffix")
    unicodeLive.update("words")
    #expect(unicode.writes == 0 && unicodeLive.status == .paused)
}

@Test @MainActor func liveStreamingFinalCorrectionAndCancelDoNotDuplicateOrDeleteOtherText() async throws {
    var settings = Settings(); settings.liveDictation = true
    let field = EditableField(); let speech = ControlledSpeech(); speech.text = "Tuesday"
    let voice = VoiceController()
    voice.didFinish = { _, _ in voice.completeLiveDictation() }
    voice.start(mode: .dictate, selection: "", settings: settings, session: speech, liveTarget: field) { _ in
        TextResult(text: "**Wednesday**\n\n- Bring notes\n- Book room")
    }
    try await eventually { field.text as String == "Before Tuesday| after" }
    speech.onText?("Tuesday, no Wednesday")
    speech.text = "Tuesday, no Wednesday"
    try await eventually { field.text as String == "Before Tuesday, no Wednesday| after" }
    voice.finish()
    try await eventually { voice.liveDictationStatus == .finished }
    #expect(field.text as String == "Before Wednesday\n• Bring notes\n• Book room| after")
    voice.completeLiveDictation(); voice.cancel(); speech.onText?("late")
    #expect(field.text as String == "Before Wednesday\n• Bring notes\n• Book room| after")

    let nextField = EditableField(); let nextSpeech = ControlledSpeech()
    voice.start(mode: .dictate, selection: "", settings: settings, session: nextSpeech, liveTarget: nextField) { _ in TextResult(text: "Unused") }
    try await eventually { nextField.writes > 0 }
    nextSpeech.onText?("queued"); voice.cancel(); nextSpeech.onText?("late")
    try await Task.sleep(for: .milliseconds(180))
    #expect(nextField.text as String == "Before | after")
    #expect(voice.phase == .idle)
}

@Test @MainActor func onlyOptedInDictationCanWriteLive() async throws {
    for (mode, enabled, autoInsert) in [(VoiceMode.ask, true, true), (.translate, true, true), (.dictate, false, true), (.dictate, true, false)] {
        var settings = Settings(); settings.liveDictation = enabled; settings.autoInsert = autoInsert
        let field = EditableField(); let speech = ControlledSpeech(); let voice = VoiceController()
        voice.didFinish = { _, _ in voice.completeLiveDictation() }
        voice.start(mode: mode, selection: "Reference", settings: settings, session: speech, liveTarget: field) { _ in TextResult(text: "Output") }
        try await eventually { voice.phase == .listening }
        voice.finish(); try await eventually { voice.phase == .ready }
        #expect(voice.liveDictationStatus == .off && field.writes == 0)
        voice.cancel()
    }
    var settings = Settings(); settings.liveDictation = true
    let field = EditableField(selectionLength: 6); let voice = VoiceController(); let speech = ControlledSpeech()
    voice.start(mode: .dictate, selection: "", settings: settings, session: speech, liveTarget: field) { _ in TextResult(text: "Final") }
    try await eventually { voice.phase == .listening }
    voice.finish(); try await eventually { voice.phase == .ready }; voice.completeLiveDictation()
    #expect(voice.liveDictationStatus == .unavailable && field.writes == 0)
    #expect(field.text as String == "Before | after")
}

@Test func liveTypingIsOptInAndItsSettingSurvivesRestart() throws {
    #expect(try !JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).liveDictation)
    var settings = Settings(); settings.liveDictation = true
    let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    #expect(restored.liveDictation)
}

@Test func terminalDictationCannotSubmitCommandsOrInjectControlKeys() {
    #expect(TerminalDictation.insertionText("Wednesday at two.\n\n• Bring notes\n1. Book room\r\n") == "Wednesday at two. • Bring notes 1. Book room")
    #expect(TerminalDictation.insertionText("keep\tthese\u{2028}words 👋🏽") == "keep these words 👋🏽")
    for unsafe in ["text\u{1b}[2K", "text\u{8}", "text\u{7f}", "text\u{85}more\u{3}"] {
        #expect(TerminalDictation.insertionText(unsafe) == nil)
    }
    #expect(TerminalDictation.insertionText("\r\n\t ") == nil)
}
