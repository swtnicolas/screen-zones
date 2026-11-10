#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

deploy() {
    if kpackagetool6 --type "$1" --show "$2" >/dev/null 2>&1; then
        kpackagetool6 --type "$1" --upgrade "$3"
    else
        kpackagetool6 --type "$1" --install "$3"
    fi
}

scripting() {
    qdbus6 org.kde.KWin /Scripting "org.kde.kwin.Scripting.$1" "${@:2}"
}

icon=assets/icon/AppIcon.svg
[[ -f $icon ]] || icon=../assets/icon/AppIcon.svg

deploy KWin/Script local.screenzones package
deploy Plasma/Applet local.screenzones plasmoid
install -Dm644 "$icon" "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/local.screenzones.svg"
kwriteconfig6 --file kwinrc --group Plugins --key local.screenzonesEnabled true
qdbus6 org.kde.KWin /KWin reconfigure

copy="$XDG_RUNTIME_DIR/local.screenzones-$(date +%s%N)"
cp -r package "$copy"
scripting unloadScript local.screenzones >/dev/null
scripting loadDeclarativeScript "$copy/contents/ui/main.qml" local.screenzones >/dev/null
scripting start
find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'local.screenzones-*' ! -path "$copy" -exec rm -rf {} +

systemctl --user restart plasma-plasmashell
