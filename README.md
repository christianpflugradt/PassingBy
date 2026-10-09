# Passing By

Passing By is a small native macOS workspace for information that matters now: to-dos, appointments, and Markdown notes. It keeps your information on your Mac and is designed to stay calm and low-distraction.

## Features

- A compact dashboard for open to-dos and upcoming appointments.
- To-dos, date-based appointments, and notes you can edit directly in Markdown.
- Optional categories to group and filter your items.
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

## Development

You need Apple Command Line Tools with Swift 6 or later (`xcode-select --install`) and [Mise](https://mise.jdx.dev/) for the commands below. No separate Node.js runtime is required to build or run the app. See [Product.md](Product.md) for the product specification.

From the repository root:

```sh
mise install
mise run build
mise run test
mise run test-ui # Native Settings focus tests; requires a macOS desktop session.
```

`mise run build` creates `build/Passing By.app`. Open that bundle from Finder to run it. The build is ad hoc signed. Local builds have a separate development app identity and display “Development build” in About.

After cloning, run `sh Scripts/setup-git-hooks.sh` to enable the repository commit-message hook. Commit subjects use `type: description` or `type(scope): description` with a non-empty description. If included, the scope must be one of those listed below.

Allowed types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`, `style`, `revert`.

Allowed scopes: `app`, `ui`, `notes`, `todos`, `appointments`, `settings`, `persistence`, `security`, `build`, `release`, `docs`, `deps`, `tests`.

Examples: `build: assemble local app`, `fix(ui): correct sidebar alignment`, `docs: clarify setup`.

### Releases

Releases use Semantic Release and SemVer. Run `mise run release` to start the manual GitHub workflow; Conventional Commits determine the next version. After tests pass, Semantic Release passes that version directly to the release build and packaging steps, creates the `v<version>` tag, and publishes the GitHub Release with the ZIP attached. For local packaging checks, run `RELEASE_VERSION=1.2.3 mise run build && RELEASE_VERSION=1.2.3 mise run package` with a test version.

## License

Passing By is licensed under [Apache-2.0](LICENSE).
