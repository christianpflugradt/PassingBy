# Hannes checks

Seven enabled checks run in ID order on macOS:

| Check | Command | Scope |
| --- | --- | --- |
| `01-compile` | `mise run compile` | Release application compilation |
| `02-domain` | `mise run test-domain` | Filtering, retention and domain rules |
| `03-persistence` | `mise run test-persistence` | Saves, failed writes, migration and legacy fixtures |
| `04-editor` | `mise run test-editor` | Markdown and smart substitutions |
| `05-native-ui` | `mise run test-ui` | Settings focus, navigation, selection and Undo/Redo |
| `06-app-bundle` | `mise run build` | Bundle assembly, metadata, icon and signature verification |
| `07-style` | `mise run lint` | Swift formatting and style |

Hannes executes the underlying commands directly; Mise offers equivalent shortcuts.
Swift 6+, Apple Command Line Tools and a macOS desktop session are required.
Native tests create test windows; they are not a full application or VoiceOver test.
Tests use temporary workspace files, including two synthetic workspaces encoded
with the initial historical models. They do not use your saved application data.
Build outputs stay in ignored `.build/` and `build/` directories. Incremental builds
reuse compiler outputs; they do not clean the checkout or install the app.

```sh
hannes pass auf
hannes mach was
hannes was ist phase
hannes was ist phase --details
```

Each check gets live progress and its own PASS/FAIL/ERROR result. Captured output
is available in the ignored local `reports/last.json` and the saved details view.
`swift run PassingByTests` runs all suites; `--suite domain|persistence|editor`
selects one, and `--list` lists every registered test. Unknown suites fail.
The style check never rewrites files; `mise run format` performs explicit formatting.

All three reviews are disabled. `provider.toml` retains your local Codex login,
GPT-6.1 Sol (`model = "gpt-6.1-sol"`), no MCP servers (`mcp_servers = []`),
medium reasoning and a 300-second timeout for a future opt-in review. Enabling a review
makes `mach was` call Codex after all checks pass and consumes account allowance.
No credentials are stored here and there are no automatic repairs.

The disabled accessibility review declares five Settings source/test entry files
and exact Product.md requirement headings. Hannes sends those shared excerpts once
with original line numbers, filters initial diff/path hints to that focus, and asks
Codex to follow dependencies using targeted reads. This does not enable the review.
Model/MCP settings live in `provider.toml`; server names must already be configured
in Codex CLI before adding them to its explicit allow list.
