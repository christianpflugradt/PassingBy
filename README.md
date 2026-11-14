# Passing By

Passing By is a small native macOS workspace for information that matters now: to-dos, appointments, and Markdown notes. It keeps your information on your Mac and is designed to stay calm and low-distraction.

## Features

- A compact dashboard for open to-dos and upcoming appointments.
- To-dos, date-based appointments, and notes you can edit directly in Markdown.
- Optional categories to group and filter your items.
- Optional local Smart Substitutions for content typing, with built-in symbols and custom mappings.
- Recovery of explicitly deleted notes, to-dos, and appointments for 30 days through Settings → Recently Deleted.
- Appointment import from TSV, control over how long completed to-dos and past appointments are kept, and optional App Lock.

## Install

Passing By requires macOS 14 or later.

Download the latest `Passing-By-<version>.zip` from [GitHub Releases](https://github.com/christianpflugradt/PassingBy/releases), extract it, and move `Passing By.app` to `/Applications`.

The app is ad hoc signed and is not notarized, so macOS may block it from opening. If you trust the copy downloaded from this repository, run this command in Terminal after moving it to `/Applications`:

```bash
xattr -dr com.apple.quarantine "/Applications/Passing By.app"
```

To update, quit Passing By, replace the app in `/Applications` with the newer release, and repeat the command if macOS blocks the new copy.

## Data and privacy

Your workspace is saved automatically at `~/Library/Application Support/Passing By/workspace.json`. On each subsequent save, the last readable version is copied to `workspace.json.backup`. Existing data in the former `Passing by` directory is migrated on first launch.

Optional App Lock uses native macOS authentication to protect access to the application UI. It does **not** encrypt the workspace file.

Smart Substitutions default off. Enable them in Settings and open Manage Substitutions… to configure Automatic rules or add custom mappings. Type `|sqrt|` for √; Automatic rules convert whole inputs after Space, Tab or Return. Escape a literal sequence as `\|sqrt|` (the backslash stays), or Undo once to restore the typed sequence. Code fences and inline code are protected. See [Product.md section 21.8](Product.md#218-smart-substitutions) for the catalog, delimiter escaping, and exact matching rules.

## Development

You need Apple Command Line Tools with Swift 6 or later (`xcode-select --install`) and [Mise](https://mise.jdx.dev/) for the commands below. No separate Node.js runtime is required to build or run the app. See [Product.md](Product.md) for the product specification.

From the repository root:

```sh
mise install
mise run build
mise run test-ui # Native Settings focus and substitution editing tests; requires a macOS desktop session.
```

`mise run build` creates `build/Passing By.app`. Open that bundle from Finder to run it. The build is ad hoc signed. Local builds have a separate development app identity and display “Development build” in About.

### Please Behave

Use the published governor pinned in [mise.toml](mise.toml). Prepare
the tools with `mise install` and locked Node release dependencies with
`mise setup`, then run `mise exec -- please sync --yes`.
Use `mise verify` for a quick fail-fast check, `mise exec -- please run --at pre-push` for the complete gate and
`mise exec -- git commit` / `mise exec -- git push` to give hooks the same tool PATH.
Plain commands need mise shell activation; installation alone does not activate tools. See [.please/README.md](.please/README.md)
for setup, execution points and the release contract.

Pre-commit checks Swift, Python and shell formatting. Pre-push runs all unit tests, the verified app
build, native UI tests, workflow validation and offline release-tooling tests,
plus shared security/license checks. CI runs the same gate without native UI tests
and adds the npm audit. `please status --details` shows saved results.

Commit subjects use Conventional Commits with optional scopes from
[.please/commit-scopes.txt](.please/commit-scopes.txt). Types and syntax are checked
by the shared external Rule Set. Its advisory Gemini Flash-Lite Review evaluates
only the header for specific English imperative wording. Export GEMINI_API_KEY
for the hook; review failures or unavailable credentials remain visible without
blocking commits. CI does not validate commit ranges or PR titles.

Examples: `build: assemble local app`, `fix(ui): correct sidebar alignment`,
`docs: clarify setup`.

`mise run format` applies the four-space, 140-column Swift style, together with `ruff` and `shfmt` for Python and
shell scripts; the hooks only check it. Use the same Swift toolchain locally and in CI for consistent formatter results.
`mise run build` assembles and verifies the signed development app bundle.
The standalone verifier is `./tools/check-app-bundle.sh [path-to-app]`;
release bundles require the matching `RELEASE_VERSION`.

### Releases

Run `mise run release` to dispatch Release on main. Plan calculates the version;
Readiness checks exact-commit CI proof, source security and current advisories;
Candidate builds and verifies the versioned app, reusing source tests from CI. Publish verifies and publishes that
same ZIP without rebuilding. See the [release contract](.please/README.md#release-contract)
for version semantics and reruns. Passing By remains a native macOS app with one
release artifact; native UI tests run only locally at pre-push.

CI and release use mise for portable tools, with Python pinned exactly in
`mise.toml`. Apple SDKs and Swift remain host prerequisites. Preparation only
fetches npm dependencies. Native build validation remains in Please Behave;
Actions owns packaging, artifact verification and publication. Plan and Publish
never install governance or Git hooks. Release dispatch uses an authenticated
host `gh` CLI.

For local packaging, run `RELEASE_VERSION=1.2.3 mise run build` followed by
`RELEASE_VERSION=1.2.3 mise run package`. The ZIP remains in `build/`; `dist/`
contains the ZIP, SHA256SUMS and source-bound metadata for release verification.

## License

Passing By is licensed under [Apache-2.0](LICENSE).
