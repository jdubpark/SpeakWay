import AVFoundation
import SpeakWayCore

@MainActor final class AudioCapture {
    private let engine = AVAudioEngine()
    private var tapped = false
    private var startID: UUID?

    func start(format: AVAudioFormat, onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
               onLevel: @escaping (Float) -> Void, onFailure: @escaping (Error) -> Void) async throws {
        let id = UUID(); startID = id
        let allowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            ? true : await AVCaptureDevice.requestAccess(for: .audio)
        try Task.checkCancellation()
        guard startID == id else { throw CancellationError() }
        guard allowed else { throw SpeakWayError.message("Allow microphone access in System Settings → Privacy & Security → Microphone, then try again.") }
        let node = engine.inputNode
        let input = node.outputFormat(forBus: 0)
        guard input.sampleRate > 0, input.channelCount > 0,
              let converter = AVAudioConverter(from: input, to: format) else {
            throw SpeakWayError.message("No microphone is available. Connect or select one in System Settings → Sound.")
        }
        node.installTap(onBus: 0, bufferSize: 4096, format: input) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / input.sampleRate) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return buffer
            }
            if let conversionError {
                Task { @MainActor in onFailure(conversionError) }; return
            }
            guard status != .error, converted.frameLength > 0 else { return }
            var sum: Float = 0
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
                sum = min(1, sqrt(sum / Float(buffer.frameLength)) * 7)
            }
            let level = sum
            onBuffer(converted)
            Task { @MainActor in onLevel(level) }
        }
        tapped = true
        do { engine.prepare(); try engine.start() }
        catch { stop(); throw error }
    }

    func stop() {
        startID = nil
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
    }
}
