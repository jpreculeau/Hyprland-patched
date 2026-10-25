#!/bin/bash
# Keeps a patched clone on upstream's latest release. Upstream history is not published: each
# release is one "snapshot" commit (the release's tree, unmodified, trailer "Upstream-Tag:"),
# chained to the previous snapshot, with the local patches on top (branch "patches", or "main"
# without it). On a new vX.Y.Z tag, a new snapshot is made and the patches are moved onto it
# (a patch merged upstream becomes empty and is dropped); fork/gcc14.sh (if present) regenerates
# "main" from "patches"; then both are pushed. Stops on a conflict, a dirty tree, or commits on
# origin that are not here, without pushing anything for that clone.
# Garde un clone corrigé sur la dernière version amont. L'historique amont n'est pas publié :
# chaque version est un commit « instantané » (arbre de la version, inchangé, ligne
# « Upstream-Tag: »), chaîné au précédent, avec les correctifs par-dessus. À chaque nouvelle
# étiquette vX.Y.Z : nouvel instantané, correctifs déplacés dessus (un correctif intégré en amont
# devient vide et disparaît), "main" régénérée par fork/gcc14.sh, puis poussée. S'arrête sans rien
# pousser sur un conflit, un arbre modifié, ou des commits d'origin absents d'ici.
#
# Usage: sync.sh [--no-push] <clone>...    remotes: "upstream" (hyprwm), "origin" (this repository)
# Exit / sortie: 0 ok, 1 error in at least one clone / erreur dans au moins un clone, 2 usage.
set -uo pipefail

# This script lives in a clone it rebases: run from a copy, so that bash never reads a file
# rewritten under its feet. / Ce script vit dans un clone qu'il rebase : tourner depuis une copie.
if [ -z "${FORK_SYNC_COPY:-}" ]; then
    copy=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/fork-sync.XXXXXX") || exit 1
    cp "$0" "$copy" || exit 1
    FORK_SYNC_COPY=$copy FORK_SYNC_NAME=$0 exec bash "$copy" "$@"
fi
trap 'rm -f "$FORK_SYNC_COPY"' EXIT

