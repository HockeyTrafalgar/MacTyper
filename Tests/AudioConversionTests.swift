import XCTest
import AVFoundation
@testable import MacTyper

/// Exercises the mic → Gemini wire-format conversion (Float32 device rate →
/// 16 kHz mono Int16) without a live microphone, using the same formats
/// AVAudioEngine's input node produces.
final class AudioConversionTests: XCTestCase {
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                          channels: 1, interleaved: true)!

    private func sineBuffer(format: AVAudioFormat, frames: AVAudioFrameCount, hz: Double = 440) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let sr = format.sampleRate
        for ch in 0..<Int(format.channelCount) {
            let p = buf.floatChannelData![ch]
            for i in 0..<Int(frames) {
                p[i] = Float(0.5 * sin(2 * .pi * hz * Double(i) / sr))
            }
        }
        return buf
    }

    private func runConversion(inRate: Double, channels: AVAudioChannelCount,
                               interleaved: Bool = false) -> [Data] {
        let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inRate,
                                     channels: channels, interleaved: interleaved)!
        let converter = AVAudioConverter(from: inFormat, to: outFormat)!
        // Ten 0.1 s buffers, like the tap delivers.
        let frames = AVAudioFrameCount(inRate / 10)
        return (0..<10).compactMap { _ in
            AudioCapture.convertToWireFormat(sineBuffer(format: inFormat, frames: frames),
                                             using: converter, outFormat: outFormat)
        }
    }

    func testConvert48kMono() {
        let chunks = runConversion(inRate: 48000, channels: 1)
        let total = chunks.reduce(0) { $0 + $1.count }
        // 1 s of audio → ~16000 samples → ~32000 bytes (resampler latency
        // may hold back a few hundred frames).
        XCTAssertGreaterThan(total, 28000, "conversion produced almost no data: \(total) bytes")
        XCTAssertFalse(chunks.contains { $0.isEmpty })
    }

    func testConvert44_1kMono() {
        let total = runConversion(inRate: 44100, channels: 1).reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(total, 28000)
    }

    func testConvert48kStereo() {
        let total = runConversion(inRate: 48000, channels: 2).reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(total, 28000)
    }

    func testConvert16kMonoPassthroughRate() {
        let total = runConversion(inRate: 16000, channels: 1).reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(total, 28000)
    }

    func testConvert192kStereo() {
        // The user's real interface: 192 kHz 2 ch (12:1 resample ratio).
        let chunks = runConversion(inRate: 192000, channels: 2)
        let total = chunks.reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(total, 28000, "192k conversion produced almost no data: \(total) bytes over \(chunks.count) chunks")
        XCTAssertFalse(chunks.contains { $0.isEmpty })
    }

    func testOutputIsNotSilence() {
        let chunks = runConversion(inRate: 48000, channels: 1)
        let data = chunks.max(by: { $0.count < $1.count })!
        let peak = data.withUnsafeBytes { raw -> Int16 in
            raw.bindMemory(to: Int16.self).reduce(0) { max($0, Swift.abs($1)) }
        }
        XCTAssertGreaterThan(peak, 8000, "converted audio is near-silent (peak \(peak))")
    }
}
