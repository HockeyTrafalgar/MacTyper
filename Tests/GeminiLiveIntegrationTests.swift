import XCTest
@testable import MacTyper

/// Live-API integration test: feeds a known speech WAV through the real
/// GeminiLiveSession and expects a transcript. Needs a Gemini API key —
/// taken from the GEMINI_API_KEY env var or ~/work/typer/.env — and
/// network access; skips when no key is available.
final class GeminiLiveIntegrationTests: XCTestCase {
    private func loadAPIKey() -> String? {
        if let k = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !k.isEmpty { return k }
        let envPath = ("~/work/typer/.env" as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else { return nil }
        for line in content.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("GEMINI_API_KEY=") {
                return String(t.dropFirst("GEMINI_API_KEY=".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
        }
        return nil
    }

    /// 16 kHz mono Int16 PCM of spoken text, synthesized on the fly.
    private func makeSpeechPCM() throws -> Data {
        let dir = FileManager.default.temporaryDirectory
        let wav = dir.appendingPathComponent("mactyper-test-speech.wav")
        if !FileManager.default.fileExists(atPath: wav.path) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            p.arguments = ["-o", wav.path, "--data-format=LEI16@16000",
                           "Hello world, this is a test of the transcription system."]
            try p.run()
            p.waitUntilExit()
        }
        let data = try Data(contentsOf: wav)
        return Data(data.dropFirst(44))  // strip WAV header; payload is raw PCM
    }

    func testLiveTranscription() async throws {
        guard let apiKey = loadAPIKey() else {
            throw XCTSkip("no GEMINI_API_KEY available")
        }
        let pcm = try makeSpeechPCM()
        let interims = InterimBox()
        let config = GeminiLiveSession.Config(
            apiKey: apiKey,
            model: "gemini-3.5-transcribe-live",
            languageCodes: [],
            customVocabulary: [],
            finishTimeoutS: 8)
        let session = GeminiLiveSession(config: config) { text in
            interims.append(text)
        }
        await session.connect()
        // Feed in 0.1 s chunks, roughly paced like the audio pipeline.
        var offset = 0
        while offset < pcm.count {
            let end = min(offset + 3200, pcm.count)
            await session.feed(pcm.subdata(in: offset..<end))
            offset = end
            try await Task.sleep(for: .milliseconds(20))
        }
        let text = await session.finish()
        print("TRANSCRIPT: \(text ?? "<nil>")  interims=\(interims.count)")
        XCTAssertNotNil(text, "no transcript returned")
        XCTAssertTrue(text!.lowercased().contains("hello"),
                      "unexpected transcript: \(text!)")
        XCTAssertGreaterThan(interims.count, 0, "no interim updates were delivered")
    }
}

/// Thread-safe interim collector (the callback is @Sendable).
private final class InterimBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }
}
