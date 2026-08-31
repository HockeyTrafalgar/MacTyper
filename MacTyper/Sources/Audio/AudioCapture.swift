import Foundation
import AVFoundation

/// Persistent microphone capture.
///
/// The engine is started once and kept running for the process lifetime —
/// CoreAudio's open latency (~100-300 ms) would otherwise swallow the first
/// words of every dictation. Between sessions the tap is a cheap no-op.
///
/// The input node follows the system default device; when the default
/// changes (or the device unplugs), AVAudioEngine stops itself and posts
/// `AVAudioEngineConfigurationChange` — we rebuild the converter for the
/// new input format and restart. A 60 s watchdog restarts a silently
/// stalled engine (never mid-session).
final class AudioCapture {
    /// Called on an internal queue with (16 kHz mono Int16 PCM, smoothed 0..1 mic level).
    var onAudio: ((Data, Double) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.timurvalishev.mactyper.audio")
    private var converter: AVAudioConverter?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                          channels: 1, interleaved: true)!
    private var sessionActive = false          // guarded by `queue`
    private var lastBufferAt = Date()
    private var watchdog: Timer?
    private var restartPending = false

    func start() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(configurationChanged),
            name: .AVAudioEngineConfigurationChange, object: engine)
        startEngine()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func startEngine() {
        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            Log.audio.error("no usable input device (format \(inFormat)) — will retry on config change / watchdog")
            return
        }
        converter = AVAudioConverter(from: inFormat, to: outFormat)
        input.removeTap(onBus: 0)
        // ~0.1 s buffers at the device rate.
        let bufSize = AVAudioFrameCount(inFormat.sampleRate / 10)
        input.installTap(onBus: 0, bufferSize: bufSize, format: inFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
            Log.audio.info("audio engine started (in: \(inFormat.sampleRate) Hz \(inFormat.channelCount) ch)")
        } catch {
            Log.audio.error("engine start failed: \(error.localizedDescription)")
        }
    }

    @objc private func configurationChanged(_ note: Notification) {
        Log.audio.info("audio configuration changed (device switch?) — restarting engine")
        queue.async { [weak self] in
            guard let self else { return }
            if self.sessionActive {
                // Never yank the stream out from under an in-flight
                // dictation; retry when the session ends or on watchdog.
                Log.audio.warning("config change mid-session — deferring restart")
                self.restartPending = true
                return
            }
            DispatchQueue.main.async { self.restart() }
        }
    }

    private func restart() {
        engine.stop()
        startEngine()
    }

    private func watchdogTick() {
        queue.async { [weak self] in
            guard let self, !self.sessionActive else { return }
            let stalled = Date().timeIntervalSince(self.lastBufferAt) > 55
            let needRestart = self.restartPending || !self.engine.isRunning || stalled
            if needRestart {
                Log.audio.warning("watchdog: engine unhealthy (running=\(self.engine.isRunning) stalled=\(stalled) pending=\(self.restartPending)) — restarting")
                self.restartPending = false
                DispatchQueue.main.async { self.restart() }
            }
        }
    }

    // MARK: - Session gating

    func beginSession() {
        queue.async { [weak self] in
            guard let self else { return }
            self.sessionActive = true
            self.micLevelSmoothed = 0
        }
        // Health-check inline like the Python session-start path: if the
        // engine died since the last session, restart it now.
        if !engine.isRunning {
            Log.audio.warning("session start: engine not running — restarting inline")
            restart()
        }
    }

    func endSession() {
        queue.async { [weak self] in
            guard let self else { return }
            self.sessionActive = false
            if self.restartPending {
                self.restartPending = false
                DispatchQueue.main.async { self.restart() }
            }
        }
    }

    // MARK: - Buffer path

    // Smoothed mic level: fast attack / slow release, noise floor subtracted,
    // sqrt for a perceptual response (port of `_emit_mic_level`).
    private var micLevelSmoothed: Double = 0
    private let levelFloor = 0.004
    private let levelAttack = 0.6
    private let levelRelease = 0.3
    private let levelRef = 0.12

    /// Convert one input buffer to 16 kHz mono Int16 PCM. Static and pure
    /// (converter carries the resampler state between calls) so it's unit-
    /// testable without a live microphone.
    static func convertToWireFormat(_ buffer: AVAudioPCMBuffer,
                                    using converter: AVAudioConverter,
                                    outFormat: AVAudioFormat) -> Data? {
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let error {
            Log.audio.error("convert failed: \(error.localizedDescription)")
            return nil
        }
        guard out.frameLength > 0, let int16 = out.int16ChannelData?[0] else { return nil }
        return Data(bytes: int16, count: Int(out.frameLength) * MemoryLayout<Int16>.size)
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lastBufferAt = Date()
            guard self.sessionActive, let converter = self.converter else { return }

            // RMS on the raw float buffer for the level meter.
            var rms = 0.0
            if let ch = buffer.floatChannelData?[0] {
                let n = Int(buffer.frameLength)
                if n > 0 {
                    var sum: Double = 0
                    for i in 0..<n { let v = Double(ch[i]); sum += v * v }
                    rms = (sum / Double(n)).squareRoot()
                }
            }
            let eff = max(0, rms - self.levelFloor)
            let target = self.levelRef > 0 ? min(1.0, (eff / self.levelRef).squareRoot()) : 0
            let coeff = target > self.micLevelSmoothed ? self.levelAttack : self.levelRelease
            self.micLevelSmoothed += coeff * (target - self.micLevelSmoothed)

            // Convert to 16 kHz mono Int16 — exactly Gemini's wire format.
            guard let data = Self.convertToWireFormat(buffer, using: converter, outFormat: self.outFormat),
                  !data.isEmpty else {
                Log.audio.error("conversion produced no data (in: \(buffer.format.sampleRate) Hz, \(buffer.frameLength) frames)")
                return
            }
            self.onAudio?(data, self.micLevelSmoothed)
        }
    }
}
