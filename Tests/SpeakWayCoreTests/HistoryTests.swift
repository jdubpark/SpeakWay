import Foundation
import AVFoundation
import Testing
@testable import SpeakWayCore

private func save(_ archive: RecordingArchive, text: String, result: TextResult?) async throws -> HistoryEntry? {
    try await withCheckedThrowingContinuation { continuation in
        archive.save(mode: .dictate, rawTranscript: text, result: result) { outcome in
            #expect(!Thread.isMainThread)
            continuation.resume(with: outcome)
        }
    }
}

@Test func historyRetainsRawAndCorrectedTextWithPlayableOrderedAudio() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let archive = RecordingArchive(directory: root)
    archive.append(Data([0x00, 0x00, 0xff, 0x7f]))
    archive.append(Data([0x00, 0x80, 0x01, 0x00]))
    let raw = "Tuesday, oh wait, that’s incorrect. I meant Wednesday."
    let entry = try #require(try await save(archive, text: raw, result: TextResult(text: "**Wednesday.**")))
    let saved = try #require(RecordingHistory.load(from: root).first)
    #expect(saved.id == entry.id && saved.rawTranscript == raw)
    #expect(saved.correctedText == "**Wednesday.**" && saved.audioError == nil)
    let url = RecordingHistory.folder(for: entry.id, in: root).appendingPathComponent(try #require(entry.audioFilename))
    let audio = try AVAudioFile(forReading: url)
    #expect(audio.length == 4 && audio.fileFormat.sampleRate == 24_000 && audio.fileFormat.channelCount == 1)
    let data = try Data(contentsOf: url)
    #expect(Array(data.suffix(8)) == [0x00, 0x00, 0xff, 0x7f, 0x00, 0x80, 0x01, 0x00])
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
}

@Test func discardedAudioAndLateChunksCannotLeakIntoTheNextRecording() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cancelled = RecordingArchive(directory: root)
    cancelled.append(Data([1, 0])); cancelled.discard(); cancelled.append(Data([2, 0]))
    #expect(try await save(cancelled, text: "Cancelled", result: nil) == nil)
    let next = RecordingArchive(directory: root)
    next.append(Data([3, 0]))
    let entry = try #require(try await save(next, text: "Next turn", result: TextResult(text: "Next turn.")))
    next.append(Data([4, 0]))
    #expect(try await save(next, text: "Duplicate", result: nil) == nil)
    let entries = try RecordingHistory.load(from: root)
    #expect(entries.count == 1 && entries[0].rawTranscript == "Next turn")
    let data = try Data(contentsOf: RecordingHistory.folder(for: entry.id, in: root).appendingPathComponent("audio.wav"))
    #expect(data.count == 46 && Array(data.suffix(2)) == [3, 0])
}

@Test func archiveWriteFailureIsReportedWithoutOverwritingExistingFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("A file cannot contain a history folder".utf8).write(to: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let result = TextResult(text: "Wednesday.")
    let archive = RecordingArchive(directory: root)
    do {
        _ = try await save(archive, text: "Tuesday, I mean Wednesday", result: result)
        Issue.record("An unwritable history location must report its failure")
    } catch {
        #expect(try String(contentsOf: root, encoding: .utf8) == "A file cannot contain a history folder")
    }
}

@Test func editingHistoryImmediatelyAfterSavePreservesOriginalsAndAudio() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let archive = RecordingArchive(directory: root)
    archive.append(Data([1, 0, 2, 0]))
    archive.save(mode: .dictate, rawTranscript: "Tuesday, actually Wednesday", result: TextResult(text: "Wednesday.")) { result in
        if case .failure(let error) = result { Issue.record("Initial save failed: \(error)") }
    }
    let firstEdit = try await RecordingHistory.saveEdit(id: archive.id, text: "Thursday.\n\n- Bring notes", in: root)
    let secondEdit = try await RecordingHistory.saveEdit(id: archive.id, text: "Friday.", in: root)
    #expect(firstEdit.correctedText == "Wednesday." && secondEdit.correctedText == "Wednesday.")
    let saved = try #require(RecordingHistory.load(from: root).first)
    #expect(saved.rawTranscript == "Tuesday, actually Wednesday" && saved.displayText == "Friday.")
    #expect(saved.editedAt != nil && saved.createdAt == firstEdit.createdAt && saved.audioFilename == "audio.wav")
    let audioURL = RecordingHistory.folder(for: archive.id, in: root).appendingPathComponent("audio.wav")
    #expect(Array(try Data(contentsOf: audioURL).suffix(4)) == [1, 0, 2, 0])
    do { _ = try await RecordingHistory.saveEdit(id: archive.id, text: " \n", in: root); Issue.record("Empty edit must fail") } catch {}
    #expect(try RecordingHistory.load(from: root).first?.displayText == "Friday.")
}
