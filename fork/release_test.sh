#!/bin/bash
# Usage: fork/release_test.sh fork/release.sh   (fake gh, sync and build in a temporary directory)
# Tests fork/release.sh: first release, nothing changed, new commit, new upstream release, gh error,
# no snapshot. / Teste fork/release.sh avec un faux gh et une fausse construction.
[ -f "${1:-}" ] || { echo "usage: $0 <path to release.sh>" >&2; exit 2; }
R=$(realpath "$1"); T=$(mktemp -d); cd "$T" || exit 1
trap 'rm -rf "$T"' EXIT
fails=0 total=0
check() { total=$((total+1)); if [ "$2" = "$3" ]; then echo "OK   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }
g() { git -c user.name=t -c user.email=t@t "$@"; }

mkdir bin gh-state
cat > bin/gh << 'GH'
#!/bin/bash
# fake gh: releases stored as files gh-state/<n>-<tag> holding the notes (newest = latest)
S=$GH_STATE; [ -n "${GH_FAIL:-}" ] && { echo "gh: network error" >&2; exit 1; }
case "$1 $2" in
  "release list") ls "$S" | sort -n | sed 's/^[0-9]*-//' ;;
  "release view") f=$(ls "$S" | sort -n | tail -1); [ -n "$f" ] || { echo "release not found" >&2; exit 1; }; cat "$S/$f" ;;
  "release create") tag=$3; ls "$S" | sed 's/^[0-9]*-//' | grep -qxF "$tag" && { echo "tag exists" >&2; exit 1; }
     shift 3; notes=
     while [ $# -gt 0 ]; do [ "$1" = --notes-file ] && notes=$2; shift; done
     n=$(( $(ls "$S" | sed 's/-.*//' | sort -n | tail -1) + 1 )); cp "$notes" "$S/$n-$tag" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
GH
chmod +x bin/gh
export PATH="$T/bin:$PATH" GH_STATE="$T/gh-state"

mk_clone() { # <dir> <tag>: snapshot commit + one patch on main, fake fork/ scripts
  g init -q -b main "$1"; echo base > "$1/f"; g -C "$1" add f
  g -C "$1" commit -qm "upstream: $2, unmodified source" -m "Upstream-Tag: $2"
  mkdir -p "$1/fork"
  printf '#!/bin/bash\nexit 0\n' > "$1/fork/sync.sh"
  printf '#!/bin/bash\necho built >> %s/builds\nmkdir -p "$1/x/share/hypr-stack" && echo m > "$1/x/share/hypr-stack/manifest.txt"\ntar -C "$1/x" -I zstd -cf "$1/hypr-stack-debian13-arm64.tar.zst" . && rm -r "$1/x"\n(cd "$1" && sha256sum *.tar.zst > hypr-stack-debian13-arm64.tar.zst.sha256)\n' "$T" > "$1/fork/package.sh"
  echo '#!/bin/sh' > "$1/fork/install.sh"
  chmod +x "$1"/fork/*.sh; g -C "$1" add fork; g -C "$1" commit -qm patch
}
builds() { [ -f "$T/builds" ] && wc -l < "$T/builds" || echo 0; }
latest() { ls gh-state | sort -n | tail -1 | sed 's/^[0-9]*-//'; }

mk_clone hypr v1.0.0; mk_clone aq v0.1.0
"$R" hypr aq > /dev/null 2>&1; check "first release: exit 0" "$?" 0
check "first release: tag" "$(latest)" v1.0.0-patched.1
check "first release: built once" "$(builds)" 1

"$R" hypr aq > /dev/null 2>&1; check "unchanged: exit 0" "$?" 0
check "unchanged: no new release, no build" "$(ls gh-state | wc -l)/$(builds)" "1/1"

echo more >> hypr/f; g -C hypr commit -qam "another patch"
"$R" hypr aq > /dev/null 2>&1; check "new commit: exit 0" "$?" 0
check "new commit: numbered 2" "$(latest)" v1.0.0-patched.2

g -C hypr commit -q --allow-empty -m "upstream: v1.1.0, unmodified source" -m "Upstream-Tag: v1.1.0"
"$R" hypr aq > /dev/null 2>&1; check "new upstream release: exit 0" "$?" 0
check "new upstream release: numbered 1 again" "$(latest)" v1.1.0-patched.1

echo again >> hypr/f; g -C hypr commit -qam "yet another patch"
GH_FAIL=1 "$R" hypr aq > /dev/null 2>&1; check "gh error: exit 1" "$?" 1
check "gh error: nothing built" "$(builds)" 3

FORCE=1 "$R" hypr aq > /dev/null 2>&1; check "FORCE=1: exit 0" "$?" 0
check "FORCE=1: rebuilt and numbered 2" "$(latest)/$(builds)" "v1.1.0-patched.2/4"

rm gh-state/*-v1.1.0-patched.1   # a release deleted by hand / version supprimée à la main
echo last >> hypr/f; g -C hypr commit -qam "last patch"
"$R" hypr aq > /dev/null 2>&1; check "after a deleted release: exit 0" "$?" 0
check "after a deleted release: next number after the highest" "$(latest)" v1.1.0-patched.3

g init -q -b main nosnap; echo x > nosnap/f; g -C nosnap add f; g -C nosnap commit -qm x
mkdir -p nosnap/fork && cp hypr/fork/*.sh nosnap/fork/
"$R" nosnap aq > /dev/null 2>&1; check "no snapshot: exit 1" "$?" 1

echo "RESULT release: $((total - fails))/$total"
exit $((fails > 0))
