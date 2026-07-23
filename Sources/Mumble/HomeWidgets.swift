import SwiftUI

/// Time saved — the dashboard's signature stat. One track represents how long
/// these words would take to *type*; the navy segment is what *speaking* cost,
/// and the remaining pink segment is the time saved. One element, three reads.
struct TimeSavedCard: View {
    @ObservedObject var state = AppState.shared

    private func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }

    private var savedHeadline: String {
        let saved = state.timeSaved.savedMin
        if saved < 60 { return "\(Int(saved.rounded())) min" }
        let hours = saved / 60
        return String(format: "%.1f hrs", hours)
    }

    var body: some View {
        let t = state.timeSaved
        let speakingFraction = t.typingMin > 0 ? t.speakingMin / t.typingMin : 0

        VStack(alignment: .leading, spacing: 14) {
            Text("TIME SAVED")
                .font(.system(size: 11, weight: .semibold)).kerning(0.5)
                .foregroundStyle(Theme.pink)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(savedHeadline)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.navy)
                Text("vs typing")
                    .font(.system(size: 13)).foregroundStyle(Theme.grey)
            }

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // Full track = time it would take to type these words.
                    RoundedRectangle(cornerRadius: 6).fill(Theme.pinkTint)
                    // Speaking cost.
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.navy)
                        .frame(width: max(6, w * speakingFraction))
                    // Saved marker at the boundary.
                    if speakingFraction < 0.96 {
                        Text("saved")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.pinkTintText)
                            .padding(.leading, min(w - 44, w * speakingFraction + 8))
                    }
                }
            }
            .frame(height: 26)

            HStack {
                legend(color: Theme.navy, label: "Speaking", value: hm(t.speakingMin))
                Spacer()
                legend(color: Theme.pinkTint, label: "Typing would’ve taken", value: hm(t.typingMin))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }

    private func legend(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.grey)
            Text(value).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink)
        }
    }
}

/// What Mumble learned this week — a feed of corrections it picked up from your
/// edits, each addable to the dictionary. Surfaces the learning loop and turns
/// it into an action.
struct LearnedThisWeekCard: View {
    @ObservedObject var state = AppState.shared

    private var recent: [Correction] { state.correctionsThisWeek }

    private func addToDictionary(_ c: Correction) {
        guard !state.dictionary.contains(where: {
            $0.word.lowercased() == c.corrected.lowercased()
                && $0.replaces.lowercased() == c.original.lowercased()
        }) else { return }
        state.dictionary.append(DictionaryWord(word: c.corrected, replaces: c.original))
    }

    private func isInDictionary(_ c: Correction) -> Bool {
        state.dictionary.contains {
            $0.word.lowercased() == c.corrected.lowercased()
                && $0.replaces.lowercased() == c.original.lowercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Learned this week").font(Theme.heading(20)).foregroundStyle(Theme.ink)
                Spacer()
                if !recent.isEmpty {
                    Text("\(recent.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.pinkTintText)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.pinkTint))
                }
            }

            if recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(Theme.pink)
                    Text("Nothing new this week.")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    Text("Edit a dictation after it lands and Mumble picks up your correction.")
                        .font(.system(size: 12)).foregroundStyle(Theme.grey)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(recent.prefix(5)) { c in
                    HStack(spacing: 8) {
                        Text(c.original)
                            .font(.system(size: 13)).strikethrough()
                            .foregroundStyle(Theme.grey).lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.pink)
                        Text(c.corrected)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.navy).lineLimit(1)
                        Spacer(minLength: 8)
                        if isInDictionary(c) {
                            Label("Saved", systemImage: "checkmark")
                                .font(.system(size: 11)).foregroundStyle(Theme.grey)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Button { addToDictionary(c) } label: {
                                Text("Add to dictionary").font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.navy)
                        }
                    }
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                }
                if recent.count > 5 {
                    Text("and \(recent.count - 5) more")
                        .font(.system(size: 11)).foregroundStyle(Theme.grey)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }
}
