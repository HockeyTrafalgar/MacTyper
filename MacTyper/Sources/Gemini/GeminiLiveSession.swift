import Foundation

/// One Gemini Live streaming transcription session per dictation.
///
/// Wire protocol (proto-JSON over WebSocket, camelCase — mirrors what the
/// google-genai Python SDK sends):
///  1. client → `{"setup": {"model": "models/…", "generationConfig":
///     {"responseModalities": ["TEXT"]}, "inputAudioTranscription":
///     {"languageCodes": […], "mode": "SMART", "customVocabulary": […]}}}`
///  2. server → `{"setupComplete": {}}`
///  3. client → `{"realtimeInput": {"audio": {"data": "<b64 16-bit LE PCM>",
///     "mimeType": "audio/pcm;rate=16000"}}}` per chunk
///  4. on finish: ~1 s of silence (endpointer-convergence trick), then
///     `{"realtimeInput": {"audioStreamEnd": true}}`
///  5. server → `{"serverContent": {"interimInputTranscription": {"text":…}
///     | "inputTranscription": {"text":…} | "generationComplete": true
///     | "turnComplete": true}}`
///
/// Audio fed before `setupComplete` is buffered and flushed on the ack, so
/// the ~0.6 s handshake overlaps with the first words.
actor GeminiLiveSession {
    struct Config {
        var apiKey: String
        var model: String
        var languageCodes: [String]
        var customVocabulary: [String]
        var finishTimeoutS: Double
    }

    enum SessionError: Error { case connectFailed, serverClosed }

    private let config: Config
    private let onInterim: @Sendable (String) -> Void

    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var assembler = TranscriptAssembler()
    private var setupDone = false
    private var pendingAudio: [Data] = []
    private var closing = false
    private var aborted = false
    private var failed = false
    private var readerFinished = false
    private var lastEventAt = ContinuousClock.now
    private let startedAt = ContinuousClock.now

    init(config: Config, onInterim: @escaping @Sendable (String) -> Void) {
        self.config = config
        self.onInterim = onInterim
    }

    // MARK: - Lifecycle

    func connect() {
        var request = URLRequest(url: URL(string:
            "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!)
        request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")
        let session = URLSession(configuration: .default)
        let ws = session.webSocketTask(with: request)
        ws.maximumMessageSize = 8 * 1024 * 1024
        task = ws
        ws.resume()
        sendSetup()
        receiveLoop = Task { await self.runReceiveLoop() }
    }

    private func sendSetup() {
        var transcription: [String: Any] = ["mode": "SMART"]
        if !config.languageCodes.isEmpty { transcription["languageCodes"] = config.languageCodes }
        if !config.customVocabulary.isEmpty { transcription["customVocabulary"] = config.customVocabulary }
        let modelName = config.model.hasPrefix("models/") ? config.model : "models/\(config.model)"
        let setup: [String: Any] = [
            "setup": [
                "model": modelName,
                "generationConfig": ["responseModalities": ["TEXT"]],
                "inputAudioTranscription": transcription,
            ] as [String: Any],
        ]
        sendJSON(setup)
    }

    private func sendJSON(_ obj: [String: Any]) {
        guard let task, !failed else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        let text = String(decoding: data, as: UTF8.self)
        task.send(.string(text)) { [weak self] error in
            if let error {
                Log.gemini.error("ws send failed: \(error.localizedDescription)")
                Task { await self?.markFailed() }
            }
        }
    }

    private func markFailed() {
        failed = true
        readerFinished = true
    }

    // MARK: - Client API

    /// Queue 16 kHz mono 16-bit LE PCM for streaming. Cheap; called from the
    /// audio pipeline ~10×/s.
    func feed(_ pcm: Data) {
        guard !closing, !failed, !pcm.isEmpty else { return }
        if setupDone {
            sendAudioChunk(pcm)
        } else {
            pendingAudio.append(pcm)
        }
    }

    private func sendAudioChunk(_ pcm: Data) {
        let msg: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "data": pcm.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=16000",
                ],
            ],
        ]
        sendJSON(msg)
    }

    /// Signal end-of-speech and wait for the final transcript. Returns the
    /// joined text, or nil when the session failed / heard nothing.
    /// Bounded two ways: the hard finish timeout, and a 1.2 s no-server-
    /// traffic window after stream end (if the user released after silence,
    /// the last utterance was already finalized and nothing more will come).
    func finish() async -> String? {
        guard !aborted else { return nil }
        closing = true
        // ~1 s of trailing silence so the server's endpointer converges on
        // the complete utterance (its final can otherwise drop words spoken
        // right before an abrupt stream end).
        sendAudioChunkFlushed(Data(count: 32000))
        sendJSON(["realtimeInput": ["audioStreamEnd": true]])
        lastEventAt = ContinuousClock.now

        let quietGrace = Duration.milliseconds(1200)
        let deadline = ContinuousClock.now + .seconds(config.finishTimeoutS)
        while !readerFinished {
            let now = ContinuousClock.now
            if now >= deadline {
                Log.gemini.warning("finish: no completion within \(self.config.finishTimeoutS, format: .fixed(precision: 1))s — using \(self.assembler.finals.count) collected segment(s)")
                break
            }
            if now - lastEventAt >= quietGrace {
                Log.gemini.debug("finish: quiet after stream end — transcript complete")
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let text = (failed && assembler.finals.isEmpty) ? nil : assembler.mergedText()
        teardown()
        return text
    }

    /// If setup hasn't completed yet, make sure buffered audio goes first.
    private func sendAudioChunkFlushed(_ pcm: Data) {
        if !setupDone && !pendingAudio.isEmpty {
            // Setup never completed — flush order is preserved by the queue;
            // append and let the setupComplete handler send everything.
            pendingAudio.append(pcm)
            return
        }
        sendAudioChunk(pcm)
    }

    /// Cancelled session (Esc): stop streaming, discard everything.
    func abort() {
        aborted = true
        closing = true
        teardown()
    }

    private func teardown() {
        receiveLoop?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: - Receive loop

    private func runReceiveLoop() async {
        guard let task else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleServerMessage(Data(text.utf8))
                case .data(let data):
                    handleServerMessage(data)
                @unknown default:
                    break
                }
                if readerFinished { return }
            } catch {
                if !closing && !aborted {
                    Log.gemini.error("ws receive failed: \(error.localizedDescription)")
                    failed = true
                }
                readerFinished = true
                return
            }
        }
    }

    private func handleServerMessage(_ data: Data) {
        lastEventAt = ContinuousClock.now
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if obj["setupComplete"] != nil {
            setupDone = true
            let elapsed = ContinuousClock.now - startedAt
            Log.gemini.info("connected in \(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000) ms; flushing \(self.pendingAudio.count) buffered chunk(s)")
            let buffered = pendingAudio
            pendingAudio.removeAll()
            for chunk in buffered { sendAudioChunk(chunk) }
            return
        }
        guard let sc = obj["serverContent"] as? [String: Any] else { return }
        if let it = sc["interimInputTranscription"] as? [String: Any],
           let text = it["text"] as? String, !text.isEmpty {
            assembler.addInterim(text)
            onInterim(assembler.preview)
        }
        if let ft = sc["inputTranscription"] as? [String: Any],
           let text = ft["text"] as? String, !text.isEmpty {
            assembler.addFinal(text)
            onInterim(assembler.preview)
            Log.gemini.debug("final segment received")
        }
        let generationComplete = (sc["generationComplete"] as? Bool) ?? false
        let turnComplete = (sc["turnComplete"] as? Bool) ?? false
        if generationComplete || turnComplete {
            // Only end-of-session once our audioStreamEnd is on the wire —
            // the server completes a "turn" after every mid-speech pause.
            if closing {
                readerFinished = true
            } else {
                Log.gemini.debug("utterance complete (mid-session, \(self.assembler.finals.count) segment(s) so far)")
            }
        }
    }
}
