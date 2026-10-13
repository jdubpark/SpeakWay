import Foundation

public struct HistoryEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let mode: VoiceMode
    public let rawTranscript: String
    public let correctedText: String?
    public let audioFilename: String?
    public let audioError: String?
    public let processingError: String?
    public let sources: [SourceLink]
    public var editedText: String?
    public var editedAt: Date?
    public var displayText: String? { editedText ?? correctedText }
}

public enum RecordingHistory {
    // An immediate edit follows its still-pending initial save on this queue.
    static let queue = DispatchQueue(label: "com.speakway.recording-history", qos: .utility)
    static let pendingSaves = DispatchGroup()
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakWay/History", isDirectory: true)
    }

    public static func load(from directory: URL = directory) throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("transcript.json")) else { return nil }
            return try? JSONDecoder().decode(HistoryEntry.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public static func folder(for id: UUID, in directory: URL = directory) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public static func saveEdit(id: UUID, text: String, in directory: URL = directory) async throws -> HistoryEntry {
        pendingSaves.enter()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                defer { pendingSaves.leave() }
                do {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 24_000 else {
                        throw SpeakWayError.message("Enter between 1 and 24,000 characters.")
                    }
                    let url = folder(for: id, in: directory).appendingPathComponent("transcript.json")
                    var entry = try JSONDecoder().decode(HistoryEntry.self, from: Data(contentsOf: url))
                    entry.editedText = text; entry.editedAt = Date()
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(entry).write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    continuation.resume(returning: entry)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// Buffers the already-created PCM chunks without waiting for disk. Final WAV
/// assembly and atomic transcript writes run on a utility queue after delivery.
public final class RecordingArchive: @unchecked Sendable {
    public let id = UUID()
    private let createdAt = Date()
    private let directory: URL
    private let queue = RecordingHistory.queue
    private var chunks: [Data] = []
    private var byteCount = 0
    private var closed = false
    private var audioError: String?
    // Capture is capped at five minutes; leave a little headroom for stopping.
    private static let maxBytes = 24_000 * 2 * 310

    public init(directory: URL = RecordingHistory.directory) { self.directory = directory }

    public func append(_ pcm: Data) {
        queue.async { [self] in
            guard !closed, audioError == nil else { return }
            guard byteCount + pcm.count <= Self.maxBytes else {
                audioError = "Audio exceeded the recording limit and was not saved."
                chunks.removeAll(); byteCount = 0; return
            }
            chunks.append(pcm); byteCount += pcm.count
        }
    }

    public func discard() {
        queue.async { [self] in closed = true; chunks.removeAll(); byteCount = 0 }
    }

    public func save(mode: VoiceMode, rawTranscript: String, result: TextResult?, error: String? = nil,
                     completion: @escaping @Sendable (Result<HistoryEntry?, Error>) -> Void) {
        RecordingHistory.pendingSaves.enter()
        queue.async { [self] in
            defer { RecordingHistory.pendingSaves.leave(); chunks.removeAll(); byteCount = 0 }
            guard !closed else { completion(.success(nil)); return }
            closed = true
            guard byteCount > 0 || !rawTranscript.isEmpty || result != nil else { completion(.success(nil)); return }
            do {
                let folder = RecordingHistory.folder(for: id, in: directory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                var audioFilename: String?
                if byteCount > 0 {
                    do {
                        let audioURL = folder.appendingPathComponent("audio.wav")
                        try waveFile().write(to: audioURL, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: audioURL.path)
                        audioFilename = "audio.wav"
                    } catch { audioError = "Audio could not be saved: \(error.localizedDescription)" }
                }
                let entry = HistoryEntry(id: id, createdAt: createdAt, mode: mode, rawTranscript: rawTranscript,
                                         correctedText: result?.text, audioFilename: audioFilename, audioError: audioError,
                                         processingError: error, sources: result?.sources ?? [])
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let metadata = folder.appendingPathComponent("transcript.json")
                try encoder.encode(entry).write(to: metadata, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadata.path)
                completion(.success(entry))
            } catch { completion(.failure(error)) }
        }
    }

    /// Graceful termination waits asynchronously for writes already enqueued.
    public static func whenSaved(_ completion: @escaping @Sendable () -> Void) {
        RecordingHistory.pendingSaves.notify(queue: .main, execute: completion)
    }

    private func waveFile() -> Data {
        var data = Data()
        data.reserveCapacity(44 + byteCount)
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + byteCount)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(24_000)); number(UInt32(48_000)); number(UInt16(2)); number(UInt16(16))
        text("data"); number(UInt32(byteCount))
        for chunk in chunks { data.append(chunk) }
        return data
    }
}
