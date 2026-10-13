import Foundation
import Testing
@testable import SpeakWayCore

@MainActor final class ControlledSpeech: SpeechSession {
    var starts = 0
    var finishes = 0
    var cancellations = 0
    var text = "Um, Tuesday, actually Wednesday."
    var onText: ((String) -> Void)?
    var startGate: CheckedContinuation<Void, Never>?
    var delayStart = false
    func start(onText: @escaping (String) -> Void, onLevel: @escaping (Float) -> Void, onFailure: @escaping (Error) -> Void) async throws {
        starts += 1; self.onText = onText
        if delayStart { await withCheckedContinuation { startGate = $0 } }
        onText(text)
    }
    func finish() async throws -> String { finishes += 1; return text }
    func cancel() { cancellations += 1 }
}

@MainActor func eventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
    #expect(condition())
}

@Test @MainActor func oneCaptureProducesOneRequestAndOneDelivery() async throws {
    let controller = VoiceController(); let speech = ControlledSpeech()
    var requests: [TextRequest] = []; var deliveries = 0
    controller.didFinish = { _, _ in deliveries += 1 }
    controller.start(mode: .dictate, selection: "do not send this", settings: Settings(), session: speech) { request in
        requests.append(request); return TextResult(text: "Wednesday.")
    }
    controller.start(mode: .ask, selection: "", settings: Settings(), session: speech) { _ in TextResult(text: "Incorrect") }
    try await eventually { controller.phase == .listening }
    controller.finish(); controller.finish()
    try await eventually { controller.phase == .ready }
    #expect(speech.starts == 1 && speech.finishes == 1)
    #expect(requests.count == 1 && requests[0].selection.isEmpty)
    #expect(controller.result?.text == "Wednesday.")
    #expect(deliveries == 1)
}

@Test @MainActor func cancellationRejectsAnOldModelResponseAndLateSpeechEvents() async throws {
    let controller = VoiceController(); let oldSpeech = ControlledSpeech()
    var response: CheckedContinuation<TextResult, Never>?
    var deliveries = 0
    controller.didFinish = { _, _ in deliveries += 1 }
    controller.start(mode: .ask, selection: "", preContext: "Old transcription", settings: Settings(), session: oldSpeech) { _ in
        await withCheckedContinuation { response = $0 }
    }
    try await eventually { controller.phase == .listening }
    controller.finish(); try await eventually { response != nil }
    controller.cancel()
    let newSpeech = ControlledSpeech(); newSpeech.text = "New session"
    controller.start(mode: .dictate, selection: "", settings: Settings(), session: newSpeech) { request in
        #expect(request.preContext.isEmpty)
        return TextResult(text: "New answer")
    }
    try await eventually { controller.phase == .listening }
    oldSpeech.onText?("Stale words")
    response?.resume(returning: TextResult(text: "Stale answer"))
    await Task.yield()
    #expect(controller.transcript == "New session")
    #expect(controller.result == nil && deliveries == 0)
    controller.finish(); try await eventually { controller.phase == .ready }
    #expect(controller.result?.text == "New answer" && deliveries == 1)
}

@Test @MainActor func cancellingPreparationCannotLaterTurnTheMicrophoneOn() async throws {
    let controller = VoiceController(); let speech = ControlledSpeech(); speech.delayStart = true
    controller.start(mode: .dictate, selection: "", settings: Settings(), session: speech) { _ in TextResult(text: "Unused") }
    try await eventually { speech.startGate != nil }
    controller.cancel(); speech.startGate?.resume()
    try await eventually { speech.cancellations >= 2 }
    #expect(controller.phase == .idle && controller.transcript.isEmpty)
}

@Test @MainActor func emptySpeechAndMissingSelectionNeverCallTheModel() async throws {
    let controller = VoiceController(); let speech = ControlledSpeech(); speech.text = " \n "
    var requests = 0
    controller.start(mode: .translate, selection: "", settings: Settings(), session: speech) { _ in requests += 1; return TextResult(text: "Unused") }
    #expect(controller.phase == .failed && speech.starts == 0)
    controller.start(mode: .ask, selection: "", preContext: String(repeating: "x", count: 24_001), settings: Settings(), session: speech) { _ in requests += 1; return TextResult(text: "Unused") }
    #expect(controller.phase == .failed && speech.starts == 0)
    controller.start(mode: .dictate, selection: "", settings: Settings(), session: speech) { _ in requests += 1; return TextResult(text: "Unused") }
    try await eventually { controller.phase == .listening }
    controller.finish(); try await eventually { controller.phase == .failed }
    #expect(requests == 0 && controller.result == nil)
}

@Test @MainActor func editingCompletedDictationPreservesRawSpeechAndNeverRedelivers() async throws {
    let controller = VoiceController(); let speech = ControlledSpeech()
    var deliveries = 0
    controller.didFinish = { _, _ in deliveries += 1 }
    #expect(!controller.editResult("No result yet"))
    controller.start(mode: .dictate, selection: "", settings: Settings(), session: speech) { _ in TextResult(text: "Wednesday.") }
    try await eventually { controller.phase == .listening }
    #expect(!controller.editResult("Still recording"))
    controller.finish(); try await eventually { controller.phase == .ready }
    #expect(!controller.editResult("  \n") && !controller.editResult(String(repeating: "x", count: 24_001)))
    #expect(controller.editResult("Thursday.\n\n1. Bring notes"))
    #expect(controller.result?.text == "Thursday.\n\n1. Bring notes")
    #expect(controller.transcript == speech.text && controller.resultWasEdited && deliveries == 1)
    controller.start(mode: .ask, selection: "", settings: Settings(), session: ControlledSpeech()) { _ in TextResult(text: "Answer") }
    try await eventually { controller.phase == .listening }
    #expect(!controller.resultWasEdited)
    controller.finish(); try await eventually { controller.phase == .ready }
    #expect(!controller.editResult("Cannot edit answer as dictation"))
}

@Test @MainActor func completedTranscriptionCanProvideContextToOneFollowUpInEveryMode() async throws {
    for mode in VoiceMode.allCases {
        let controller = VoiceController()
        controller.start(mode: .dictate, selection: "", settings: Settings(), session: ControlledSpeech()) { _ in
            TextResult(text: "Meet Wednesday at two.")
        }
        try await eventually { controller.phase == .listening }
        controller.finish(); try await eventually { controller.phase == .ready }
        let previous = try #require(controller.result?.text)
        let followUp = ControlledSpeech(); followUp.text = "Bring notes."
        var requests: [TextRequest] = []
        controller.start(mode: mode, selection: "", preContext: previous, settings: Settings(), session: followUp) { request in
            requests.append(request); return TextResult(text: "Follow-up result")
        }
        try await eventually { controller.phase == .listening }
        controller.finish(); try await eventually { controller.phase == .ready }
        let request = try #require(requests.first)
        #expect(request.mode == mode && request.preContext == "Meet Wednesday at two.")
        #expect(request.transcript == "Bring notes." && request.selection.isEmpty)
        #expect(requests.count == 1)

        controller.start(mode: .ask, selection: "", settings: Settings(), session: ControlledSpeech()) { request in
            #expect(request.preContext.isEmpty)
            return TextResult(text: "Independent result")
        }
        try await eventually { controller.phase == .listening }
        controller.finish(); try await eventually { controller.phase == .ready }
        controller.cancel()
        #expect(controller.preContext.isEmpty)
    }
}
