import Foundation
import Combine

/// JSON-file-backed store in ~/Library/Application Support/OpenFlow/.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings: AppSettings { didSet { save(settings, to: "settings.json") } }
    @Published var history: [TranscriptEntry] { didSet { save(history, to: "history.json") } }
    @Published var dictionary: [DictionaryWord] { didSet { save(dictionary, to: "dictionary.json") } }
    @Published var snippets: [Snippet] { didSet { save(snippets, to: "snippets.json") } }

    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenFlow")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private init() {
        settings = Self.load("settings.json") ?? AppSettings()
        history = Self.load("history.json") ?? []
        dictionary = Self.load("dictionary.json") ?? []
        snippets = Self.load("snippets.json") ?? []
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
