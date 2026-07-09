import Foundation

struct TranscriptEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var appName: String
    var date: Date
    var durationSeconds: Double
    var wordCount: Int { text.split(separator: " ").count }
}

struct DictionaryWord: Codable, Identifiable, Equatable {
    var id = UUID()
    var word: String
    /// Optional misheard form to auto-correct from (e.g. "sked yellow" -> "Skedulo").
    var replaces: String = ""
}

struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Spoken trigger phrase, e.g. "insert meeting link".
    var trigger: String
    var expansion: String
}

enum ActivationGesture: String, Codable, CaseIterable {
    case hold = "Hold to talk"
    case doubleTap = "Double-tap to toggle"
}

struct AppSettings: Codable, Equatable {
    /// Push-to-talk key: fn (default, like Wispr Flow on Apple keyboards)
    /// or ctrl+option (Wispr's fallback for non-Apple keyboards).
    var useFnKey = true
    var gesture: ActivationGesture = .hold
    var playSounds = true
    var removeFillerWords = true
    var autoCapitalize = true
    var localeIdentifier = Locale.current.identifier
    var onDeviceOnly = false
    var maxSessionMinutes = 20
    var hasCompletedOnboarding = false

    /// Stage-2 LLM cleanup (the Wispr Flow "auto-edits" layer): rewrites the raw
    /// transcript to fix mis-transcribed words, punctuation, and tone-per-app.
    /// Falls back to rule-based polishing when off, offline, or no key.
    var useAICleanup = true
    /// Claude model for the cleanup pass. Opus 4.8 by default; switch to
    /// claude-haiku-4-5 for lowest latency.
    var cleanupModel = "claude-opus-4-8"
    /// Anthropic API key. If empty, ANTHROPIC_API_KEY from the environment is used.
    var anthropicAPIKey = ""
    var adaptToneByApp = true
}
