#!/bin/bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
out=$repo/dist/screenzones-install.sh
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

install -Dm755 "$repo/scripts/install.sh" "$stage/scripts/install.sh"
install -Dm755 "$repo/scripts/uninstall.sh" "$stage/scripts/uninstall.sh"
install -Dm644 "$repo/../assets/icon/AppIcon.svg" "$stage/assets/icon/AppIcon.svg"
cp -r "$repo/package" "$stage/package"
cp -r "$repo/plasmoid" "$stage/plasmoid"

mkdir -p "$repo/dist"
{
    cat <<'END'
#!/bin/bash
set -euo pipefail
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
tail -n +"$(awk '/^__PAYLOAD__$/ { print NR + 1; exit }' "$0")" "$0" | tar xz -C "$dir"
if [[ ${1:-} == --uninstall ]]; then
    "$dir/scripts/uninstall.sh"
else
    "$dir/scripts/install.sh"
fi
exit 0
__PAYLOAD__
END
    tar cz -C "$stage" --owner=0 --group=0 --numeric-owner .
} >"$out"
chmod 755 "$out"
echo "$out"
