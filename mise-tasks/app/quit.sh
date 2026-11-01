#!/bin/sh
#MISE description="Quit the app started by app:run"
# shellcheck source=mise-tasks/app/lib.sh
. "$(dirname "$0")/lib.sh"

quit_app
exit 0
