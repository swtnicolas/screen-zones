#!/bin/bash
set -uo pipefail

data=${XDG_DATA_HOME:-$HOME/.local/share}

qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript local.screenzones >/dev/null 2>&1
kpackagetool6 --type KWin/Script --remove local.screenzones
kpackagetool6 --type Plasma/Applet --remove local.screenzones
rm -f "$data/icons/hicolor/scalable/apps/local.screenzones.svg"
rm -rf "${XDG_RUNTIME_DIR:?}"/local.screenzones-*
kwriteconfig6 --file kwinrc --group Plugins --key local.screenzonesEnabled --delete
qdbus6 org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.unregister kwin "ScreenZones Menu" >/dev/null 2>&1
qdbus6 org.kde.KWin /KWin reconfigure
systemctl --user restart plasma-plasmashell
