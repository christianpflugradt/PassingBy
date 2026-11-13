# Repository governance

The separately installed published CLI in `mise.toml` governs this project.
Candidate binaries never govern their own validation. Local Rules contain only
Passing By tooling (rule scripts in `.please/checks/`, release glue in `.github/scripts/`, build tools in `tools/`); the baseline Rule Sets and independent provider import use immutable pins. All Rule Sets and the provider share one reviewed revision.

## Setup

Prepare Swift 6+ and Apple Command Line Tools on macOS. Run `mise trust`,
`mise install` and `mise prepare` to install the exact Node, Python, actionlint
and Gitleaks versions in `mise.toml` and fetch locked npm dependencies.
Use the published Please Behave version in `mise.toml`, then synchronize:

```sh
mise exec -- please sync --yes
```

Use `mise exec -- please run --at pre-commit` or `mise exec -- please run --at pre-push`
for manual checks, and `mise exec -- git commit` / `mise exec -- git push` so hooks
inherit the same tools without shell activation. Plain commands require mise
shell activation or equivalent PATH setup; `mise install` alone does not activate
tools. Apple SDKs, Swift, signing tools, the native UI test desktop session and
credentials remain external prerequisites.

CI and candidate jobs use mise installation and the published Action pinned to a full
commit. One Action step uses
`install: 'false'` and `sync: 'true'` to synchronize and execute governance.
Hook setup retrieves external sources;
runtime uses the immutable cache.
Managed wrappers live at Git’s effective hook path, preserve compatible custom
content and are not versioned. Setup retires an old local .githooks setting only
when its three event files are absent; any remaining custom hook is preserved
and requires manual integration. Other configured hook paths are retained.

## Execution points

| Local Rule | Execution points |
| --- | --- |
| format-swift, format-python, format-shell | pre-commit, pre-push, check |
| swift-tests | pre-push, check |
| native-build | pre-push, check, release |
| ui-tests | pre-push only; requires a macOS desktop session |
| release-rules | pre-push, check |

`swift run PassingByTests` runs all unit and compatibility tests in one Rule.
The native build compiles, assembles and verifies the ad hoc signed app bundle.
Unit tests, build and UI tests share the `swift` resource lock. Unit/UI
commands build their own inputs, so they do not depend on the release app build.
Native UI tests are excluded from CI and Release Candidate. The three format Rules check one
tool each (`swift format`, `ruff format --check`, `shfmt -d`) and never edit files; the
developer and agent command `mise run format` applies all three.

The external `rulesets/security` and `rulesets/open-source-software` sets run filename,
Gitleaks and byte-for-byte license checks at check and pre-push. Check reads the
working tree; pre-push reads HEAD. Release Readiness runs `.github/scripts/check-release-ci.py` directly for successful
push CI for the exact source, repository, workflow, main branch and `Check` job.
Partial CI reruns may retain successful jobs from the same run.

The external `rulesets/repository-conventions` set limits AGENTS.md to 1500 approximate tokens at
pre-commit and check. Commit-msg uses its Conventional Commits Check and advisory wording
Review. Scopes come from `commit-scopes.txt`. The independent `gemini-flash-lite`
provider package supplies the adapter; no copy lives in this repository. The Review
uses only the header, without the diff, body or repository files. Export
GEMINI_API_KEY in the shell invoking Git. Review FAIL and ERROR, including unavailable
credentials, remain visible without blocking commits. It uses at most three
attempts, 1/3-second waits, 20 seconds per request and a 70-second provider deadline.
No local commit-message, commit-range or PR-title checks are present. The previous
disabled Hannes reviews are retired; no product or accessibility review is enabled.

Agents receive validation through Git commit/push and inspect saved results with
`please status --details`. Pre-commit checks formatting and the AGENTS.md size; pre-push runs the complete
local gate. Do not bypass hooks or manually repeat the full gate before pushing.
Targeted diagnostics and explicit source formatting are permitted. Tests use
synthetic data and mocked services, without live model calls. The normal commit
hook may call its advisory provider. Dependency preparation is separate from checks.
Builds reuse ignored `.build/` and `build/` outputs and never install the app.
The npm audit needs advisory access in CI; release reuses its result.

