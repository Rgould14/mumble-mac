import SwiftUI
import AppKit

enum HubSection: String, CaseIterable, Identifiable {
    case home = "Home", insights = "Insights", history = "History", dictionary = "Dictionary",
         snippets = "Snippets", learning = "Learning", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "house"
        case .insights: "chart.bar"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .learning: "brain"
        case .settings: "gearshape"
        }
    }
}

struct HubView: View {
    @State private var section: HubSection = .home
    @ObservedObject var state = AppState.shared

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                if let lockup = Theme.logoHorizontal {
                    Image(nsImage: lockup)
                        .resizable().scaledToFit()
                        .frame(height: 30)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                }
                List(HubSection.allCases, selection: $section) { s in
                    Label(s.rawValue, systemImage: s.icon).tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 195)
        } detail: {
            switch section {
            case .home: HomeView()
            case .insights: InsightsView()
            case .history: HistoryView()
            case .dictionary: DictionaryView()
            case .snippets: SnippetsView()
            case .learning: LearningView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .tint(Theme.navy)
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    if let logo = Theme.logoMark {
                        Image(nsImage: logo)
                            .resizable().scaledToFit()
                            .frame(width: 44, height: 44)
                    }
                    Text("Welcome to Mumble")
                        .font(Theme.display(28))
                        .foregroundStyle(Theme.ink)
                }
                Text("Hold **fn** and speak into any app. Release to insert polished text. Double-tap **fn** or press **fn + Space** for hands-free. **Esc** cancels.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    StatCard(title: "Words dictated", value: "\(state.totalWords)")
                    StatCard(title: "Average WPM", value: "\(state.averageWPM)")
                    StatCard(title: "Day streak", value: "\(state.streakDays)")
                }

                Text("Recent activity").font(Theme.heading(20)).foregroundStyle(Theme.ink)
                if state.history.isEmpty {
                    Text("No dictations yet — hold fn and say something!")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.history.prefix(5)) { entry in
                        TranscriptRow(entry: entry)
                    }
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatCard: View {
    let title: String, value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(Theme.statNumber(30))   // Goodly Light — oversized stat numbers
                .foregroundStyle(Theme.ink)
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.grey)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
    }
}

struct TranscriptRow: View {
    let entry: TranscriptEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text).lineLimit(3)
            HStack {
                Text(entry.appName).font(.caption).foregroundStyle(.secondary)
                Text(entry.date, style: .relative).font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
    }
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject var state = AppState.shared
    @State private var search = ""

    var filtered: [TranscriptEntry] {
        search.isEmpty ? state.history
            : state.history.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading) {
            if state.history.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Your dictations will appear here."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { TranscriptRow(entry: $0) }
                    }
                    .padding(16)
                }
            }
        }
        .searchable(text: $search, prompt: "Search transcripts")
        .toolbar {
            Button(role: .destructive) { state.history = [] } label: {
                Label("Clear all", systemImage: "trash")
            }
        }
        .navigationTitle("History")
    }
}

// MARK: - Dictionary

