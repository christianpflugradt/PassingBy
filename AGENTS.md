# Agent Instructions

## Sources of Truth

- `Product.md` is the authoritative product specification.
- Read `Product.md` before making product, UX, domain, or scope decisions.
- Keep product requirements in `Product.md`; link to them rather than maintaining competing definitions elsewhere.
- Explicit non-goals in `Product.md` are deliberate constraints, not missing features.

Use the interpretation and reviewer decision rules in `Product.md` sections 33–34. For unspecified minor details, preserve established behaviour and choose the simplest consistent solution. For missing, conflicting, or evolving requirements that materially affect behaviour, data safety, or scope, inspect tests and relevant Git history, report the uncertainty, and leave the product decision to the user. Neither the implementation nor passing tests automatically overrides the specification.

## Engineering Principles

Keep the implementation simple, native, and maintainable.

- Prefer straightforward solutions over speculative abstractions.
- Do not design for hypothetical future requirements.
- Avoid unnecessary frameworks, generic infrastructure, plugin systems, or abstraction layers.
- A small amount of duplication is preferable to premature abstraction.
- Follow established project patterns once they exist.
- Use native macOS conventions and platform capabilities where practical.
- Do not add dependencies without a clear benefit.

Functional correctness alone is insufficient. Implementation and UX decisions must also respect the product principles defined in `Product.md`.

## Scope Discipline

Implement only what is required by `Product.md` and the current task.

Do not add adjacent features merely because they are common in similar applications.

Do not perform unrelated refactoring while completing a task unless it is necessary for correctness or materially reduces implementation risk.

## Working Method

Before changing code:

1. inspect the relevant existing implementation,
2. read the applicable sections of `Product.md`,
3. understand existing tests and conventions.

Then make the smallest coherent change that fully satisfies the task.

Work incrementally and keep the project in a valid state.

After changes:

1. build the application,
2. run relevant automated tests,
3. fix regressions,
4. verify the result against the applicable requirements in `Product.md`.

Fix violations and regressions introduced by the task before declaring it complete. Report unrelated pre-existing discrepancies or failing checks separately; do not silently expand the task to repair them. For documentation-only work, verify claims against source, tests, and history, and check links and cross-references; do not change application code or tests unless requested.

## Testing

Add automated tests where they provide meaningful protection against regressions.

Prioritise:

- domain rules,
- state transitions,
- persistence behaviour,
- filtering,
- retention behaviour,
- data invariants.

Do not create low-value tests merely to increase coverage.

Use UI tests when they protect important user-visible behaviour that cannot be tested effectively at a lower level.

## Persistence and Data Safety

User-created content must not be silently lost.

Changes that affect persistence, deletion, retention, or migrations require particular care and appropriate tests.

Never change or discard existing persisted data merely because doing so simplifies implementation.

## Product Specification Changes

Do not modify `Product.md` merely to make the current implementation conform.

If implementation work reveals that the specification should change:

1. report the issue,
2. explain the trade-off,
3. propose the smallest concrete specification change,
4. leave the product decision to the user unless explicitly instructed otherwise.

An explicitly requested feature or documentation review can authorize updating the affected specification. Record well-supported product decisions in the existing relevant sections, update corresponding verification criteria where useful, and preserve unresolved material questions for human review. Do not turn incidental implementation details into new product constraints.

## UI State and Native Interaction

Do not rebuild major view hierarchies for routine interactions such as selection, filtering, editing, or toggling state.

During incremental updates, preserve selection, focus, scroll position, native Undo/Redo context, and in-progress edits where their target remains available. Intentional transitions such as creation, deletion, filtering out an item, or closing a dialog may move focus as specified in `Product.md`; choose an appropriate surviving control and preserve saved content.

Prefer stable native view hierarchies with incremental state updates over reconstructing controls after each interaction.

## Documentation

Keep documentation concise and useful.

Do not create planning documents, architecture documents, ADRs, progress logs, or other process artifacts unless the task requires them or they provide clear lasting value.

Keep `README.md` focused on practical repository usage such as building, running, and testing the application.

## Git Workflow

- Never use `git stash` in any form.
- Work only on `main`. Do not create, check out, or commit on another branch.
- Commit completed work on `main` and push `main` to `origin`.

## Completion

Before considering a task complete:

- the project builds,
- relevant tests pass,
- the requested behaviour works,
- applicable `Product.md` requirements are satisfied, with unrelated pre-existing deviations reported,
- no unrelated product behaviour has been introduced.

For substantial product work, perform a final review against the relevant `Product.md` verification criteria and report any remaining deviations explicitly.

After completing a task, commit its changes using the repository's commit-message convention and push `main` to `origin`. Report the commit and push result; if the push fails, report the failure without discarding the commit.
