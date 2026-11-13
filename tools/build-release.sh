#!/bin/bash
set -euo pipefail

version_pattern='^[1-9][0-9]*\.[0-9]+\.[0-9]+$'

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
swift build -c release --product PassingByApp
bin_path="$(swift build -c release --show-bin-path)"
app="$root/build/Passing By.app"
mkdir -p "$root/build"
staging="$(mktemp -d "$root/build/.passing-by.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
staged_app="$staging/Passing By.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$bin_path/PassingByApp" "$staged_app/Contents/MacOS/PassingBy"
cp "$root/Resources/Info.plist" "$staged_app/Contents/Info.plist"
if [[ -n "${RELEASE_VERSION:-}" ]]; then
  # Release builds keep the production identity; local builds use the development identity from Info.plist.
  if [[ ! "$RELEASE_VERSION" =~ $version_pattern ]]; then
    echo "RELEASE_VERSION must be a numeric major.minor.patch version" >&2
    exit 1
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$staged_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $RELEASE_VERSION" "$staged_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.passingby.app' "$staged_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName Passing By' "$staged_app/Contents/Info.plist"
fi

icon_tmp="$(mktemp -d)"
trap 'rm -rf "$staging" "$icon_tmp"' EXIT
iconset="$icon_tmp/PassingBy.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((size * scale))
    suffix=""
    if ((scale == 2)); then suffix="@2x"; fi
    sips -s format png -z "$pixels" "$pixels" \
      "$root/passing-by-icon-master.svg" \
      --out "$iconset/icon_${size}x${size}${suffix}.png" >/dev/null
  done
done
iconutil -c icns "$iconset" -o "$staged_app/Contents/Resources/PassingBy.icns"

codesign --force --sign - "$staged_app"
"$root/tools/check-app-bundle.sh" "$staged_app"
rm -rf "$app"
mv "$staged_app" "$app"
echo "Built $app"
