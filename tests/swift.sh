#!/bin/sh
# Build the Swift package and run its tests. Extra arguments are passed to `swift test`
# (e.g. --filter ConfigTests).
cd "$(dirname "$0")/.." || exit 1

swift build && swift test "$@"