PUSH=yes
[ "${1:-}" = "--no-push" ] && { PUSH=no; shift; }
[ $# -gt 0 ] || { echo "usage: ${FORK_SYNC_NAME:-sync.sh} [--no-push] <clone>..." >&2; exit 2; }

# find_snapshot <rev>: newest snapshot under <rev>: "Upstream-Tag:" line and the tree of that tag
# instantané le plus récent sous <rev> : ligne « Upstream-Tag: » et arbre de cette étiquette
find_snapshot() {
    local c tag
    for c in $(git log --format=%H --grep='^Upstream-Tag: ' "$1"); do
        tag=$(git log -1 --format=%B "$c" | sed -n 's/^Upstream-Tag: //p')
        if [ "$(git rev-parse -q --verify "$tag^{tree}")" = "$(git rev-parse "$c^{tree}")" ]; then
            echo "$c"
            return
        fi
    done
}

# snapshot <tag> [parent]: commit holding the tree of upstream <tag>, unmodified
snapshot() {
    local tag=$1 parent=${2:-} date
    date=$(git log -1 --format=%cI "$tag^{commit}") || return 1
    GIT_AUTHOR_DATE=$date GIT_COMMITTER_DATE=$date git commit-tree "$tag^{tree}" ${parent:+-p "$parent"} \
        -m "upstream: $tag, unmodified source" \
        -m "Snapshot of upstream release $tag (commit $(git rev-parse --short=12 "$tag^{commit}")), without its history." \
        -m "Upstream-Tag: $tag"
}

sync_one() {
    local dir=$1 branch=patches newest base_snap base_tag new_snap old_main b
    local -A lease=()
    cd "$dir" || return 1
    git diff --quiet && git diff --cached --quiet || { echo "$dir: uncommitted changes / modifications non commitées" >&2; return 1; }
    git show-ref --quiet refs/heads/patches || branch=main
    git fetch --quiet --tags upstream || return 1

    # never overwrite commits made elsewhere / ne jamais écraser des commits faits ailleurs
    if [ "$PUSH" = yes ]; then
        git fetch --quiet origin || return 1
        for b in "$branch" main; do
            git rev-parse -q --verify "refs/remotes/origin/$b" > /dev/null || continue
            lease[$b]=$(git rev-parse "refs/remotes/origin/$b")
            [ "$b" = main ] && [ "$branch" = patches ] && continue   # generated, rewritten each time
            # origin must be what this clone pushed last (refs/sync/<b>, set after each sync push), or
            # contained in the local branch (e.g. pushed by hand from here): else commits came from
            # elsewhere. / origin doit être le dernier push de ce clone, ou contenu dans la branche locale.
            { git rev-parse -q --verify "refs/sync/$b" > /dev/null \
                && [ "${lease[$b]}" = "$(git rev-parse "refs/sync/$b")" ]; } \
                || git merge-base --is-ancestor "origin/$b" "$b" \
                || { echo "$dir: origin/$b has commits from elsewhere / commits poussés d'ailleurs" >&2; return 1; }
        done
    fi

    git checkout --quiet "$branch" || return 1
    newest=$(git tag --list 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    [ -n "$newest" ] || { echo "$dir: no release tag / aucune étiquette de version" >&2; return 1; }
    base_snap=$(find_snapshot "$branch")
    if [ -z "$base_snap" ]; then
        # first run: the branch sits on an upstream tag; put it on a snapshot of that tag
        # premier passage : la branche est sur une étiquette amont ; la poser sur son instantané
        base_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' "$branch") || return 1
        new_snap=$(snapshot "$base_tag") || return 1
        git rebase --quiet --onto "$new_snap" "$base_tag" "$branch" \
            || { git rebase --abort; echo "$dir: cannot move $branch onto its snapshot" >&2; return 1; }
        base_snap=$new_snap
    fi
    base_tag=$(git log -1 --format=%B "$base_snap" | sed -n 's/^Upstream-Tag: //p')
    if [ "$base_tag" != "$newest" ]; then
        new_snap=$(snapshot "$newest" "$base_snap") || return 1
        if ! git rebase --quiet --onto "$new_snap" "$base_snap" "$branch"; then
            git rebase --abort
            echo "$dir: conflict moving $branch from $base_tag to $newest / conflit au rebase" >&2
            return 1
        fi
    fi

    if [ "$branch" = patches ]; then
        old_main=$(git rev-parse -q --verify main || true)
        git checkout --quiet -B main patches || return 1
        if ! fork/gcc14.sh; then
            git reset --quiet --hard
            [ -n "$old_main" ] && git checkout --quiet -B main "$old_main"
            echo "$dir: fork/gcc14.sh failed / a échoué" >&2
            return 1
        fi
        if ! git diff --quiet; then
            git add -u
            git commit --quiet -m "build: GCC 14 compatibility (generated by fork/gcc14.sh)" \
                -m "Regenerated on each sync from the patches branch; see .github/README.md." \
                -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" || return 1
        fi
        # same tree and same patches as before: keep the old commit / rien de changé : garder l'ancien
        if [ -n "$old_main" ] && [ "$(git rev-parse 'main^{tree}')" = "$(git rev-parse "$old_main^{tree}")" ] \
            && [ "$(git rev-parse "$old_main~1")" = "$(git rev-parse patches)" ]; then
            git checkout --quiet -B main "$old_main"
        fi
    fi

    [ "$PUSH" = yes ] || { echo "$dir: on $newest, not pushed"; return 0; }
    local args=() branches=("$branch")
    [ "$branch" = patches ] && branches+=(main)
    for b in "${branches[@]}"; do
        args+=("--force-with-lease=refs/heads/$b:${lease[$b]:-}" "$b")
    done
    git push --quiet --atomic origin "${args[@]}" || return 1
    for b in "${branches[@]}"; do git update-ref "refs/sync/$b" "$b"; done
    echo "$dir: $newest + $(git rev-list --count "$(find_snapshot main)"..main) commit(s), pushed"
}

status=0
for clone in "$@"; do
    ( sync_one "$clone" ) || status=1
done
exit $status
