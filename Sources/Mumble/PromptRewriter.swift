import Foundation

/// Where a Prompt Mode dictation is headed — decides the rewrite style.
enum PromptTarget: String, CaseIterable, Identifiable {
    case claudeCode = "Coding agent (Claude Code)"
    case inlineIDE = "IDE assistant (Cursor/Copilot)"
    case chatAssistant = "Chat assistant (Claude/ChatGPT)"
    case general = "General LLM prompt"
    var id: String { rawValue }

    /// Infer the target from the app the user is dictating into.
    static func infer(appName: String, fallback: PromptTarget) -> PromptTarget {
        let a = appName.lowercased()
        if ["terminal", "iterm", "warp", "ghostty", "kitty", "alacritty"].contains(where: a.contains) {
            return .claudeCode
        }
        if ["cursor", "windsurf", "visual studio code", "code", "zed", "xcode"].contains(where: a.contains) {
            return .inlineIDE
        }
        if ["claude", "chatgpt", "gemini", "perplexity"].contains(where: a.contains) {
            return .chatAssistant
        }
        if ["safari", "chrome", "arc", "firefox", "edge", "brave", "dia"].contains(where: a.contains) {
            return .chatAssistant
        }
        return fallback
    }
}

/// Rewrites a rambled dictation into an engineered prompt for the chosen
/// target, following Anthropic's prompt-engineering guidance (clarity and
/// specificity, context/motivation, XML structure, explicit output format,
/// verification criteria for agents). Reuses the LLMCleanup transport.
enum PromptRewriter {
    static func rewrite(_ raw: String, target: PromptTarget, state: AppState) async throws -> String {
        guard let key = LLMCleanup.apiKey(from: state.settings) else { throw LLMCleanup.Unavailable() }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.split(separator: " ").count >= 3 else { throw LLMCleanup.Unavailable() }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": state.settings.cleanupModel,
            "max_tokens": 3000,
            "system": systemPrompt(target: target),
            "messages": [["role": "user",
                          "content": "<dictation>\n\(trimmed)\n</dictation>"]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw LLMCleanup.Unavailable()
        }
        let text = content.filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMCleanup.Unavailable() }
        return text
    }

    private static func systemPrompt(target: PromptTarget) -> String {
        let common = """
        You are a prompt engineer inside a dictation tool. The user rambled their \
        intent between <dictation> tags; they are about to paste your output into \
        \(target.rawValue). Rewrite the dictation into the prompt they should send.

        Follow Anthropic's prompt-engineering guidance:
        - Be clear, direct, and specific. State exactly what is wanted, including \
        the desired output format and any constraints the user implied. A reader \
        with no context must be able to follow it (the "new employee" rule).
        - Keep the user's motivation: if they said WHY they want something, keep \
        the why — models generalize better from motivated instructions.
        - Preserve every concrete detail verbatim: file paths, function names, \
        URLs, numbers, error messages, product names. NEVER invent requirements, \
        constraints, or details the user did not say or clearly imply.
        - Cut filler, repetition, thinking-out-loud, and self-corrections (keep \
        only the user's final position when they changed their mind mid-ramble).
        - If the dictation mixes context and request, structure the prompt with \
        XML tags (<context>, <task>, <constraints>, <output_format>) — but for \
        short simple asks, plain prose is better. Do not over-engineer.
        - Write in first person, as the user speaking to the assistant.

        Output ONLY the rewritten prompt — no preamble, no explanation, no \
        markdown fences around the whole thing, no meta-commentary.
        """
        let specific: String
        switch target {
        case .claudeCode:
            specific = """

            Target-specific rules for an autonomous coding agent:
            - Put the FULL task specification up front in one message: goal, \
            constraints, and what "done" looks like.
            - State goals and constraints, not step-by-step instructions — the \
            agent plans better from outcomes than from prescribed steps.
            - Include verification criteria the agent can check itself against \
            ("done when the tests in X pass", "verify by running Y") when the \
            user implied any.
            - Scope guardrails: if the user hinted at limits ("don't refactor", \
            "just a quick fix"), state them explicitly.
            """
        case .inlineIDE:
            specific = """

            Target-specific rules for an inline IDE assistant:
            - Short and imperative. Lead with the action on the current code.
            - Reference code locations the way the user did (file, function, \
            selection) — the assistant sees the editor context.
            - One task per prompt; if the user rambled several, keep the primary \
            one and append the rest as a short follow-ups list.
            """
        case .chatAssistant:
            specific = """

            Target-specific rules for a chat assistant:
            - Separate context from the actual question; question last.
            - Make the desired response format explicit (length, structure, \
            tone) when the user implied one.
            - If the user wants analysis or judgment, ask the assistant to \
            reason through it before answering.
            """
        case .general:
            specific = ""
        }
        return common + specific
    }
}