struct DictionaryView: View {
    @ObservedObject var state = AppState.shared
    @State private var newWord = ""
    @State private var newReplaces = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teach Flow your names and jargon. Optionally map a commonly misheard phrase to the correct word.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Word (e.g. Skedulo)", text: $newWord)
                TextField("Replaces (optional, e.g. sked yellow)", text: $newReplaces)
                Button("Add") {
                    guard !newWord.isEmpty else { return }
                    state.dictionary.append(DictionaryWord(word: newWord, replaces: newReplaces))
                    newWord = ""; newReplaces = ""
                }
                .keyboardShortcut(.defaultAction)
            }
            List {
                ForEach(state.dictionary) { w in
                    HStack {
                        Text(w.word).bold()
                        if !w.replaces.isEmpty {
                            Text("← \(w.replaces)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { state.dictionary.removeAll { $0.id == w.id } } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(20)
        .navigationTitle("Dictionary")
    }
}

// MARK: - Snippets

struct SnippetsView: View {
    @ObservedObject var state = AppState.shared
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Say a trigger phrase on its own and Flow inserts the full snippet — great for meeting links and canned replies.")
                .foregroundStyle(.secondary)
            HStack(alignment: .top) {
                VStack {
                    TextField("Trigger phrase (e.g. insert meeting link)", text: $trigger)
                    TextField("Expansion text", text: $expansion, axis: .vertical).lineLimit(2...4)
                }
                Button("Add") {
                    guard !trigger.isEmpty, !expansion.isEmpty else { return }
                    state.snippets.append(Snippet(trigger: trigger, expansion: expansion))
                    trigger = ""; expansion = ""
                }
            }
            List {
                ForEach(state.snippets) { s in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text("“\(s.trigger)”").bold()
                            Text(s.expansion).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button { state.snippets.removeAll { $0.id == s.id } } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(20)
        .navigationTitle("Snippets")
    }
}

// MARK: - Learning

struct LearningView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Learn from my edits", isOn: $state.settings.enableLearning)
            Text("After a dictation lands, Mumble watches what you change in the text field and remembers your corrections. Ones seen twice are applied automatically; all recent ones guide the AI cleanup.")
                .font(.caption).foregroundStyle(.secondary)

            if state.corrections.isEmpty {
                ContentUnavailableView("Nothing learned yet", systemImage: "brain",
                                       description: Text("Dictate, then edit the result — your corrections will appear here."))
            } else {
                List {
                    ForEach(state.corrections.sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }) { c in
                        HStack {
                            Text(c.original).strikethrough().foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                            Text(c.corrected).bold()
                            Spacer()
                            if c.count >= 2 {
                                Text("auto ×\(c.count)")
                                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(.green.opacity(0.2)))
                            } else {
                                Text("×\(c.count)").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Button { state.corrections.removeAll { $0.id == c.id } } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .padding(20)
        .toolbar {
            Button(role: .destructive) { state.corrections = [] } label: {
                Label("Forget all", systemImage: "trash")
            }
        }
        .navigationTitle("Learning")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        Form {
            Section("Activation") {
                Toggle("Use fn key (Apple keyboards)", isOn: $state.settings.useFnKey)
                Picker("Gesture", selection: $state.settings.gesture) {
                    ForEach(ActivationGesture.allCases, id: \.self) { Text($0.rawValue) }
                }
                LabeledContent("Hands-free", value: "fn + Space, or double-tap fn")
                LabeledContent("Paste last transcript", value: "⌘⌃V")
                LabeledContent("Cancel", value: "Esc")
                Text("Tip: set System Settings → Keyboard → “Press 🌐 key to” = Do Nothing so fn is free for Mumble.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Transcription") {
                TextField("Locale (e.g. en_US)", text: $state.settings.localeIdentifier)
                Toggle("On-device recognition only", isOn: $state.settings.onDeviceOnly)
                Toggle("Always use built-in microphone", isOn: $state.settings.preferBuiltInMic)
                Text("Recommended with Bluetooth headphones: their mic is unreliable on macOS and drops music to call quality while recording.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Max session: \(state.settings.maxSessionMinutes) min",
                        value: $state.settings.maxSessionMinutes, in: 1...60)
            }
            Section("AI cleanup") {
                Toggle("Use AI to clean up transcripts", isOn: $state.settings.useAICleanup)
                Text("Rewrites raw speech-to-text to fix mis-transcribed words, punctuation, and tone — the way Wispr Flow does. Falls back to rule-based polishing when off or offline.")
                    .font(.caption).foregroundStyle(.secondary)
                if state.settings.useAICleanup {
                    SecureField("Anthropic API key (or set ANTHROPIC_API_KEY)",
                                text: $state.settings.anthropicAPIKey)
                    Picker("Model", selection: $state.settings.cleanupModel) {
                        Text("Claude Opus 4.8 (most accurate)").tag("claude-opus-4-8")
                        Text("Claude Haiku 4.5 (fastest)").tag("claude-haiku-4-5")
                        Text("Claude Sonnet 5 (balanced)").tag("claude-sonnet-5")
                    }
                    Toggle("Adapt tone to the active app", isOn: $state.settings.adaptToneByApp)
                }
            }
            Section("Polish (fallback / on top of AI)") {
                Toggle("Remove filler words (um, uh…)", isOn: $state.settings.removeFillerWords)
                Toggle("Auto-capitalize first word", isOn: $state.settings.autoCapitalize)
            }
            Section("Feedback") {
                Toggle("Play sounds", isOn: $state.settings.playSounds)
            }
            Section("Permissions") {
                PermissionsStatusView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
