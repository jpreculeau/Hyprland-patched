#!/bin/bash
# Usage: fork/session_test.sh fork/session/hypr-stack-session   (fake stack and HOME in a temporary directory)
# Tests which config the session passes to Hyprland: hyprland-stack.lua first (Hyprland >= 0.57 reads Lua only),
# then hyprland-stack.conf (0.56), else none (Hyprland's own lookup: hyprland.lua, then hyprland.conf before
# 0.57); and that the optional hook runs before Hyprland.
# Teste la config passée à Hyprland : hyprland-stack.lua d'abord (Lua seul à partir de 0.57), puis
# hyprland-stack.conf (0.56), sinon aucune (recherche de Hyprland) ; et le crochet lancé avant Hyprland.
[ -f "${1:-}" ] || { echo "usage: $0 <path to hypr-stack-session>" >&2; exit 2; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
# the copy under test uses the fake stack, never /opt / la copie testée utilise la fausse pile, jamais /opt
grep -qx 'P=/opt/hypr-stack' "$1" || { echo "FAIL no 'P=/opt/hypr-stack' line in $1" >&2; exit 1; }
S="$T/hypr-stack-session"; sed "s|^P=/opt/hypr-stack\$|P=$T/stack|" "$1" > "$S"
fails=0 total=0
check() { total=$((total+1)); if [ "$2" = "$3" ]; then echo "OK   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }

# fake stack: start-hyprland records its arguments / fausse pile : start-hyprland note ses arguments
mkdir -p "$T/stack/bin" "$T/fakebin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/args"\n' "$T" > "$T/stack/bin/start-hyprland"
printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/systemctl"
chmod +x "$T/stack/bin/start-hyprland" "$T/fakebin/systemctl"

run() { # <files to create in ~/.config/hypr> ; prints the -c argument, or "none"
    rm -rf "${T:?}/home" "${T:?}/args"; mkdir -p "$T/home/.config/hypr"
    for f in "$@"; do : > "$T/home/.config/hypr/$f"; done
    HOME="$T/home" PATH="$T/fakebin:$PATH" sh "$S" > /dev/null 2>&1
    a=$(cat "$T/args" 2> /dev/null)
    case "$a" in *" -c "*) c=${a##* -c }; echo "${c#"$T/home/.config/hypr/"}" ;; "") echo "not started" ;; *) echo none ;; esac
}

check "lua only: lua" "$(run hyprland-stack.lua)" hyprland-stack.lua
check "lua and conf: lua wins" "$(run hyprland-stack.lua hyprland-stack.conf)" hyprland-stack.lua
check "stack conf only (0.56): conf" "$(run hyprland-stack.conf)" hyprland-stack.conf
check "neither: no -c (Hyprland's own lookup)" "$(run hyprland.conf hyprland.lua)" none
check "start-hyprland given the stack's Hyprland" "$(run hyprland-stack.lua >/dev/null; grep -c -- "--path $T/stack/bin/Hyprland --" "$T/args")" 1

# hook runs before Hyprland / crochet lancé avant Hyprland
rm -rf "${T:?}/home" "${T:?}/args"; mkdir -p "$T/home/.config/hypr"; : > "$T/home/.config/hypr/hyprland-stack.lua"
printf '#!/bin/sh\necho hook >> "%s/args"\n' "$T" > "$T/home/.config/hypr/hypr-stack-pre"; chmod +x "$T/home/.config/hypr/hypr-stack-pre"
HOME="$T/home" PATH="$T/fakebin:$PATH" sh "$S" > /dev/null 2>&1
check "hook first" "$(head -1 "$T/args")" hook

echo "$((total-fails))/$total"
[ "$fails" = 0 ]
