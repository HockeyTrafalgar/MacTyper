import SwiftUI

/// Searchable multi-select dropdown for the Gemini language hints.
/// Persists as the same comma-separated BCP-47 string as before, so the
/// session config code is untouched. Empty selection = auto-detect.
struct LanguagePicker: View {
    @Binding var selection: String   // comma-separated BCP-47 codes
    @State private var open = false
    @State private var query = ""

    struct Language: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    static let all: [Language] = {
        let codes = [
            "en-US", "en-GB", "en-AU", "en-IN", "ru-RU", "uk-UA",
            "es-ES", "es-MX", "pt-BR", "pt-PT", "fr-FR", "fr-CA",
            "de-DE", "it-IT", "nl-NL", "pl-PL", "cs-CZ", "sk-SK",
            "ro-RO", "hu-HU", "bg-BG", "hr-HR", "sr-RS", "sl-SI",
            "el-GR", "tr-TR", "ar-EG", "ar-SA", "he-IL", "fa-IR",
            "hi-IN", "bn-BD", "ur-PK", "ta-IN", "te-IN", "mr-IN",
            "gu-IN", "kn-IN", "ml-IN", "pa-IN", "th-TH", "vi-VN",
            "id-ID", "ms-MY", "fil-PH", "ja-JP", "ko-KR", "zh-CN",
            "zh-TW", "sv-SE", "nb-NO", "da-DK", "fi-FI", "is-IS",
            "et-EE", "lv-LV", "lt-LT", "ka-GE", "hy-AM", "az-AZ",
            "kk-KZ", "uz-UZ", "ky-KG", "mn-MN", "ne-NP", "si-LK",
            "km-KH", "lo-LA", "my-MM", "am-ET", "sw-KE", "af-ZA",
            "zu-ZA", "sq-AL", "mk-MK", "bs-BA", "ca-ES", "eu-ES",
            "gl-ES", "be-BY",
        ]
        return codes.map { code in
            let name = Locale.current.localizedString(forIdentifier: code) ?? code
            return Language(code: code, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    private var selectedCodes: [String] {
        selection.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var summary: String {
        let codes = selectedCodes
        if codes.isEmpty { return "Auto-detect (all languages)" }
        let names = codes.map { code in
            Self.all.first(where: { $0.code == code })?.name ?? code
        }
        return names.joined(separator: ", ")
    }

    private var filtered: [Language] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Self.all }
        return Self.all.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.code.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack {
                Text(summary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(selectedCodes.isEmpty ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                TextField("Search languages…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filtered) { lang in
                            Toggle(isOn: binding(for: lang.code)) {
                                HStack {
                                    Text(lang.name)
                                    Spacer()
                                    Text(lang.code)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                        }
                        if filtered.isEmpty {
                            Text("No matches").foregroundStyle(.secondary).padding(12)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(width: 340, height: 320)
                Divider()
                HStack {
                    Button("Clear (auto-detect)") {
                        selection = ""
                    }
                    .disabled(selectedCodes.isEmpty)
                    Spacer()
                    Text(selectedCodes.isEmpty ? "No hints" : "\(selectedCodes.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Done") { open = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(10)
            }
        }
    }

    private func binding(for code: String) -> Binding<Bool> {
        Binding(
            get: { selectedCodes.contains(code) },
            set: { on in
                var codes = selectedCodes
                if on {
                    if !codes.contains(code) { codes.append(code) }
                } else {
                    codes.removeAll { $0 == code }
                }
                selection = codes.joined(separator: ",")
            })
    }
}
