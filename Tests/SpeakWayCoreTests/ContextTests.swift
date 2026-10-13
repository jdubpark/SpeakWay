import Testing
@testable import SpeakWayCore

@Test func clearingContextExcludesTheExternalSelectionUntilRecordingStarts() {
    var context = PendingContext()
    context.clear()
    #expect(context.resolve(externalSelection: "Private selected text") == "")
    // Setup can reject several attempts without beginning a recording.
    #expect(context.resolve(externalSelection: "Private selected text") == "")
    context.recordingBegan()
    #expect(context.resolve(externalSelection: "A newly selected passage") == "A newly selected passage")
}

@Test func clipboardContextSurvivesSetupAndIsConsumedByOneRecording() {
    var context = PendingContext()
    context.useClipboard("Translate this passage")
    #expect(context.resolve(externalSelection: "Unrelated selection") == "Translate this passage")
    #expect(context.resolve(externalSelection: "") == "Translate this passage")
    context.recordingBegan()
    #expect(context.resolve(externalSelection: "") == "")
}

@Test func transcriptionContextIsExplicitSurvivesSetupAndIsConsumedOnce() throws {
    var context = PendingContext()
    try context.useTranscription("Meet Wednesday at two.")
    // Repeated resolution during failed setup must not lose the user's choice
    // or silently include text from another app.
    for _ in 0..<2 {
        #expect(context.preContext == "Meet Wednesday at two.")
        #expect(context.resolve(externalSelection: "Unrelated private text") == "")
    }
    context.recordingBegan()
    #expect(context.preContext.isEmpty)
    #expect(context.resolve(externalSelection: "New selection") == "New selection")

    try context.useTranscription("Another transcription")
    context.clear()
    #expect(context.preContext.isEmpty && context.resolve(externalSelection: "Private selection").isEmpty)
    try context.useTranscription("Another transcription")
    context.useClipboard("Chosen clipboard text")
    #expect(context.preContext.isEmpty)
    #expect(context.resolve(externalSelection: "Private selection") == "Chosen clipboard text")
}

@Test func invalidTranscriptionContextPreservesTheExistingChoice() throws {
    var context = PendingContext()
    try context.useTranscription("Valid context")
    for invalid in [" \n ", String(repeating: "x", count: 24_001)] {
        #expect(throws: (any Error).self) { try context.useTranscription(invalid) }
        #expect(context.preContext == "Valid context")
    }
}
