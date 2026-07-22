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

/// A learned correction: the user changed `original` (what we inserted) into
/// `corrected` after dictation. Repeats increase `count`; high-count
/// corrections are applied automatically and all recent ones are fed to the
/// AI cleanup prompt as style/vocabulary guidance.
struct Correction: Codable, Identifiable, Equatable {
    var id = UUID()
    var original: String
    var corrected: String
    var appName: String = ""
    var count: Int = 1
    var lastSeen: Date = Date()
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

    /// Capture from the built-in mic even when a Bluetooth headset is the
    /// system default input. BT headset mics force the low-quality HFP profile
    /// (degrading music), engage slowly, and often deliver no audio on macOS.
    var preferBuiltInMic = true

    /// Learn from post-dictation edits: re-read the target field after
    /// insertion, diff against what was inserted, and remember corrections.
    var enableLearning = true
}

// Tolerant decoding: new fields fall back to their defaults instead of failing
// the whole settings file (which would silently reset everything, incl. API key).
extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        useFnKey = try c.decodeIfPresent(Bool.self, forKey: .useFnKey) ?? d.useFnKey
        gesture = try c.decodeIfPresent(ActivationGesture.self, forKey: .gesture) ?? d.gesture
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? d.playSounds
        removeFillerWords = try c.decodeIfPresent(Bool.self, forKey: .removeFillerWords) ?? d.removeFillerWords
        autoCapitalize = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? d.autoCapitalize
        localeIdentifier = try c.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? d.localeIdentifier
        onDeviceOnly = try c.decodeIfPresent(Bool.self, forKey: .onDeviceOnly) ?? d.onDeviceOnly
        maxSessionMinutes = try c.decodeIfPresent(Int.self, forKey: .maxSessionMinutes) ?? d.maxSessionMinutes
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        useAICleanup = try c.decodeIfPresent(Bool.self, forKey: .useAICleanup) ?? d.useAICleanup
        cleanupModel = try c.decodeIfPresent(String.self, forKey: .cleanupModel) ?? d.cleanupModel
        anthropicAPIKey = try c.decodeIfPresent(String.self, forKey: .anthropicAPIKey) ?? d.anthropicAPIKey
        adaptToneByApp = try c.decodeIfPresent(Bool.self, forKey: .adaptToneByApp) ?? d.adaptToneByApp
        preferBuiltInMic = try c.decodeIfPresent(Bool.self, forKey: .preferBuiltInMic) ?? d.preferBuiltInMic
        enableLearning = try c.decodeIfPresent(Bool.self, forKey: .enableLearning) ?? d.enableLearning
    }
}
