#!/bin/bash
set -euo pipefail

version_pattern='^[1-9][0-9]*\.[0-9]+\.[0-9]+$'

: "${RELEASE_VERSION:?Set RELEASE_VERSION to the Semantic Release version}"
if [[ ! "$RELEASE_VERSION" =~ $version_pattern ]]; then
  echo "RELEASE_VERSION must be a numeric major.minor.patch version" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

app="$root/build/Passing By.app"
archive="$root/build/Passing-By-$RELEASE_VERSION.zip"
[[ -x "$app/Contents/MacOS/PassingBy" ]]
[[ -f "$app/Contents/Resources/PassingBy.icns" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$RELEASE_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$RELEASE_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "local.passingby.app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$app/Contents/Info.plist")" == "Passing By" ]]

"$root/tools/check-app-bundle.sh" "$app"
rm -f "$archive"
ditto -c -k --norsrc --keepParent "$app" "$archive"
unzip -tqq "$archive"
mkdir -p "$root/dist"
# Keep the local build/ ZIP and replace only the generated release directory.
rm -f "$root"/dist/Passing-By-*.zip "$root/dist/metadata.json" "$root/dist/SHA256SUMS"
cp "$archive" "$root/dist/"
python3 "$root/.github/scripts/release-artifacts.py" record
echo "Packaged $archive"
