#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="$HOME/Applications/ScreenZones.app"
agent="$HOME/Library/LaunchAgents/local.screenzones.login.plist"

"$root/scripts/build.sh"
"$root/scripts/quit.sh"
mkdir -p "$HOME/Applications" "$(dirname "$agent")"
rm -rf "$target"
cp -R "$root/build/ScreenZones.app" "$target"
cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>local.screenzones.login</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>$target</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>local.screenzones</string>
	</array>
</dict>
</plist>
EOF
open "$target"
