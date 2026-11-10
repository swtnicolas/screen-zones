#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

"$root/scripts/quit.sh"
launchctl bootout "gui/$(id -u)/local.screenzones.login" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.screenzones.login.plist"
rm -rf "$HOME/Applications/ScreenZones.app"
