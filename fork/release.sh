#!/bin/bash
# Weekly job: aligns both clones on upstream's latest release (fork/sync.sh), and when the
# sources changed since the last published release, builds the stack (fork/package.sh) and
# publishes a GitHub release vX.Y.Z-patched.N with the archive and install.sh.
# Tâche hebdomadaire : aligne les deux clones sur la dernière version amont (fork/sync.sh) et, si
# les sources ont changé depuis la dernière publication, compile la pile et publie une version.
#
# Usage: fork/release.sh <Hyprland-patched clone> <aquamarine-patched clone>   (env FORCE=1: rebuild)
set -euo pipefail
if [ -z "${FORK_RELEASE_COPY:-}" ]; then   # the clone gets rebased: run from a copy / tourner depuis une copie
    copy=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/fork-release.XXXXXX") || exit 1
    cp "$0" "$copy" || exit 1
    FORK_RELEASE_COPY=$copy exec bash "$copy" "$@"
fi
trap 'rm -f "$FORK_RELEASE_COPY"' EXIT
[ $# -eq 2 ] || { echo "usage: $0 <Hyprland-patched clone> <aquamarine-patched clone>" >&2; exit 2; }
HYPR=$(realpath "$1"); AQ=$(realpath "$2")
REPO=jpreculeau/Hyprland-patched

"$HYPR/fork/sync.sh" "$HYPR" "$AQ"

# upstream release of the snapshot under main / version amont de l'instantané sous main
BASE=$(git -C "$HYPR" log -1 --format=%B --grep='^Upstream-Tag: ' main | sed -n 's/^Upstream-Tag: //p')
[ -n "$BASE" ] || { echo "no upstream snapshot under main / aucun instantané amont" >&2; exit 1; }
SOURCES="Sources: Hyprland-patched $(git -C "$HYPR" rev-parse --short=12 main), aquamarine-patched $(git -C "$AQ" rev-parse --short=12 main)"
# "no release yet" is fine; any other error (network, auth) stops here, before a long build
# « aucune version » est normal ; toute autre erreur (réseau, authentification) arrête ici
RELEASES=$(gh release list --repo "$REPO" --limit 200 --json tagName -q '.[].tagName')
if [ -n "$RELEASES" ] && [ -z "${FORCE:-}" ]; then
    LAST_BODY=$(gh release view --repo "$REPO" --json body -q .body)
    if grep -qxF "$SOURCES" <<< "$LAST_BODY"; then
        echo "release up to date / version à jour ($SOURCES)"
        exit 0
    fi
fi

OUT=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/fork-release-out.XXXXXX")
trap 'rm -f "$FORK_RELEASE_COPY"; rm -rf "$OUT"' EXIT
"$HYPR/fork/package.sh" "$OUT"
cp "$HYPR/fork/install.sh" "$OUT/install.sh"

# next number after the highest one (releases may have been deleted) / après le plus grand numéro
N=$(( $( { grep -oE "^${BASE//./\\.}-patched\.[0-9]+$" <<< "$RELEASES" || true; } | sed 's/.*\.//' | sort -n | tail -1) + 1 ))
TAG=$BASE-patched.$N
{
    echo "Hyprland $BASE with the patches of this repository, built for Debian 13 arm64 (GCC 14)."
    echo "Hyprland $BASE avec les correctifs de ce dépôt, compilée pour Debian 13 arm64 (GCC 14)."
    echo
    echo '```'
    echo "curl -fsSL https://github.com/$REPO/releases/latest/download/install.sh | sh"
    echo '```'
    echo
    echo "Components / composants (name, ref, commit):"
    echo '```'
    tar -I zstd -xOf "$OUT"/*.tar.zst ./share/hypr-stack/manifest.txt
    echo '```'
    echo
    echo "$SOURCES"
} > "$OUT/notes.md"
gh release create "$TAG" --repo "$REPO" --target main --title "Hyprland $BASE patched ($N)" \
    --notes-file "$OUT/notes.md" "$OUT"/*.tar.zst "$OUT"/*.sha256 "$OUT/install.sh"
echo "published / publiée : $TAG"
