import Foundation

/// Assembles the final transcript from Gemini Live's stream of interim and
/// final segments. Pure logic, unit-tested. Ports the hard-won server
/// behavior fixes from the Python reference:
///
/// - The server emits a final segment after EVERY pause in speech (each
///   utterance is a "turn"), so finals accumulate across the session.
/// - Endpointer truncation guard ("tail-merge"): the server's final can
///   drop trailing words its own interim already heard. When the current
///   interim verifiably EXTENDS a final (same normalized words, then more),
///   the interim is the more complete text — keep it. Applied at every
///   final AND once more at merge time using the last interim ever seen.
struct TranscriptAssembler {
    private(set) var finals: [String] = []
    /// Cleared when a final lands (drives the HUD preview).
    private(set) var interim: String = ""
    /// Never cleared — the merge-time tail-recovery source.
    private(set) var lastInterim: String = ""

    /// Punctuation/case-insensitive word list for prefix comparison.
    static func normWords(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).compactMap { token in
            let cleaned = token.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            if cleaned.isEmpty { return nil }
            return String(String.UnicodeScalarView(cleaned)).lowercased()
        }
    }

    private static func extends(_ candidate: String, over base: String) -> Bool {
        let nb = normWords(base)
        let nc = normWords(candidate)
        return nc.count > nb.count && Array(nc.prefix(nb.count)) == nb
    }

    mutating func addInterim(_ text: String) {
        guard !text.isEmpty else { return }
        interim = text
        lastInterim = text
    }

    mutating func addFinal(_ text: String) {
        guard !text.isEmpty else { return }
        var final = text
        // Per-final tail recovery against this utterance's current interim.
        let cur = interim.trimmingCharacters(in: .whitespaces)
        if !cur.isEmpty, Self.extends(cur, over: final) {
            Log.gemini.info("segment tail recovered from interim")
            final = cur
        }
        finals.append(final)
        interim = ""
    }

    /// HUD preview: all finals plus the in-flight interim.
    var preview: String {
        ([finals.joined(separator: " "), interim]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
            .joined(separator: " ")
    }

    /// Final joined transcript, with merge-time tail recovery from the last
    /// interim ever seen (interims reset per utterance, so when the last
    /// interim extends the last final, the server finalized early).
    func mergedText() -> String? {
        var parts = finals.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let li = lastInterim.trimmingCharacters(in: .whitespaces)
        if !li.isEmpty {
            let last = parts.last ?? ""
            if Self.extends(li, over: last) {
                if parts.isEmpty {
                    parts = [li]
                } else {
                    Log.gemini.info("tail recovered from interim at merge")
                    parts[parts.count - 1] = li
                }
            }
        }
        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined
    }
}
