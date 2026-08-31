import Foundation

/// Cheap Gemini API key check: lists one model over REST. A wrong key
/// fails fast with the server's own explanation.
/// Fetches the model IDs usable for live transcription (models exposing the
/// bidiGenerateContent method) so Settings can offer a real dropdown.
enum ModelCatalog {
    static func fetchLiveModels(apiKey: String) async -> [String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200")!)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { model -> String? in
            guard let name = model["name"] as? String,
                  let methods = model["supportedGenerationMethods"] as? [String],
                  methods.contains("bidiGenerateContent") else { return nil }
            return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        }.sorted { a, b in
            // Transcription models first, then alphabetical.
            let ta = a.contains("transcribe"), tb = b.contains("transcribe")
            if ta != tb { return ta }
            return a < b
        }
    }
}

enum APIKeyValidator {
    static func validate(_ key: String) async -> (ok: Bool, message: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "Key is empty") }
        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1")!)
        request.setValue(trimmed, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return (true, "Key is valid") }
            // Error payload: {"error": {"message": "...", ...}}
            var detail = "HTTP \(status)"
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any],
               let msg = err["message"] as? String {
                detail = String(msg.prefix(140))
            }
            return (false, detail)
        } catch {
            return (false, "Network error: \(error.localizedDescription)")
        }
    }
}
