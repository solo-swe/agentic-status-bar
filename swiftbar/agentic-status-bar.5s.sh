#!/bin/sh
#
# <xbar.title>Agentic Status Bar</xbar.title>
# <xbar.version>v1.0.0-rc.1</xbar.version>
# <xbar.author>Hakan Serce</xbar.author>
# <xbar.desc>Shows in one menu-bar item whether any running Claude Code agent needs you.</xbar.desc>
# <xbar.dependencies>asb</xbar.dependencies>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisappearPlugin>true</swiftbar.hideDisappearPlugin>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
#
# The SwiftBar front end of asb (the Swift CLI in this repo): it prints the menu,
# and run with arguments, it performs a menu action.

# Resolve our own path, following symlinks (SwiftBar runs a symlink). Menu items
# run this path, so it must stay the same however the plugin is linked.
self="$0"
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in
    /*) self="$link" ;;
    *) self="${self%/*}/$link" ;;
  esac
done
case "$self" in
  /*) plugin_path="$self" ;;
  *) plugin_path="$PWD/$self" ;;
esac
repo="${plugin_path%/*}/.."

# asb: the override (tests), the installed copy, or a build in this repo.
asb=""
for candidate in "${ASB_BIN:-}" \
  "$HOME/Library/Application Support/agentic-status-bar/bin/asb" \
  "$repo/.build/release/asb" "$repo/.build/debug/asb"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    asb="$candidate"
    break
  fi
done

if [ -z "$asb" ]; then
  [ "$#" -gt 0 ] && exit 0
  echo ":exclamationmark.triangle: | sfcolor=#B25000,#FFD60A"
  echo "---"
  echo "Agentic Status Bar needs asb"
  echo "Build it with: swift build -c release | color=gray"
  exit 0
fi

if [ "$#" -gt 0 ]; then
  exec "$asb" action "$@"
fi
exec "$asb" swiftbar --plugin "$plugin_path"
