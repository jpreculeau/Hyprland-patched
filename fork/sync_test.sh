#!/bin/bash
# Usage: fork/sync_test.sh fork/sync.sh   (throwaway repos in a temporary directory / dépôts jetables)
# Tests fork/sync.sh: snapshots instead of upstream history, new release (patches moved, pushed),
# release with a conflict, commits without a release, patch merged upstream, this repository's own
# *-patched.N tags, dirty tree, commits on origin that are not local, the patches -> main
# (fork/gcc14.sh) path, and the exit code with several clones.
# Teste fork/sync.sh : instantanés, nouvelle version, conflit, commits sans version, correctif
# intégré en amont, étiquettes *-patched.N, arbre modifié, origin en avance, chemin patches -> main.
[ -f "${1:-}" ] || { echo "usage: $0 <path to sync.sh>" >&2; exit 2; }
S=$(realpath "$1"); T=$(mktemp -d); cd "$T" || exit 1
trap 'rm -rf "$T"' EXIT
fails=0 total=0
check() { total=$((total+1)); if [ "$2" = "$3" ]; then echo "OK   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }
g() { git -c user.name=t -c user.email=t@t "$@"; }
setup() { # [patches]: upstream release v1.0.0; clone with one patch on it, in main or patches
  rm -rf up.git fork.git work u other
  g init -q -b main u && printf 'a\nb\nc\nd\ne\n' > u/f.txt && g -C u add f.txt && g -C u commit -qm "base, fixes owner/repo#1" && g -C u tag v1.0.0
  g clone -q --bare u up.git; g -C u remote add origin "$T/up.git"; g -C u push -q origin --tags
  g init -q --bare -b main fork.git
  g clone -q -o upstream up.git work && g -C work remote add origin "$T/fork.git"
  git -C work config user.name t && git -C work config user.email t@t
  sed -i 's/^c$/c patched/' work/f.txt && g -C work commit -qam patch
  if [ "${1:-}" = patches ]; then
    g -C work checkout -q -b patches
    mkdir -p work/fork && printf '#!/bin/sh\nsed -i "s/^d$/d gcc14/" f.txt\n' > work/fork/gcc14.sh && chmod +x work/fork/gcc14.sh
    g -C work add fork && g -C work commit -qm tooling
  fi
}
upstream_commit() { # <shell edit> <message> [tag]
  (cd u && eval "$1" && g commit -qam "$2" && { [ -z "${3:-}" ] || g tag "$3"; } && g push -q origin main --tags)
}
run() { "$S" "$@" > /dev/null 2>&1; echo $?; }
snap_tag() { g -C work log -1 --format=%B --grep='^Upstream-Tag: ' "$1" | sed -n 's/^Upstream-Tag: //p'; }

setup
check "first run: exit 0" "$(run work)" 0
check "first run: on a snapshot of v1.0.0" "$(snap_tag main)" v1.0.0
check "first run: upstream history not pushed" "$(g -C fork.git log --format=%s main | grep -c 'owner/repo')" 0
check "first run: pushed" "$(g -C fork.git rev-parse main)" "$(g -C work rev-parse main)"
check "first run: snapshot tree = v1.0.0 tree" "$(g -C work rev-parse main~1^{tree})" "$(g -C work rev-parse v1.0.0^{tree})"

P=$(g -C work rev-parse main)
upstream_commit "sed -i 's/^a\$/a dev/' f.txt" "unreleased work"
g -C work tag v9.9.9-patched.1 main   # this repository's own release tags are ignored
check "no new release: exit 0" "$(run work)" 0
check "no new release: unchanged" "$(g -C work rev-parse main)" "$P"

upstream_commit "sed -i 's/^e\$/e upstream/' f.txt" release v1.1.0
check "new release: exit 0" "$(run work)" 0
check "new release: on a snapshot of v1.1.0" "$(snap_tag main)" v1.1.0
check "new release: snapshots chained" "$(g -C work log --format=%s main | grep -c '^upstream: ')" 2
check "new release: patch kept" "$(grep -c 'c patched' work/f.txt)" 1

P=$(g -C work rev-parse main)
upstream_commit "sed -i 's/^c\$/c conflicting/' f.txt" conflicting v1.2.0
check "conflict: exit 1" "$(run work)" 1
check "conflict: branch unchanged" "$(g -C work rev-parse main)" "$P"
check "conflict: no rebase left" "$([ -d work/.git/rebase-merge ] || [ -d work/.git/rebase-apply ] && echo yes || echo no)" no
check "conflict: nothing pushed" "$(g -C fork.git rev-parse main)" "$P"

setup; run work > /dev/null
upstream_commit "sed -i 's/^c\$/c patched/' f.txt" "patch merged upstream" v1.1.0
check "patch merged upstream: exit 0" "$(run work)" 0
check "patch merged upstream: no local commit left" "$(g -C work rev-list --count "$(g -C work log -1 --format=%H --grep='^Upstream-Tag: ' main)"..main)" 0

setup; run work > /dev/null
echo dirty >> work/f.txt
check "dirty tree: exit 1" "$(run work)" 1
g -C work checkout -q -- f.txt

g clone -q -b main fork.git other && (cd other && sed -i 's/^b$/b elsewhere/' f.txt && g commit -qam elsewhere && g push -q origin main)
O=$(g -C fork.git rev-parse main)
upstream_commit "sed -i 's/^e\$/e upstream/' f.txt" release v1.1.0
check "commits on origin not local: exit 1" "$(run work)" 1
check "commits on origin not local: kept" "$(g -C fork.git rev-parse main)" "$O"

setup; run work > /dev/null
upstream_commit "sed -i 's/^e\$/e upstream/' f.txt" release v1.1.0
check "--no-push then push: rebased locally" "$(run --no-push work)" 0
check "--no-push then push: pushed" "$(run work)/$(g -C fork.git rev-parse main)" "0/$(g -C work rev-parse main)"

setup; run work > /dev/null
sed -i "s/^a$/a manual/" work/f.txt && g -C work commit -qam "manual commit" && g -C work push -q origin main
check "manual push from this clone, then sync: exit 0" "$(run work)" 0
upstream_commit "sed -i 's/^e\$/e upstream/' f.txt" release v1.1.0
check "manual push, then new release: rebased and pushed" "$(run work)/$(g -C fork.git rev-parse main)" "0/$(g -C work rev-parse main)"

setup patches
check "patches: exit 0" "$(run work)" 0
check "patches: main = patches + generated commit" "$(g -C work rev-list --count patches..main)/$(grep -c 'd gcc14' work/f.txt)" "1/1"
check "patches: both pushed" "$(g -C fork.git rev-parse patches)/$(g -C fork.git rev-parse main)" "$(g -C work rev-parse patches)/$(g -C work rev-parse main)"
M=$(g -C work rev-parse main)
check "patches, nothing new: exit 0" "$(run work)" 0
check "patches, nothing new: main kept" "$(g -C work rev-parse main)" "$M"
g -C work checkout -q patches && g -C work commit -q --amend -m "tooling, reworded" && g -C work checkout -q main
check "patches reworded: exit 0" "$(run work)" 0
check "patches reworded: main on top of patches" "$(g -C work rev-parse main~1)" "$(g -C work rev-parse patches)"

setup; cp -r work work2
upstream_commit "sed -i 's/^c\$/c conflicting/' f.txt" conflicting v1.1.0
check "two clones, one fails: exit 1" "$(run work2 work)" 1

echo "RESULT sync: $((total - fails))/$total"
exit $((fails > 0))
