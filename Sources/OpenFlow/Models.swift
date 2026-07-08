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
}
