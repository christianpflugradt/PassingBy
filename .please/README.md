# Repository governance

The separately installed published CLI in `.please-version` governs this project.
Candidate binaries never govern their own validation. Local Rules contain only
Passing By tooling; the baseline Rule Sets and independent provider import use immutable pins. The release binding is pinned independently.

## Setup

Prepare Swift 6+, Apple Command Line Tools, Python 3, Node from `mise.toml`,
actionlint 1.7.12 and Gitleaks 8.30.1. Tools are installed by the developer.
Prepare release dependencies with `npm ci --ignore-scripts`. Use the published
Please Behave version in `.please-version`, then synchronize:

```sh
sh Scripts/setup-git-hooks.sh --yes
```

If the published governor is unavailable, `python3 Scripts/install-governor.py`
downloads it with checksum and executable-version verification into the ignored
repository-local `.tools/please/bin`. Add that directory to PATH before setup or
Git operations. This does not install a machine-wide tool. CI and release jobs
install through published Please Behave Action v1.2.0 pinned to
`722d5967c094e5ac4bfe25e9f82b020ff34e9487`. Hook setup retrieves external sources;
runtime uses the immutable cache.
Managed wrappers live at Git’s effective hook path, preserve compatible custom
content and are not versioned. Setup retires an old local .githooks setting only
when its three event files are absent; any remaining custom hook is preserved
and requires manual integration. Other configured hook paths are retained.

## Execution points

| Local Rule | Execution points |
| --- | --- |
| format | pre-commit, pre-push, check |
| swift-tests | pre-push, check |
| native-build | pre-push, check, release-candidate |
| native-ui | pre-push only; requires a macOS desktop session |
| workflows | pre-push, check |
| release-rules | pre-push, check |
| npm-audit | check |
| release-package | release-candidate; depends on native-build |
| release-package-verify | release-candidate; depends on release-package |

`swift run PassingByTests` runs all unit and compatibility tests in one Rule.
The native build compiles, assembles and verifies the ad hoc signed app bundle.
Unit tests, build and native UI tests share the `swift` resource lock. Unit/UI
commands build their own inputs, so they do not depend on the release app build.
Native UI tests are excluded from CI and Release Candidate. Formatting never edits
files; `mise run format` is the explicit editing command.

The external `multi-point/security` and `repository-conventions` sets run filename,
Gitleaks and byte-for-byte license checks at check and pre-push. Check reads the
working tree; pre-push reads HEAD. Release Readiness uses the external
`release/releasable-project` set for successful
push CI for the exact source SHA, trusted repository, workflow, main branch and
`Check` job. Partial CI reruns may retain successful jobs from the same run.

Commit-msg uses only the external Conventional Commits Check and advisory wording
Review. Scopes come from `commit-scopes.txt`. The independent `gemini-flash-lite`
provider package supplies the adapter; no copy lives in this repository. The Review
uses only the header, without the diff, body or repository files. Export
GEMINI_API_KEY in the shell invoking Git. Review FAIL and ERROR, including unavailable
credentials, remain visible without blocking commits. It uses at most three
attempts, 1/3-second waits, 20 seconds per request and a 70-second provider deadline.
No local commit-message, commit-range or PR-title checks are present. The previous
disabled Hannes reviews are retired; no product or accessibility review is enabled.

Agents receive validation through Git commit/push and inspect saved results with
`please status --details`. Pre-commit checks formatting; pre-push runs the complete
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
CI, Readiness and Candidate execute through the same published Action with the
CLI version from `.please-version`, `checks-only: 'true'` and `summary: 'true'`.
Install-only mode precedes explicit synchronization; the execution invocation
produces the Job Summary.

Plan runs Semantic Release without preparation, tagging or publication and binds
the version to the dispatched source SHA. Candidate builds that version, verifies the app bundle and packages it; source checks and unit tests are reused from CI. Packaging
records the archive and executable SHA-256, source SHA, version and workflow
run/attempt. Both Candidate and Publish verify the exact artifact set, safe ZIP
paths, executable permission, app metadata, icon and code signature. Publish runs
on macOS to verify the extracted app; it never rebuilds; the published governor verifies common release evidence.
Only artifacts from the same workflow run and attempt are accepted. A release
rerun missing the current attempt’s artifact requires rerunning all jobs.

Semantic Release rechecks the planned version, checkout SHA and remote main before
tagging. Changed main or version refuses publication. Release creates no version
commit and publishes the ZIP, SHA256SUMS and metadata.json. Release serialization
prevents competing workflow publications; it is not an atomic lock against pushes.

Version policy follows the CLI for stable releases: feat is minor; fix, perf,
chore, refactor, build and effective revert are patch. Historical build(release)
version commits produce no release. ci, config, docs, style and test produce no
release unless breaking; breaking changes are major because Passing By is already
1.x. Scoped reverts cancel unreleased originals in version calculation and notes.
There is no commit-history or PR-title validation; history analysis for versioning
remains. Offline release tests cover policy, lifecycle, source/version guards and
artifact rejection. Workflow syntax is checked by actionlint.

## Shared release evidence

The separate external `release/releasable-project` Rule Set is pinned independently
from the repository baseline. Its `release-contract` Check uses
`release-ci.json` and `release-artifacts.json`. Readiness trusts exact-source CI
without an age limit or repeated source/security checks. Candidate builds and
artifact-specific tests remain local. After they pass, `release-record` writes
internal `release-evidence/TARGET.json` manifests. Publish collects every expected
target and invokes `release-verify` before publication. The shared Check verifies
repository, workflow, source, version, current run/attempt and artifact hashes.
Missing or altered evidence blocks publication; partial release reruns require
rerunning all jobs. Evidence is transferred separately and is not a public asset.

Before tagging, thin local Semantic Release adapters load the cached external
publication guard exported by `release-verify`. The shared implementation checks
the recalculated version, checkout, dispatched SHA, repository, main branch and
current remote main. Custom prerelease/image publication reuses that source guard.
Offline lifecycle fixtures exercise the actual pinned external module from cache.

## Published governor updates

`.please-version` records the exact latest stable published governor. The shared
`renovate-governor` preset in the external ruleset repository tracks GitHub
Releases and auto-merges newer stable versions, including major updates, after
checks pass. Governor updates have no dependency cooldown; ordinary dependency
policies remain unchanged. CI installs the proposed pin before running checks.
Renovate runs determine update timing. Local governor preparation uses the same
pin; candidate binaries never become the governor.
