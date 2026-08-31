import XCTest
import SwiftUI
@testable import MacTyper

/// Renders the Settings view to a PNG so layout/alignment can be inspected
/// without a human clicking through the app.
final class SettingsRenderTests: XCTestCase {
    @MainActor
    func testRenderSettingsToPNG() throws {
        // Seed representative values so fields aren't empty.
        let s = AppSettings.shared
        let savedVocab = s.vocabulary
        let savedLangs = s.languageHints
        defer { s.vocabulary = savedVocab; s.languageHints = savedLangs }
        s.vocabulary = "Altegio,Strapi,Supabase,EvoClinic,Famaga,BPMN,CRM,Gemini"
        s.languageHints = "en-US,ru-RU"

        let view = SettingsView()
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 1400)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return XCTFail("no bitmap rep")
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("no png")
        }
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mactyper-settings.png")
        try png.write(to: out)
        print("SETTINGS_PNG: \(out.path)")
    }
}
