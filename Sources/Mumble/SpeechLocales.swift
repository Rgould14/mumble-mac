import Speech
import Foundation

/// Languages the on-system speech recognizer supports, with display names.
enum SpeechLocales {
    static let all: [(id: String, name: String)] = SFSpeechRecognizer.supportedLocales()
        .map { l in
            (l.identifier,
             Locale.current.localizedString(forIdentifier: l.identifier) ?? l.identifier)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    /// Quick-switch shortlist for the menu bar: current + team languages.
    static func favorites(current: String) -> [String] {
        var ids = [normalize(current), "en-AU", "en-US", "vi-VN"]
        var seen = Set<String>()
        ids = ids.filter { seen.insert($0).inserted }
        return ids.filter { id in all.contains { $0.id == id } }
    }

    /// Stored settings may use underscore form (en_AU); recognizer locales use
    /// hyphens (en-AU).
    static func normalize(_ id: String) -> String {
        let hyphenated = id.replacingOccurrences(of: "_", with: "-")
        if all.contains(where: { $0.id == hyphenated }) { return hyphenated }
        return id
    }

    static func displayName(_ id: String) -> String {
        all.first { $0.id == normalize(id) }?.name ?? id
    }
}
