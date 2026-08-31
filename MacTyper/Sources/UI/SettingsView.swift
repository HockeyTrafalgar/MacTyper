import SwiftUI

/// Settings window: Gemini API key (Keychain-backed), engine options,
/// triggers, HUD, and clipboard behavior.
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var apiKeyDraft: String = AppSettings.shared.apiKey
    @State private var apiKeySaved = false
    @State private var validating = false
    @State private var validation: (ok: Bool, message: String)?

    var onMouseTriggerChanged: () -> Void = {}
    var onAllPermissionsGranted: () -> Void = {}

    var body: some View {
        Form {
            PermissionsSection(onAllGranted: onAllPermissionsGranted)

            Section("Gemini API") {
                TextField("API key", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Button("Save & Test Key") {
                        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        settings.apiKey = key
                        apiKeySaved = true
                        validating = true
                        validation = nil
                        Task {
                            let result = await APIKeyValidator.validate(key)
                            await MainActor.run {
                                validation = result
                                validating = false
                            }
                        }
                    }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty || validating)
                    if validating {
                        ProgressView().controlSize(.small)
                        Text("Checking key…").foregroundStyle(.secondary)
                    } else if let validation {
                        Label(validation.message,
                              systemImage: validation.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(validation.ok ? .green : .red)
                            .help(validation.message)
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                    TextField("gemini-3.5-transcribe-live", text: Binding(
                        get: { settings.geminiModel },
                        set: { settings.geminiModel = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Text("Gemini Live transcription model ID — change only when Google ships a newer one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Language hints")
                    TextField("e.g. en-US,ru-RU — empty = auto-detect", text: Binding(
                        get: { settings.languageHints },
                        set: { settings.languageHints = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Text("Comma-separated BCP-47 codes; hinting the languages you actually speak improves recognition.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom vocabulary")
                    TextField("names, jargon, comma-separated", text: Binding(
                        get: { settings.vocabulary },
                        set: { settings.vocabulary = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
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
        .frame(width: 560, height: 780)
    }
}
