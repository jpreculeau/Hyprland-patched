#!/bin/bash
# shellcheck disable=SC2016 # code passed to in_script expands there / le code passé s'y développe
# Usage: fork/install_test.sh fork/install.sh   (fake stack and stubs in a temporary directory, no sudo, no apt)
# Tests that apt is only asked for missing packages (apt-get install on an installed package upgrades it,
# which can pull a transition that needs a removal, refused by --no-remove), and that installing keeps
# every older stack instead of deleting the previous one.
# Teste qu'apt ne reçoit que les paquets absents (apt-get install sur un paquet présent le met à jour,
# ce qui peut entraîner une transition avec retrait, refusée par --no-remove), et que l'installation
# garde chaque ancienne pile au lieu de supprimer la précédente.
[ -f "${1:-}" ] || { echo "usage: $0 <path to install.sh>" >&2; exit 2; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
# the copy under test uses the fake stack, never /opt, and does not run main
# la copie testée utilise la fausse pile, jamais /opt, et ne lance pas main
grep -qx '    P=/opt/hypr-stack' "$1" || { echo "FAIL no 'P=/opt/hypr-stack' line in $1" >&2; exit 1; }
[ "$(tail -n 1 "$1")" = 'main "$@"' ] || { echo "FAIL last line of $1 is not 'main \"\$@\"'" >&2; exit 1; }
S="$T/install.sh"; sed '$d' "$1" > "$S"
fails=0 total=0
check() { total=$((total+1)); if [ "$2" = "$3" ]; then echo "OK   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }

# sudo runs the command, except apt-get which is only recorded; dpkg-query knows the packages in $T/installed
# sudo lance la commande, sauf apt-get qui est seulement noté ; dpkg-query connaît les paquets de $T/installed
in_script() { # <shell code run after sourcing the copy>
    PATH="$T/bin:$PATH" sh -c '
        sudo() { if [ "$1" = apt-get ]; then shift; echo "$*" >> "$T/apt"; else "$@"; fi; }
        . "$S"; P="$T/stack"; ARCH=arm64; APT_UPDATED=
        '"$1" 2>&1
}
export T S
mkdir "$T/bin"
cat > "$T/bin/dpkg-query" << 'STUB'
#!/bin/sh
# $T/installed: "<package> <db:Status-Status> <Architecture>" per installed instance; any other
# query is refused, so a change of the format asked by install.sh fails the tests
# toute autre requête est refusée : un changement du format demandé par install.sh fait échouer les tests
[ "$1" = -W ] && [ "$2" = '-f=${db:Status-Status} ${Architecture}\n' ] && [ $# -eq 3 ] \
    || { echo "dpkg-query stub: unexpected arguments: $*" >&2; exit 3; }
for p; do :; done
grep "^$p " "$T/installed" 2> /dev/null | cut -d' ' -f2- | grep . || exit 1
STUB
printf '#!/bin/sh\nexit 0\n' > "$T/bin/chown"   # root:root needs root / root:root demande root
chmod +x "$T/bin/dpkg-query" "$T/bin/chown"

# apt_install
printf 'liba installed arm64\nlibb installed all\n' > "$T/installed"; rm -f "$T/apt"
in_script 'apt_install liba libb' > /dev/null
check "all installed: apt not called" "$(cat "$T/apt" 2> /dev/null)" ""
rm -f "$T/apt"
in_script 'apt_install liba libc libb libd' > /dev/null
check "missing ones only: update then install" "$(cat "$T/apt")" "update
install -y --no-install-recommends --no-remove libc libd"
rm -f "$T/apt"; printf 'libh installed arm64\n' > "$T/installed"
in_script 'apt_install libh' > /dev/null
check "held package (hold ok installed): installed, apt not called" "$(cat "$T/apt" 2> /dev/null)" ""
rm -f "$T/apt"; printf 'libt triggers-pending arm64\nlibw triggers-awaited all\n' > "$T/installed"
in_script 'apt_install libt libw' > /dev/null
check "triggers pending or awaited: installed, apt not called" "$(cat "$T/apt" 2> /dev/null)" ""
rm -f "$T/apt"; printf 'libu unpacked arm64\nlibv half-installed arm64\nlibx half-configured arm64\n' > "$T/installed"
in_script 'apt_install libu libv libx' > /dev/null
check "unpacked, half-installed or half-configured: missing" "$(cat "$T/apt")" "update
install -y --no-install-recommends --no-remove libu libv libx"
rm -f "$T/apt"; printf 'libf installed armhf\nlibr config-files arm64\n' > "$T/installed"
in_script 'apt_install libf libr' > /dev/null
check "foreign arch or config-files only: missing" "$(cat "$T/apt")" "update
install -y --no-install-recommends --no-remove libf libr"

# swap_in: new stack in $P, the current one in $P.prev, an older .prev kept aside
# swap_in : nouvelle pile dans $P, l'actuelle dans $P.prev, une .prev plus ancienne gardée à part
stack() { mkdir -p "$1"; echo "$2" > "$1/version"; }
rm -rf "${T:?}"/stack*; stack "$T/new" v2
in_script 'swap_in "$T/new"' > /dev/null
check "first install: stack in place" "$(cat "$T/stack/version")" v2
check "first install: no .prev" "$(ls -d "$T"/stack.* 2> /dev/null)" ""
stack "$T/new" v3
in_script 'swap_in "$T/new"' > /dev/null
check "update: new stack in place" "$(cat "$T/stack/version")" v3
check "update: previous in .prev" "$(cat "$T/stack.prev/version")" v2
stack "$T/new" v4
out=$(in_script 'swap_in "$T/new"')
check "second update: new stack in place" "$(cat "$T/stack/version")" v4
check "second update: previous in .prev" "$(cat "$T/stack.prev/version")" v3
check "second update: older stack kept" "$(cat "$T"/stack.prev.*/version 2> /dev/null)" v2
check "second update: kept stack named in the output" "$(printf '%s\n' "$out" | grep -c "kept in $T/stack.prev.")" 1
check "second update: kept stacks listed with a total" "$(printf '%s\n' "$out" | grep -c 'total$')" 1
stack "$T/new" v5; stack "$T/stack.prev.20000101-000000" v0
in_script 'date() { echo 20000101-000000; }; swap_in "$T/new"' > /dev/null
check "same-second name taken: that stack untouched" "$(ls "$T/stack.prev.20000101-000000")" version
check "same-second name taken: current stack untouched" "$(cat "$T/stack/version")" v4
check "no temporary copy left" "$(ls -d "$T/stack.new" 2> /dev/null)" ""
check "source left for the download cleanup" "$(ls -d "$T/new" 2> /dev/null)" "$T/new"

echo "$((total-fails))/$total"
[ "$fails" -eq 0 ]
