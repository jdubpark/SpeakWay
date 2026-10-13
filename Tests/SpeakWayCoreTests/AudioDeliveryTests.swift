import Foundation
import Testing
@testable import SpeakWayCore

@Test @MainActor func earlyAudioQueuesWithoutWaitingForConnectionAndFinishingDrainsInOrder() async throws {
    var connected: CheckedContinuation<Void, Never>?
    var sent: [Data] = []
    var finished = false
    let sender = BufferedAudioSender(prepare: {
        await withCheckedContinuation { connected = $0 }
    }, send: { sent.append($0) }, onFailure: { _ in Issue.record("Connection should succeed") })
    sender.append(Data([1, 2])); sender.append(Data([3, 4]))
    try await eventually { connected != nil }
    let finish = Task { try await sender.finish(); finished = true }
    await Task.yield()
    #expect(sent.isEmpty && !finished)
    connected?.resume()
    try await finish.value
    #expect(sent == [Data([1, 2]), Data([3, 4])] && finished)
    sender.append(Data([5, 6]))
    await Task.yield()
    #expect(sent.count == 2)
}

@Test @MainActor func cancellationDropsQueuedAudioEvenIfConnectionCompletesLater() async throws {
    var connected: CheckedContinuation<Void, Never>?
    var sent = 0; var failures = 0
    let sender = BufferedAudioSender(prepare: {
        await withCheckedContinuation { connected = $0 }
    }, send: { _ in sent += 1 }, onFailure: { _ in failures += 1 })
    sender.append(Data([1, 2]))
    try await eventually { connected != nil }
    sender.cancel(); connected?.resume()
    do { try await sender.finish(); Issue.record("Cancelled audio must not be delivered") }
    catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    #expect(sent == 0 && failures == 0)
}

@Test @MainActor func bufferOverflowAndConnectionFailureCannotBecomeSuccessfulRecordings() async throws {
    var connected: CheckedContinuation<Void, Never>?
    var failures = 0
    let sender = BufferedAudioSender(capacity: 1, prepare: {
        await withCheckedContinuation { connected = $0 }
    }, send: { _ in }, onFailure: { _ in failures += 1 })
    sender.append(Data([1])); sender.append(Data([2]))
    try await eventually { connected != nil }; connected?.resume()
    do { try await sender.finish(); Issue.record("Dropped speech must fail") } catch {}
    #expect(failures == 1)

    let disconnected = BufferedAudioSender(prepare: { throw SpeakWayError.message("Offline") },
        send: { _ in Issue.record("Audio must wait for a configured connection") }, onFailure: { _ in failures += 1 })
    disconnected.append(Data([3]))
    do { try await disconnected.finish(); Issue.record("An offline recording must fail") } catch {}
    #expect(failures == 2)
}
