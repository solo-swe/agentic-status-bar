#!/bin/sh
#MISE description="Generate the app's Xcode project and build it (unsigned)"
# shellcheck source=mise-tasks/app/lib.sh
. "$(dirname "$0")/lib.sh"

generate
build -quiet build
