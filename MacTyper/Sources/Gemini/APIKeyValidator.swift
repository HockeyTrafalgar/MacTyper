import Foundation

/// Cheap Gemini API key check: lists one model over REST. A wrong key
/// fails fast with the server's own explanation.
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
