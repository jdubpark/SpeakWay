import Foundation

/// Capture can begin while the connection opens. A single consumer sends the
/// bounded backlog in order, and finishing waits for that backlog to drain.
@MainActor public final class BufferedAudioSender {
    private nonisolated let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let work: Task<Void, Error>

    public init(capacity: Int = 150,
                prepare: @escaping @MainActor () async throws -> Void,
                send: @escaping @MainActor (Data) async throws -> Void,
                onFailure: @escaping @MainActor (Error) -> Void) {
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(capacity))
        self.continuation = continuation
        work = Task {
            do {
                try await prepare()
                try Task.checkCancellation()
                for try await data in stream {
                    try Task.checkCancellation()
                    try await send(data)
                }
            } catch {
                continuation.finish()
                if !Task.isCancelled { onFailure(error) }
                throw error
            }
        }
    }

    public nonisolated func append(_ data: Data) {
        if case .dropped = continuation.yield(data) {
            continuation.finish(throwing: SpeakWayError.message("The connection cannot keep up with the microphone. Try again with a better connection."))
        }
    }

    public func finish() async throws {
        continuation.finish()
        try await work.value
    }

    public func cancel() { continuation.finish(); work.cancel() }
}
