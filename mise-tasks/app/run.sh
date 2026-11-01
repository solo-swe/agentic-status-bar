#!/bin/sh
#MISE description="Build and start the app, quitting a running copy first (KEY=VALUE arguments: its environment)"
# Extra KEY=VALUE arguments are passed to the app as environment variables,
# e.g. ASB_STATE_DIR=/path/to/fixture.
# shellcheck source=mise-tasks/app/lib.sh
. "$(dirname "$0")/lib.sh"

generate
build -quiet build || exit 1
quit_app
sleep 1
for pair in "$@"; do set -- "$@" --env "$pair"; shift; done
open_app "$@"
