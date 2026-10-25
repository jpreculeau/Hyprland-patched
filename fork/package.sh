#!/bin/bash
# Builds the stack in a private mount namespace (/opt/hypr-stack -> a staging directory: the
# installed stack is never touched), lists its Debian runtime dependencies, and makes
# dist/hypr-stack-debian13-arm64.tar.zst (+ .sha256). Needs unprivileged user namespaces.
# Compile la pile dans un espace de montage privé (/opt/hypr-stack -> dossier de préparation :
# la pile installée n'est jamais touchée), liste ses dépendances Debian à l'exécution, et
# produit dist/hypr-stack-debian13-arm64.tar.zst (+ .sha256).
#
# Usage: fork/package.sh [output dir]   (env: see fork/build-stack.sh)
set -euo pipefail

# --list-deps (run inside the namespace): Debian packages of the /usr libraries the stack loads.
# Debian 13 merges /usr: ldd may print /lib/..., which dpkg only knows as /usr/lib/...
# Paquets Debian des bibliothèques de /usr chargées par la pile (fusion de /usr : /lib -> /usr/lib).
if [ "${1:-}" = --list-deps ]; then
    root=${LIST_ROOT:-/opt/hypr-stack}
    # ldd once over every ELF file (static ones make ldd fail: ignore its exit code, read its output)
    # ldd une seule fois sur chaque ELF (les statiques le font échouer : on lit sa sortie)
    out=$(find "$root" -type f \( -perm -u+x -o -name '*.so*' \) -exec file -0 {} + \
          | tr '\0' '\t' | awk -F'\t' '$2 ~ /ELF/ {print $1}' | xargs -r -d '\n' ldd 2>/dev/null || true)
    missing=0
    if grep -q '=> not found' <<< "$out"; then
        grep '=> not found' <<< "$out" | sort -u >&2
        echo "ldd: libraries not found / bibliothèques introuvables" >&2
        missing=1
    fi
    while read -r lib; do
        real=$(realpath "$lib")
        pkg=
        for f in "$lib" "/usr$lib" "$real" "/usr$real"; do
            # "pkg[:arch][, pkg2]: /path"; "diversion by ..." lines are not owners
            pkg=$(LC_ALL=C dpkg-query -S "$f" 2>/dev/null | grep -v '^diversion ' | head -1 || true)
            [ -n "$pkg" ] && break
        done
        pkg=${pkg%%: /*}; pkg=${pkg%%,*}; pkg=${pkg%%:*}
        if [ -n "$pkg" ]; then echo "$pkg"; else echo "no Debian package for $lib" >&2; missing=1; fi
    done < <(grep -oE '=> /[^ ]+' <<< "$out" | cut -c4- | grep -v "^$root/" | sort -u)
    exit $missing
fi
FORK=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
OUT=$(realpath -m "${1:-$PWD/dist}")
WORK=${WORK:-$HOME/.cache/hypr-patched}
export SRC=${SRC:-$WORK/src}   # build-stack.sh and EPOCH below use the same sources / mêmes sources
STAGE=$WORK/stage
NAME=hypr-stack-debian13-arm64
[ -d /opt/hypr-stack ] || { echo "/opt/hypr-stack must exist (empty is fine) as a mount point / doit exister" >&2; exit 1; }
rm -rf "$STAGE" && mkdir -p "$STAGE" "$OUT"

# inside the namespace: build, then resolve the libraries each ELF file loads from /usr
# dans l'espace de noms : compiler, puis trouver les bibliothèques de /usr chargées par chaque ELF
unshare --user --map-root-user --mount bash -euo pipefail -c '
    mount --bind "$1" /opt/hypr-stack
    "$2/build-stack.sh"
    "$2/package.sh" --list-deps | sort -u > /opt/hypr-stack/share/hypr-stack/runtime-deps.txt
' _ "$STAGE" "$FORK"

[ -s "$STAGE/share/hypr-stack/runtime-deps.txt" ] || { echo "no runtime dependency found / aucune dépendance trouvée" >&2; exit 1; }
# reproducible: sorted, fixed owner and dates / reproductible : trié, propriétaire et dates fixes
EPOCH=$(git -C "$SRC/Hyprland" log -1 --format=%ct)
tar -C "$STAGE" --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$EPOCH" \
    --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime -I 'zstd -19 -T0' -cf "$OUT/$NAME.tar.zst" .
( cd "$OUT" && sha256sum "$NAME.tar.zst" > "$NAME.tar.zst.sha256" )
echo "$OUT/$NAME.tar.zst ($(du -h "$OUT/$NAME.tar.zst" | cut -f1))"