## Dependency updates

Renovate uses the best-practices preset and groups the Semantic Release toolchain.
Routine updates wait seven days; major versions and grouped GitHub Actions updates
wait fourteen days. Release timestamps are required, and strict internal checks
keep updates pending until eligible. Branches refresh when main advances.
Minor, patch and digest updates, plus grouped GitHub Actions updates, auto-merge
after green CI through Renovate; other major updates remain manual.

## Release contract

CI has `check` / `Check`. Manual Release on main has `plan` / `Plan`,
`release-readiness` / `Release Readiness`, `release-candidate` / `Release Candidate`
and `publish` / `Publish`, matching the CLI. Readiness and Candidate depend only
on Plan and run in parallel; Publish requires both to succeed. Only Plan and
Publish request repository write permission. CI and Candidate use macos-15;
Readiness uses Ubuntu. The app remains one native macOS artifact.
CI uses `check`; Candidate uses `release` to build and verify the versioned app.
Both execute one published Action step with summaries enabled.
Mise installs tools from `mise.toml`; `prepare` fetches locked
npm dependencies only. Release jobs install only their required tool subsets.
Python is exactly pinned; Swift and Apple SDKs remain host prerequisites.

Plan runs Semantic Release without preparation, tagging or publication and binds
the version to the dispatched source SHA. Candidate builds that version, verifies the app bundle and packages it; source checks and unit tests are reused from CI. Packaging
records the archive and executable SHA-256, source SHA, version and workflow
run/attempt. Both Candidate and Publish verify the exact artifact set, safe ZIP
paths, executable permission, app metadata, icon and code signature. Publish runs
on macOS to verify the extracted app; it never rebuilds. Plan and Publish never install or invoke Please Behave or hooks.
Only artifacts from the same workflow run and attempt are accepted. A release
rerun missing the current attempt’s artifact requires rerunning all jobs.

Semantic Release rechecks the planned version, checkout SHA and remote main before
tagging. Changed main or version refuses publication. Release creates no version
commit and publishes the ZIP, SHA256SUMS and metadata.json. Release serialization
prevents competing workflow publications; it is not an atomic lock against pushes.

Version policy follows the CLI for stable releases: feat is minor; fix, perf,
chore, refactor, build, config and effective revert are patch. Historical build(release)
version commits produce no release. ci, docs, style and test produce no
release unless breaking; breaking changes are major because Passing By is already
1.x. Scoped reverts cancel unreleased originals in version calculation and notes.
There is no commit-history or PR-title validation; history analysis for versioning
remains. Offline release tests cover policy, lifecycle, source/version guards and
artifact rejection. Workflow syntax (`workflows`), shell scripts (`shell`) and npm advisories (`npm-audit`) are checked by shared rules from the open-source-software ruleset.

## Shared release evidence

Workflow-owned policies live in `.github/release-ci.json` and
`.github/release-artifacts.json`. `.github/scripts/check-release-ci.py` verifies exact-source
CI without an age limit or repeated source checks. `.github/scripts/release-evidence.py`
records and verifies candidate manifests bound to repository, workflow, source,
version, run/attempt and artifact hashes. Missing or altered evidence blocks publication.
The local Semantic Release plugin checks version, checkout and current remote main
before tagging, without depending on an imported cache or governance setup.

## Published governor updates

`mise.toml` records the exact latest stable published governor. The shared
`renovate-governor` preset in the external ruleset repository tracks GitHub
Releases and auto-merges newer stable versions, including major updates, after
checks pass. Governor updates have no dependency cooldown; ordinary dependency
policies remain unchanged. CI installs the proposed pin before running checks.
Renovate runs determine update timing. Local governor preparation uses the same
pin; candidate binaries never become the governor.

## Governor version source

The exact published governor version is the `github:please-behave/cli` tool entry
in `mise.toml`. `mise install` installs the released executable through the GitHub
backend with checksum and available artifact-attestation verification. Run
`mise exec -- please --version` to inspect it. CI installs it through mise; the published Action reuses it
without a second installation or workflow version extraction. Candidate binaries never become the governor.
