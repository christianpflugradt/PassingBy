#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
swift build --product PassingByApp
settings_test_dir=$(mktemp -d)
trap 'rm -rf "$settings_test_dir"' EXIT
settings_bin_path=$(swift build --show-bin-path)
if [ -d "$settings_bin_path/Modules" ]; then
  module_path="$settings_bin_path/Modules"
  core_objects="$settings_bin_path/PassingByCore.build/*.o"
else
  module_path="$settings_bin_path"
  core_objects="$settings_bin_path/PassingByCore.o"
fi
# shellcheck disable=SC2086 # The object glob must expand.
swiftc -swift-version 6 -D SETTINGS_NAVIGATION_TESTS -I "$module_path" \
  Sources/PassingByApp/*.swift .please/checks/ui-tests/test-settings-navigation.swift .please/checks/ui-tests/test-smart-substitutions.swift \
  $core_objects -o "$settings_test_dir/settings-navigation-tests"
"$settings_test_dir/settings-navigation-tests"
