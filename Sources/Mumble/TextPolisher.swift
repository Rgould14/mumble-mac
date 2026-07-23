import Foundation

/// Rule-based cleanup approximating Wispr Flow's "auto-edits": strips filler
/// words, fixes capitalization/spacing, applies the personal dictionary,
/// and expands snippets.
enum TextPolisher {
    static let fillers = ["um", "uh", "uhm", "erm", "hmm", "you know,", "i mean,"]

    /// Applied after any cleanup path (LLM or rule-based): whole-utterance snippet
    /// expansion and personal-dictionary corrections. Kept lightweight so it
    /// doesn't undo the LLM's formatting.
    static func postProcess(_ text: String, state: AppState) -> String {
        var out = text
        let lowered = out.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        if let snip = state.snippets.first(where: { $0.trigger.lowercased() == lowered }) {
            return snip.expansion
        }
        var fixes = 0
        for entry in state.dictionary where !entry.replaces.isEmpty {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: entry.replaces) + "\\b"
            let replaced = out.replacingOccurrences(of: pattern, with: entry.word, options: .regularExpression)
            if replaced != out { fixes += 1 }
            out = replaced
        }
        if fixes > 0 { state.settings.totalFixesApplied += fixes }
        return out
    }

    static func polish(_ raw: String, state: AppState) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        let settings = state.settings

        // Snippet expansion: if the whole utterance matches a trigger, expand it.
        let lowered = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if let snip = state.snippets.first(where: { $0.trigger.lowercased() == lowered }) {
            return snip.expansion
        }

        if settings.removeFillerWords {
            for f in fillers {
                let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: f) + "\\b[,]?\\s*"
                text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
        }

        // Personal dictionary replacements.
        for entry in state.dictionary where !entry.replaces.isEmpty {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: entry.replaces) + "\\b"
            text = text.replacingOccurrences(of: pattern, with: entry.word, options: .regularExpression)
        }

        // Whitespace + punctuation spacing cleanup.
        text = text.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if settings.autoCapitalize, let first = text.first, first.isLowercase {
            text = first.uppercased() + text.dropFirst()
        }
        return text
    }
}
