#!/bin/zsh
set -euo pipefail

: "${RELEASE_VERSION:?Set RELEASE_VERSION to the Semantic Release version}"
if [[ ! "$RELEASE_VERSION" =~ '^[1-9][0-9]*\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "RELEASE_VERSION must be a numeric major.minor.patch version"
  exit 1
fi

root="${0:A:h:h}"
cd "$root"

app="$root/build/Passing By.app"
archive="$root/build/Passing-By-$RELEASE_VERSION.zip"
[[ -x "$app/Contents/MacOS/PassingBy" ]]
[[ -f "$app/Contents/Resources/PassingBy.icns" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$RELEASE_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$RELEASE_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "local.passingby.app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$app/Contents/Info.plist")" == "Passing By" ]]

"$root/Scripts/check-app-bundle.sh" "$app"
rm -f "$archive"
ditto -c -k --norsrc --keepParent "$app" "$archive"
unzip -tqq "$archive"
mkdir -p "$root/dist"
# Keep the local build/ ZIP and replace only the generated release directory.
rm -f "$root/dist/Passing-By-"*.zip(N) "$root/dist/metadata.json" "$root/dist/SHA256SUMS"
cp "$archive" "$root/dist/"
python3 "$root/Scripts/release-artifacts.py" record
print "Packaged $archive"
