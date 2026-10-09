#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --product PassingByApp
settings_test_dir=$(mktemp -d)
trap 'rm -rf "$settings_test_dir"' EXIT
settings_bin_path=$(swift build --show-bin-path)
if [ -d "$settings_bin_path/Modules" ]; then
    swiftc -swift-version 6 -D SETTINGS_NAVIGATION_TESTS -I "$settings_bin_path/Modules" \
        Sources/PassingByApp/*.swift Scripts/test-settings-navigation.swift \
        "$settings_bin_path"/PassingByCore.build/*.o -o "$settings_test_dir/settings-navigation-tests"
else
    swiftc -swift-version 6 -D SETTINGS_NAVIGATION_TESTS -I "$settings_bin_path" \
        Sources/PassingByApp/*.swift Scripts/test-settings-navigation.swift \
        "$settings_bin_path/PassingByCore.o" -o "$settings_test_dir/settings-navigation-tests"
fi
"$settings_test_dir/settings-navigation-tests"
