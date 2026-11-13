#!/bin/sh
# Check tracked shell scripts, except zsh, with shfmt. Exit 0 PASS, 1 formatting differences, 2 technical failure.
set -eu
scripts=$(git ls-files '*.sh' | while IFS= read -r file; do
  head -n 1 "$file" | grep -q zsh || printf '%s\n' "$file"
done)
if [ -z "$scripts" ]; then
  echo "PASS: no shell scripts to check"
  exit 0
fi
errors=$(mktemp)
trap 'rm -f "$errors"' EXIT
status=0
differences=$(printf '%s\n' "$scripts" | xargs shfmt -d 2>"$errors") || status=$?
if [ "$status" -eq 0 ]; then
  echo "PASS: shfmt found no formatting differences"
  exit 0
fi
# shfmt also exits 1 for syntax errors, but only differences appear on standard output.
if [ -n "$differences" ]; then
  printf '%s\n' "$differences"
  echo "FAIL: shfmt would reformat these scripts"
  exit 1
fi
cat "$errors" >&2
echo "ERROR: shfmt failed" >&2
exit 2
