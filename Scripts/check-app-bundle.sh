#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
app="${1:-$root/build/Passing By.app}"
plist="$app/Contents/Info.plist"
fail() { print -u2 "Invalid app bundle: $*"; exit 1; }
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }

[[ -d "$app" && -f "$plist" ]] || fail "missing app directory or Info.plist"
plutil -lint "$plist"
[[ "$(value CFBundlePackageType)" == APPL ]] || fail "wrong package type"
[[ "$(value CFBundleExecutable)" == PassingBy ]] || fail "wrong executable name"
[[ "$(value LSMinimumSystemVersion)" == 14.0 ]] || fail "wrong minimum macOS version"
binary="$app/Contents/MacOS/PassingBy"
[[ -f "$binary" && -x "$binary" ]] || fail "missing executable binary"
file -b "$binary" | grep -q 'Mach-O' || fail "executable is not Mach-O"
[[ "$(value CFBundleIconFile)" == PassingBy.icns ]] || fail "wrong icon name"
icon="$app/Contents/Resources/PassingBy.icns"
[[ -s "$icon" ]] || fail "missing app icon"
icon_tmp="$(mktemp -d)"
trap 'rm -rf "$icon_tmp"' EXIT
iconutil -c iconset "$icon" -o "$icon_tmp/PassingBy.iconset"

if [[ -n "${RELEASE_VERSION:-}" ]]; then
  [[ "$RELEASE_VERSION" =~ '^[1-9][0-9]*\.[0-9]+\.[0-9]+$' ]] || fail "invalid RELEASE_VERSION"
  expected_version="$RELEASE_VERSION"
  expected_identity=local.passingby.app
  expected_name='Passing By'
else
  expected_version=0.0.0
  expected_identity=local.passingby.app.development
  expected_name='Passing By Development'
fi
[[ "$(value CFBundleIdentifier)" == "$expected_identity" ]] || fail "wrong app identity"
[[ "$(value CFBundleName)" == "$expected_name" ]] || fail "wrong app name"
[[ "$(value CFBundleShortVersionString)" == "$expected_version" ]] || fail "wrong display version"
[[ "$(value CFBundleVersion)" == "$expected_version" ]] || fail "wrong build version"
codesign --verify --deep --strict --verbose=2 "$app"
print "App bundle verified: $app"
