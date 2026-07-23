# Mumble backlog

## Prompt Mode (v1 SHIPPED — remaining items below)

**Goal:** a dedicated mode for dictating *prompts* rather than prose. You ramble
your intent; Mumble asks (or infers) which coding agent/tool the prompt is for,
then rewrites the dictation into a prompt engineered for that target — and
inserts that instead of the raw transcript.

### UX sketch

- **Activation**: a distinct shortcut (proposal: hold `fn` + `P`, or a
  "Prompt Mode" toggle in the menu bar / HUD long-press). HUD pill shows a
  distinct label ("Prompt mode") so you know the output will be rewritten.
- **Target picker**: on stop, if the frontmost app identifies the target
  (Claude Code in a terminal, Claude desktop, Cursor, ChatGPT web…), infer it
  and skip the question. Otherwise the HUD swells to a small chooser:
  `Claude Code · Cursor · Claude chat · ChatGPT · Other…` (arrow keys + enter,
  fully keyboard driven). Remember the last choice per app.
- **Output**: the rewritten prompt is inserted exactly like a normal dictation
  (same focus/paste pipeline). Raw transcript still lands in History; the
  rewritten prompt is stored alongside it.

### Rewriting engine

Second Claude call (reusing `LLMCleanup`'s transport) with a prompt-engineering
system prompt parameterized by target:

| Target | Rewrite emphasis |
|---|---|
| Claude Code / coding agents | Full task spec up front; goal + constraints, not step lists; file/repo references made explicit; verification criteria ("done when…") |
| Cursor/Copilot inline | Short, imperative, code-context-relative |
| Chat assistants | Context + question separation, desired output format |

Inputs: raw dictation, target, frontmost app name, (later) recent clipboard or
selected text as context. Learning layer applies here too: edits you make to a
rewritten prompt become corrections scoped to Prompt Mode.

### Open questions

- Does target inference from the frontmost app cover enough cases to skip the
  picker most of the time?
- Should Prompt Mode have its own model setting (fast Haiku rewrite vs Opus)?
- Do we show a diff/preview before inserting, or insert immediately like
  normal dictation (bias: insert immediately — same philosophy as dictation)?

### Shipped in v1
- fn+P toggle (+ menu bar item), PROMPT chip on the recording HUD
- Target inference from frontmost app (terminal→Claude Code, IDE→inline,
  browser/chat→chat assistant) with a Settings fallback picker
- PromptRewriter grounded in Anthropic's prompt-engineering best practices
  (clarity/specificity, kept motivation, XML structure for long prompts,
  verbatim detail preservation, target-specific rules incl. agentic full-spec
  + verification criteria)
- Fallback to normal cleanup when offline/no key

### Remaining (v2)
- HUD keyboard-driven target chooser when inference is ambiguous
- Remember last target per app
- Store raw + rewritten pair in history; Learning integration for prompt edits
- Optional separate (faster) model for rewriting

### Original build order (reference)

1. `PromptMode` state on `DictationController` + activation shortcut + HUD label
2. Target registry (name → rewrite template) with per-app inference + memory
3. `PromptRewriter` (Claude call, templates per target)
4. HUD target chooser (keyboard-first)
5. History entries store raw + rewritten pair; Learning integration
