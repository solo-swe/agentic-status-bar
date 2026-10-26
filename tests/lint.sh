#!/bin/sh
# Run shellcheck on every shell script in the repo that exists. Used locally and by CI.
cd "$(dirname "$0")/.." || exit 1

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is not installed. Install it with: brew install shellcheck" >&2
  exit 1
fi

files=""
for f in tests/*.sh scripts/*.sh; do
  [ -f "$f" ] && files="$files $f"
done

echo "shellcheck:$files"
# shellcheck disable=SC2086 # word splitting of the file list is intended
shellcheck -x -S warning -s sh $files && echo "lint ok"
