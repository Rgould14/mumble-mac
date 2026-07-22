import AppKit
import ApplicationServices

/// Learns from what the user changes after a dictation lands.
///
/// After inserting text we hold a reference to the target Accessibility
/// element, re-read its value ~20s and ~45s later, and word-diff the inserted
/// text against what's there now. Replacement spans ("sked yellow" -> "Skedulo")
/// are recorded as corrections; repeated corrections are auto-applied on future
/// dictations and all recent ones steer the AI cleanup prompt.
final class EditWatcher {
    static let shared = EditWatcher()
    private var generation = 0

    /// Call right after pasting `inserted` into the focused field.
    func watch(inserted: String, appName: String) {
        guard AppState.shared.settings.enableLearning else { return }
        let words = inserted.split(separator: " ").count
        guard words >= 3 else { return }   // too short to learn anything reliable
        guard let element = Self.focusedElement() else { return }

        generation += 1
        let gen = generation
        var learned = false
        for delay in [20.0, 45.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == gen, !learned else { return }
                guard let current = Self.value(of: element) else { return }
                if self.learn(inserted: inserted, current: current, appName: appName) {
                    learned = true
                }
            }
        }
    }

    /// Diff inserted vs the field's current content; record replacement spans.
    /// Returns true if anything was learned (or the text was verified unchanged).
    private func learn(inserted: String, current: String, appName: String) -> Bool {
        let a = tokenize(inserted)
        let b = tokenize(current)
        guard !a.isEmpty, !b.isEmpty else { return false }

        // Only compare when the field still mostly contains our dictation —
        // if it was sent/cleared or buried in other content, learn nothing.
        let sim = similarity(a, b)
        guard sim >= 0.35 else { return false }
        if inserted == current { return true }   // verified unchanged; stop watching

        var learnedSomething = false
        for (from, to) in replacements(from: a, to: b)
        where from.count <= 6 && to.count <= 6 {
            AppState.shared.recordCorrection(original: from.joined(separator: " "),
                                             corrected: to.joined(separator: " "),
                                             appName: appName)
            learnedSomething = true
        }
        return learnedSomething || sim > 0.9
    }

    // MARK: - Word diff (LCS)

    private func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    private func similarity(_ a: [String], _ b: [String]) -> Double {
        let lcs = lcsLength(a, b)
        return Double(2 * lcs) / Double(a.count + b.count)
    }

    private func lcsLength(_ a: [String], _ b: [String]) -> Int {
        guard a.count * b.count <= 200_000 else { return 0 }   // bound the work
        var dp = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            var prev = 0
            for j in 1...b.count {
                let tmp = dp[j]
                dp[j] = a[i-1].lowercased() == b[j-1].lowercased() ? prev + 1 : max(dp[j], dp[j-1])
                prev = tmp
            }
        }
        return dp[b.count]
    }

    /// Word-level replacement spans (delete-run paired with insert-run).
    private func replacements(from a: [String], to b: [String]) -> [([String], [String])] {
        guard a.count * b.count <= 200_000 else { return [] }
        // Full LCS table for backtracking.
        var dp = Array(repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                dp[i][j] = a[i-1].lowercased() == b[j-1].lowercased()
                    ? dp[i-1][j-1] + 1
                    : max(dp[i-1][j], dp[i][j-1])
            }
        }
        var i = a.count, j = b.count
        var pairs: [([String], [String])] = []
        var delRun: [String] = [], insRun: [String] = []
        func flush() {
            // Only true replacements teach us anything; pure insertions are the
            // user writing more, pure deletions are trimming — skip both.
            if !delRun.isEmpty && !insRun.isEmpty {
                pairs.append((delRun.reversed(), insRun.reversed()))
            }
            delRun = []; insRun = []
        }
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i-1].lowercased() == b[j-1].lowercased() {
                flush(); i -= 1; j -= 1
            } else if j > 0, i == 0 || dp[i][j-1] >= dp[i-1][j] {
                insRun.append(b[j-1]); j -= 1
            } else {
                delRun.append(a[i-1]); i -= 1
            }
        }
        flush()
        return pairs.reversed()
    }

    // MARK: - Accessibility

    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(ref as AnyObject, to: AXUIElement.self)
    }

    static func value(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString,
                                            &ref) == .success else { return nil }
        return ref as? String
    }
}

/// Deterministic application of well-established corrections (seen 2+ times).
enum LearnedCorrections {
    static func apply(_ text: String, state: AppState) -> String {
        guard state.settings.enableLearning else { return text }
        var out = text
        for c in state.corrections where c.count >= 2 {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: c.original) + "\\b"
            out = out.replacingOccurrences(of: pattern, with: c.corrected,
                                           options: .regularExpression)
        }
        return out
    }

    /// Prompt lines describing recent corrections, for the AI cleanup pass.
    static func promptLines(state: AppState, limit: Int = 12) -> [String] {
        guard state.settings.enableLearning, !state.corrections.isEmpty else { return [] }
        let top = state.corrections
            .sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }
            .prefix(limit)
        return top.map { "\"\($0.original)\" → \"\($0.corrected)\"" }
    }
}
