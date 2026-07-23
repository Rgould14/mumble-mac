import Foundation
import Combine

/// JSON-file-backed store in ~/Library/Application Support/Mumble/.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings: AppSettings { didSet { save(settings, to: "settings.json") } }
    @Published var history: [TranscriptEntry] { didSet { save(history, to: "history.json") } }
    @Published var dictionary: [DictionaryWord] { didSet { save(dictionary, to: "dictionary.json") } }
    @Published var snippets: [Snippet] { didSet { save(snippets, to: "snippets.json") } }
    @Published var corrections: [Correction] { didSet { save(corrections, to: "corrections.json") } }

    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mumble")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private init() {
        settings = Self.load("settings.json") ?? AppSettings()
        history = Self.load("history.json") ?? []
        dictionary = Self.load("dictionary.json") ?? []
        snippets = Self.load("snippets.json") ?? []
        corrections = Self.load("corrections.json") ?? []
    }

    /// Record one learned correction, merging with an existing identical pair.
    func recordCorrection(original: String, corrected: String, appName: String) {
        let o = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !o.isEmpty, !c.isEmpty, o.lowercased() != c.lowercased(),
              o.count <= 80, c.count <= 80 else { return }
        if let i = corrections.firstIndex(where: {
            $0.original.lowercased() == o.lowercased() && $0.corrected.lowercased() == c.lowercased()
        }) {
            corrections[i].count += 1
            corrections[i].lastSeen = Date()
            corrections[i].appName = appName
        } else {
            corrections.insert(Correction(original: o, corrected: c, appName: appName), at: 0)
            if corrections.count > 300 {   // keep the store bounded
                corrections.removeLast(corrections.count - 300)
            }
        }
        Log.line("learned correction: '\(o)' -> '\(c)' (app \(appName))")
    }

    private static func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        try? enc.encode(value).write(to: Self.dir.appendingPathComponent(name), options: .atomic)
    }

    // MARK: Stats
    var totalWords: Int { history.reduce(0) { $0 + $1.wordCount } }
    var averageWPM: Int {
        let secs = history.reduce(0.0) { $0 + $1.durationSeconds }
        guard secs > 1 else { return 0 }
        return Int(Double(totalWords) / (secs / 60.0))
    }
    var longestStreak: Int {
        let days = Set(history.map { Calendar.current.startOfDay(for: $0.date) }).sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, Calendar.current.date(byAdding: .day, value: 1, to: p) == d {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            prev = d
        }
        return best
    }

    /// Words dictated per day, for the Insights heatmap.
    var wordsByDay: [Date: Int] {
        var out: [Date: Int] = [:]
        for e in history {
            out[Calendar.current.startOfDay(for: e.date), default: 0] += e.wordCount
        }
        return out
    }

    /// Corrections Mumble learned in the last 7 days, newest first.
    var correctionsThisWeek: [Correction] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return corrections.filter { $0.lastSeen >= cutoff }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Estimated minutes to type vs speak the same words, and the difference.
    /// Typing ~40 wpm, speaking ~150 wpm are conventional averages.
    var timeSaved: (savedMin: Double, typingMin: Double, speakingMin: Double) {
        let words = Double(totalWords)
        let typing = words / 40.0
        let speaking = words / 150.0
        return (typing - speaking, typing, speaking)
    }

    var streakDays: Int {
        let days = Set(history.map { Calendar.current.startOfDay(for: $0.date) })
        var streak = 0
        var day = Calendar.current.startOfDay(for: Date())
        while days.contains(day) {
            streak += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }
}
