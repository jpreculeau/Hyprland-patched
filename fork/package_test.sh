#!/bin/bash
# Usage: fork/package_test.sh fork/package.sh   (fake ldd, throwaway tree / faux ldd, arbre jetable)
# Tests package.sh --list-deps: a library "not found" among many files fails the listing; otherwise
# the Debian packages of the libraries are listed once each.
# Teste package.sh --list-deps : une bibliothèque introuvable parmi beaucoup de fichiers fait échouer.
[ -f "${1:-}" ] || { echo "usage: $0 <path to package.sh>" >&2; exit 2; }
PK=$(realpath "$1"); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0 total=0
check() { total=$((total+1)); if [ "$2" = "$3" ]; then echo "OK   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }
mkdir -p "$T/bin" "$T/root/bin"
for i in $(seq 300); do cp /bin/true "$T/root/bin/t$i"; done
LIBC=$(ldd /bin/true | grep -oE '/[^ ]*libc\.so\.6' | head -1)
cat > "$T/bin/ldd" << LDD
#!/bin/bash
for f in "\$@"; do
    echo "\$f:"
    [ -n "\$MISSING" ] && [ "\$f" = "\$MISSING" ] && echo "	libgone.so.1 => not found"
    echo "	libc.so.6 => $LIBC (0x0000)"
done
LDD
chmod +x "$T/bin/ldd"
export PATH="$T/bin:$PATH" LIST_ROOT="$T/root"

out=$(MISSING='' "$PK" --list-deps 2>/dev/null); rc=$?
check "all found: exit 0" "$rc" 0
check "all found: libc6 listed once" "$(grep -cx libc6 <<< "$out")" 1
first=$(find "$T/root" -type f | head -1)
MISSING=$first "$PK" --list-deps > /dev/null 2>&1; rc=$?
check "one library not found among 300 files: exit 1" "$rc" 1
echo "RESULT package: $((total - fails))/$total"
exit $((fails > 0))
