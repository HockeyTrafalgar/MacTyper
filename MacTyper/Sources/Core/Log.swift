import Foundation
import os

/// Central loggers. Use `Log.app.info(...)` etc. Never log the API key or
/// full transcripts at levels that persist (transcripts are private data;
/// keep them at .debug, which is off unless streamed via Console.app).
enum Log {
    static let app = Logger(subsystem: "com.timurvalishev.mactyper", category: "app")
    static let input = Logger(subsystem: "com.timurvalishev.mactyper", category: "input")
    static let audio = Logger(subsystem: "com.timurvalishev.mactyper", category: "audio")
    static let gemini = Logger(subsystem: "com.timurvalishev.mactyper", category: "gemini")
    static let hud = Logger(subsystem: "com.timurvalishev.mactyper", category: "hud")
    static let paste = Logger(subsystem: "com.timurvalishev.mactyper", category: "paste")
}
