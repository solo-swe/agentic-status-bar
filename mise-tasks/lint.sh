#!/bin/sh
#MISE description="shellcheck on every shell script (mise-tasks/, scripts/)"
# Run shellcheck on every shell script in the repo. Used locally and by CI.
cd "$(dirname "$0")/.." || exit 1

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is not installed. Install it with: mise install" >&2
  exit 1
fi

files="$(find mise-tasks scripts -name '*.sh' -type f | sort | tr '\n' ' ')"

echo "shellcheck: $files"
# shellcheck disable=SC2086 # word splitting of the file list is intended
shellcheck -x -S warning -s sh $files && echo "lint ok"
