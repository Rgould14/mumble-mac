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

## Home dashboard — additional widgets (planned, not started)

Goal: differentiate the Home screen from Wispr Flow by surfacing what's uniquely
Mumble (learning loop, bilingual use, Prompt Mode, content) below the existing
stat cards + app-usage + streak. All buildable from existing local data
(`history.json`, `corrections.json`, `settings.json`) — no new tracking.

Prereq for language/prompt widgets: `TranscriptEntry` currently stores
{text, appName, date, durationSeconds}. Add optional `locale` and `wasPrompt`
fields (tolerant-decode, default nil/false) so new entries carry them; old
entries degrade gracefully.

### Tier 1 — SHIPPED: (1) Learned this week + (3) Time saved. (2) Language split dropped (small use case).

1. **What Mumble learned this week** *(top pick)*
   - Source: `corrections` filtered to lastSeen within 7 days, newest first.
   - Layout: Surface card, list of `original → corrected` rows with count; each
     row an "Add to dictionary" button (writes a DictionaryWord).
   - Why: exposes the learning flywheel Wispr hides; turns passive data into action.
   - Effort: low. No model changes.

2. **Language split**
   - Source: sum wordCount by `entry.locale` (needs the new field; until then,
     everything reads as the primary language).
   - Layout: single horizontal split bar (EN vs VI…) + legend, in the navy ramp.
   - Why: foregrounds the bilingual use case that's the team's reason for
     multilingual support.
   - Effort: low once `locale` is stored.

3. **Time saved**
   - Source: totalWords. Estimate = words/40wpm (typing) − words/150wpm (speaking),
     shown as "≈ X hours saved vs typing".
   - Layout: one stat tile or a slim banner; pink accent on the number.
   - Why: concrete, satisfying, motivational; Wispr doesn't frame it this way.
   - Effort: trivial (pure calc).

### Tier 2 — also strong

4. **Suggested dictionary entries**
   - Source: corrections with count ≥ 2 whose `original` isn't already a
     dictionary `replaces`. Offer as add buttons.
   - Effort: low. Complements widget 1.

5. **Prompt Mode panel**
   - Source: entries where `wasPrompt == true` (needs the new field).
   - Show: prompts engineered vs plain dictations, top target apps.
   - Effort: low once `wasPrompt` is stored.

### Tier 3 — nice-to-have

6. **When you dictate** — by-hour bar (bucket `entry.date` hour) or 14-day
   words/day sparkline. Effort: low-medium.
7. **Top vocabulary** — most-frequent distinctive words across history (stopword
   filter). Could feed widget 4. Effort: medium.
8. **Milestones/badges** — longest dictation, biggest day, 10k-word tiers.
   Effort: low.

### Open questions
- Home is getting long — do these stack below recent activity, or does Home
  split into "Overview" + a richer "Insights" page again?
- Privacy: "top vocabulary" surfaces transcript content on the dashboard — fine
  for a personal tool, worth a toggle if screens get shared.
