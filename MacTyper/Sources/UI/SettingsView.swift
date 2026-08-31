import SwiftUI

/// Settings window: Gemini API key (Keychain-backed), engine options,
/// triggers, HUD, and clipboard behavior.
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var apiKeyDraft: String = AppSettings.shared.apiKey
    @State private var apiKeySaved = false

    var onMouseTriggerChanged: () -> Void = {}

    var body: some View {
        Form {
            Section("Gemini API") {
                SecureField("API key", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save Key") {
                        settings.apiKey = apiKeyDraft
                        apiKeySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { apiKeySaved = false }
                    }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if apiKeySaved {
                        Label("Saved to Keychain", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if settings.apiKeyPresent {
                        Label("Key stored in Keychain", systemImage: "key.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("No key set — dictation is disabled", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Link("Get a key at aistudio.google.com",
                     destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.caption)

                TextField("Model", text: Binding(
                    get: { settings.geminiModel },
                    set: { settings.geminiModel = $0 }))
                TextField("Language hints (e.g. en-US,ru-RU; empty = auto)", text: Binding(
                    get: { settings.languageHints },
                    set: { settings.languageHints = $0 }))
                TextField("Custom vocabulary (comma-separated)", text: Binding(
                    get: { settings.vocabulary },
                    set: { settings.vocabulary = $0 }))
            }

            Section("Triggers") {
                LabeledContent("Hold to talk", value: "Right ⌘ or F18")
                LabeledContent("Toggle on/off", value: "F19 (while holding F18: latch)")
                LabeledContent("Cancel", value: "Esc")
                Toggle("Left-click long-press starts dictation", isOn: Binding(
                    get: { settings.mouseTriggerEnabled },
                    set: { settings.mouseTriggerEnabled = $0; onMouseTriggerChanged() }))
                if settings.mouseTriggerEnabled {
                    HStack {
                        Text("Hold duration")
                        Slider(value: Binding(
                            get: { Double(settings.mouseHoldMs) },
                            set: { settings.mouseHoldMs = Int($0) }), in: 300...1500, step: 50)
                        Text("\(settings.mouseHoldMs) ms").monospacedDigit().frame(width: 64)
                    }
                }
            }

            Section("Overlay") {
                Toggle("Show floating transcript overlay", isOn: Binding(
                    get: { settings.overlayEnabled },
                    set: { settings.overlayEnabled = $0 }))
                Picker("Placement", selection: Binding(
                    get: { settings.overlayPlacement },
                    set: { settings.overlayPlacement = $0 })) {
                    Text("Near text caret").tag("caret")
                    Text("Near mouse cursor").tag("cursor")
                    Text("Bottom of screen").tag("bottom")
                }
            }

            Section("Clipboard") {
                Toggle("Restore clipboard after pasting", isOn: Binding(
                    get: { settings.restoreClipboard },
                    set: { settings.restoreClipboard = $0 }))
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
    }
}
