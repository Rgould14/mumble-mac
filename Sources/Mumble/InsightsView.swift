import SwiftUI

/// Insights tab: usage stats in the Mumble design system — Goodly Light for
/// the oversized numbers, navy for data, Surface cards, pink nowhere (it's
/// reserved for the live state).
struct InsightsContent: View {
    @ObservedObject var state = AppState.shared

    private var totalFixes: Int {
        state.settings.totalFixesApplied + state.corrections.reduce(0) { $0 + $1.count }
    }

    /// Word share per target app, descending.
    private var appUsage: [(name: String, words: Int, share: Double)] {
        var byApp: [String: Int] = [:]
        for e in state.history { byApp[e.appName, default: 0] += e.wordCount }
        let total = max(1, byApp.values.reduce(0, +))
        return byApp.sorted { $0.value > $1.value }
            .prefix(6)
            .map { ($0.key, $0.value, Double($0.value) / Double(total)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                InsightCard(number: state.totalWords.formatted(), label: "Words dictated")
                InsightCard(number: "\(state.averageWPM)", label: "Average WPM")
                InsightCard(number: "\(state.streakDays)", label: "Day streak")
                InsightCard(number: "\(totalFixes)", label: "Fixes made")
            }

            HStack(alignment: .top, spacing: 16) {
                usageCard
                streakCard
            }
        }
    }

    // MARK: Usage by app

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("App usage").font(Theme.heading(20)).foregroundStyle(Theme.ink)
                Spacer()
                Text("APPS | \(Set(state.history.map(\.appName)).count)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.pink)
            }
            if appUsage.isEmpty {
                Text("Dictate to see where your words go.")
                    .font(.system(size: 13)).foregroundStyle(Theme.grey)
            }
            ForEach(appUsage, id: \.name) { app in
                HStack(spacing: 10) {
                    Text(app.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 110, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5).fill(Theme.navyWash)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Theme.navy)
                                .frame(width: max(24, geo.size.width * app.share))
                            Text("\(Int((app.share * 100).rounded()))%")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.leading, 7)
                        }
                    }
                    .frame(height: 20)
                    Text("\(app.words.formatted()) words")
                        .font(.system(size: 11)).foregroundStyle(Theme.grey)
                        .frame(width: 84, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }

    // MARK: Streak heatmap

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(state.streakDays) day streak")
                    .font(Theme.heading(20)).foregroundStyle(Theme.ink)
                Spacer()
                Text("LONGEST | \(state.longestStreak) DAYS")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.pink)
            }
            StreakHeatmap(wordsByDay: state.wordsByDay)
            HStack(spacing: 5) {
                Text("More").font(.system(size: 11)).foregroundStyle(Theme.grey)
                ForEach([3, 2, 1, 0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(StreakHeatmap.color(level: level))
                        .frame(width: 12, height: 12)
                }
                Text("Less").font(.system(size: 11)).foregroundStyle(Theme.grey)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }
}

struct InsightCard: View {
    let number: String, label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(number).font(Theme.statNumber(30)).foregroundStyle(Theme.figure)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Theme.pink)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
    }
}

/// GitHub-style calendar: last 18 weeks, one column per week, navy intensity
/// ramp by words dictated that day.
struct StreakHeatmap: View {
    let wordsByDay: [Date: Int]
    private let weeks = 18

    static func color(level: Int) -> Color {
        switch level {
        case 3: Theme.navy
        case 2: Color(red: 0x4A/255, green: 0x6D/255, blue: 0xA8/255)
        case 1: Color(red: 0xC4/255, green: 0xD3/255, blue: 0xEA/255)
        default: Theme.navyWash.opacity(0.5)
        }
    }

    private func level(for words: Int) -> Int {
        switch words {
        case 0: 0
        case ..<150: 1
        case ..<600: 2
        default: 3
        }
    }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Align columns to weeks ending today.
        let weekday = cal.component(.weekday, from: today)   // 1 = Sunday
        HStack(alignment: .top, spacing: 3) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { d in
                        let offset = -( (weeks - 1 - w) * 7 + (weekday - 1 - d) )
                        let day = cal.date(byAdding: .day, value: offset, to: today)!
                        let inFuture = day > today
                        RoundedRectangle(cornerRadius: 3)
                            .fill(inFuture ? Color.clear
                                           : Self.color(level: level(for: wordsByDay[day] ?? 0)))
                            .overlay(
                                day == today
                                    ? RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.pink, lineWidth: 1.5)
                                    : nil
                            )
                            .frame(width: 13, height: 13)
                    }
                }
            }
        }
    }
}
