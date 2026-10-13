import Testing
@testable import SpeakWayCore

@Test func fnChordsChooseOneModeAndNeverRestartAfterSending() {
    var router = FnShortcut()
    #expect(router.flags(fn: true, shift: false, recording: false) == nil)
    #expect(router.flags(fn: false, shift: false, recording: false) == .start(.dictate))
    #expect(router.flags(fn: true, shift: false, recording: true) == .finish)
    #expect(router.flags(fn: false, shift: false, recording: false) == nil)

    #expect(router.flags(fn: true, shift: false, recording: false) == nil)
    #expect(router.flags(fn: true, shift: true, recording: false) == nil)
    #expect(router.flags(fn: false, shift: true, recording: false) == .start(.translate))

    #expect(router.flags(fn: true, shift: false, recording: false) == nil)
    #expect(router.keyDown(space: true, escape: false, repeating: false, busy: false) == .start(.ask))
    #expect(router.keyDown(space: true, escape: false, repeating: true, busy: true) == nil)
    #expect(router.flags(fn: false, shift: false, recording: true) == nil)
    #expect(router.flags(fn: true, shift: true, recording: true) == .finish)
    #expect(router.flags(fn: false, shift: true, recording: false) == nil)
}

@Test func escapeCancelsWithoutLeakingAPendingFnPress() {
    var router = FnShortcut()
    _ = router.flags(fn: true, shift: false, recording: false)
    #expect(router.keyDown(space: false, escape: true, repeating: false, busy: true) == .cancel)
    #expect(router.flags(fn: false, shift: false, recording: false) == nil)
}

@Test func unrelatedFnChordsDoNotStartRecordingOnRelease() {
    var router = FnShortcut()
    _ = router.flags(fn: true, shift: false, recording: false)
    #expect(router.keyDown(space: false, escape: false, repeating: false, busy: false) == nil)
    #expect(router.flags(fn: false, shift: false, recording: false) == nil)
}
