# Agent Instructions

## Product specification

- `Product.md` is the authoritative product specification. Read it before product, UX, domain or scope decisions; link to it instead of keeping competing definitions elsewhere. Explicit non-goals are deliberate.
- Follow its sections 33–34 for interpretation and reviewer decisions. For unspecified minor details, preserve established behaviour and choose the simplest consistent solution. For missing, conflicting or evolving requirements that materially affect behaviour, data safety or scope, inspect tests and relevant Git history, report the uncertainty and leave the product decision to the user. Neither the implementation nor passing tests override the specification.
- Do not modify `Product.md` merely to make the implementation conform. If the specification should change, report the issue and trade-off and propose the smallest concrete change. An explicitly requested feature or documentation review authorizes updating the affected specification: record well-supported decisions in the relevant sections, keep unresolved material questions for review and do not turn incidental implementation details into constraints.
- For substantial product work, review the result against the relevant `Product.md` verification criteria and report remaining deviations.

## Engineering

- Use native macOS conventions and platform capabilities where practical. A small amount of duplication beats premature abstraction.
- Prioritise tests for domain rules, state transitions, persistence, filtering, retention and data invariants. Use UI tests only for important user-visible behaviour that lower-level tests cannot cover.
- Do not create planning documents, ADRs, progress logs or other process artifacts unless the task requires them. Keep README focused on building, running and testing.

## Persistence and data safety

- User-created content must not be silently lost. Changes to persistence, deletion, retention or migrations need particular care and tests. Never change or discard persisted data merely because it simplifies the implementation.

## UI state

- Do not rebuild major view hierarchies for routine interactions such as selection, filtering, editing or toggling; prefer stable native hierarchies with incremental updates.
- Preserve screen and editor state when switching screens or Notes (`Product.md` sections 12.3 and 25). Keep Undo/Redo history in memory across navigation and never persist it across restarts; persist other restorable UI state, including caret positions. Intentional transitions such as creation, deletion, filtering out an item or closing a dialog may move focus as specified; pick an appropriate surviving control when the original target is unavailable.
