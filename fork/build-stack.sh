#!/bin/bash
# Builds the whole Hyprland-patched stack (fork/stack.txt, plus Lua 5.5) into $PREFIX
# (default /opt/hypr-stack), for Debian 13 (GCC 14). Build dependencies: fork/build-deps.txt.
# fork/package.sh runs it in a private mount namespace where /opt/hypr-stack is a staging
# directory, so the installed stack is never touched.
# Compile toute la pile Hyprland-patched (fork/stack.txt, plus Lua 5.5) dans $PREFIX
# (/opt/hypr-stack par défaut), pour Debian 13 (GCC 14). fork/package.sh la lance dans un espace
# de montage privé où /opt/hypr-stack est un dossier de préparation : la pile installée n'est
# jamais touchée.
#
# Env: PREFIX, SRC (sources and build trees, kept for incremental builds / sources gardées pour
#      recompiler vite), JOBS, STACK_URL_<name> (overrides a git url, '-' -> '_' in <name>).
set -euo pipefail
FORK=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
P=${PREFIX:-/opt/hypr-stack}
S=${SRC:-$HOME/.cache/hypr-patched/src}
L=$S/logs
J=${JOBS:-2}
LUA_V=5.5.1
LUA_SHA256=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
mkdir -p "$S" "$L" "$P/lib/pkgconfig"
export PKG_CONFIG_PATH=$P/lib/pkgconfig:$P/share/pkgconfig
export PATH=$P/bin:$PATH
export LD_LIBRARY_PATH=$P/lib   # code generators run during the build / générateurs lancés pendant la compilation
export LDFLAGS="-L$P/lib -Wl,-rpath-link,$P/lib -Wl,-rpath,$P/lib"
MANIFEST=$S/manifest.txt
: > "$MANIFEST"

log() { echo "== $* ($(date +%H:%M))"; }

# newest vX.Y.Z (or X.Y.Z) tag of <url>, optionally restricted to <major.minor>
latest_tag() {
    git ls-remote --tags --refs "$1" | sed 's#.*refs/tags/##' \
        | { grep -E "^v?${2:+${2//./\\.}\\.}[0-9]+(\\.[0-9]+)*$" || true; } | sort -V | tail -1
}

# fetch <name> <url> <ref>: clone once, then check out <ref> (tag or branch)
fetch() {
    local n=$1 url=$2 ref=$3 var="STACK_URL_${1//-/_}"
    url=${!var:-$url}
    [ -d "$S/$n/.git" ] || git clone -q "$url" "$S/$n"
    git -C "$S/$n" remote set-url origin "$url"
    git -C "$S/$n" fetch -q --tags --force origin
    if git -C "$S/$n" rev-parse -q --verify "refs/remotes/origin/$ref" >/dev/null; then
        git -C "$S/$n" checkout -q -f --detach "origin/$ref"
    else
        git -C "$S/$n" checkout -q -f --detach "$ref"
    fi
    git -C "$S/$n" clean -q -fdx -e build-stack/
    git -C "$S/$n" submodule update -q --init --recursive
    echo "$n $ref $(git -C "$S/$n" rev-parse --short HEAD)" >> "$MANIFEST"
}

# link against this stack's libraries, not older ones from /usr (some .pc files put -L/usr/lib first)
# lier contre les bibliothèques de la pile, pas les anciennes de /usr
prefer_stack_libs() {
    local so b
    for so in "$P"/lib/*.so; do
        [ -e "$so" ] || continue
        b=$(basename "$so")
        sed -i "s#/usr/lib/aarch64-linux-gnu/$b\([ ;:]\)#$so\1#g; s#/usr/lib/aarch64-linux-gnu/$b\$#$so#g" "$1"
    done
}

cmk() { # <name> [cmake args]
    local n=$1; shift; log "$n"
    cmake -S "$S/$n" -B "$S/$n/build-stack" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$P" \
        -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_SYSCONFDIR="$P/etc" -DCMAKE_PREFIX_PATH="$P" \
        -DCMAKE_INSTALL_RPATH="$P/lib" -DBUILD_TESTING=OFF \
        "$@" > "$L/$n.log" 2>&1
    prefer_stack_libs "$S/$n/build-stack/build.ninja"
    cmake --build "$S/$n/build-stack" -j"$J" >> "$L/$n.log" 2>&1
    cmake --install "$S/$n/build-stack" >> "$L/$n.log" 2>&1
}

msn() { # <name> [meson args]
    local n=$1; shift; log "$n"
    meson setup --reconfigure "$S/$n/build-stack" "$S/$n" --prefix="$P" --libdir=lib --buildtype=release \
        -Dc_link_args="-Wl,-rpath,$P/lib" "$@" > "$L/$n.log" 2>&1 \
      || meson setup "$S/$n/build-stack" "$S/$n" --prefix="$P" --libdir=lib --buildtype=release \
        -Dc_link_args="-Wl,-rpath,$P/lib" "$@" > "$L/$n.log" 2>&1
    ninja -C "$S/$n/build-stack" -j"$J" >> "$L/$n.log" 2>&1
    ninja -C "$S/$n/build-stack" install >> "$L/$n.log" 2>&1
}

# --- sources
HYPR_MM=
while IFS='|' read -r n url ref; do
    case "$n" in ''|'#'*) continue ;; esac
    if [ "$ref" = latest ]; then
        if [ "$n" = hyprland-plugins ]; then ref=$(latest_tag "$url" "$HYPR_MM"); else ref=$(latest_tag "$url"); fi
        [ -n "$ref" ] || { echo "no release tag for $n" >&2; exit 1; }
    fi
    fetch "$n" "$url" "$ref"
    if [ "$n" = Hyprland ]; then
        # this repository has no upstream tags: read the version file / pas d'étiquettes amont ici
        HYPR_MM=$(cut -d. -f1,2 "$S/Hyprland/VERSION")
    fi
done < "$FORK/stack.txt"

# --- GCC 14 for the other hypr* repositories (Hyprland-patched already carries it)
# GCC 14 pour les autres dépôts hypr* (Hyprland-patched l'intègre déjà)
for d in "$S"/hypr*; do
    [ "$(basename "$d")" = Hyprland ] || python3 "$FORK/gcc14-compat.py" "$d" > /dev/null
done
for f in hyprtoolkit/src/system/Icons.cpp; do
    grep -qF gcc14-shim.hpp "$S/$f" || sed -i "1i #include \"$FORK/gcc14-shim.hpp\"" "$S/$f"
done

# --- Lua 5.5 (shared library + .pc, not in Debian 13 / absents de Debian 13)
log lua
if [ ! -d "$S/lua-$LUA_V" ]; then
    curl --proto '=https' -fsSL "https://www.lua.org/ftp/lua-$LUA_V.tar.gz" -o "$S/lua.tar.gz"
    echo "$LUA_SHA256  $S/lua.tar.gz" | sha256sum -c --quiet
    tar --no-same-owner -xzf "$S/lua.tar.gz" -C "$S" && rm "$S/lua.tar.gz"
fi
( cd "$S/lua-$LUA_V/src" && make clean > /dev/null \
  && { make -j"$J" MYCFLAGS="-fPIC -O2" linux-readline || make -j"$J" MYCFLAGS="-fPIC -O2" linux; } > "$L/lua.log" 2>&1 \
  && gcc -shared -o liblua5.5.so.5.5 -Wl,-soname,liblua5.5.so.5.5 $(ls ./*.o | grep -vE '/(lua|luac)\.o$') -lm -ldl \
  && install -d "$P/include/lua5.5" && install -m644 lua.h luaconf.h lualib.h lauxlib.h lua.hpp "$P/include/lua5.5/" \
  && install -m755 liblua5.5.so.5.5 "$P/lib/" && ln -sfn liblua5.5.so.5.5 "$P/lib/liblua5.5.so" )
printf 'prefix=%s\nName: Lua\nDescription: Lua 5.5\nVersion: %s\nLibs: -L%s/lib -llua5.5 -lm -ldl\nCflags: -I%s/include/lua5.5\n' \
    "$P" "$LUA_V" "$P" "$P" > "$P/lib/pkgconfig/lua5.5.pc"
echo "lua $LUA_V" >> "$MANIFEST"

# --- system libraries too old in Debian 13 / bibliothèques système trop anciennes dans Debian 13
msn wayland -Ddocumentation=false -Dtests=false
msn wayland-protocols -Dtests=false
# Lua plugins off: libinput would load Lua 5.4 next to Hyprland's 5.5 (symbol clash)
msn libinput -Dlua-plugins=disabled -Ddocumentation=false -Dtests=false -Ddebug-gui=false -Dlibwacom=true \
    -Dudev-dir="$P/lib/udev"

# --- hypr* (all linked against the same libhyprutils / toutes liées à la même libhyprutils)
cmk hyprutils
cmk hyprlang
cmk hyprwire
cmk hyprcursor
cmk hyprgraphics
cmk aquamarine
cmk Hyprland -DNO_TESTS=ON -DPython3_EXECUTABLE=/usr/bin/python3   # stub generator needs Python >= 3.12

log hyprbars
( cd "$S/hyprland-plugins/hyprbars" && make clean > /dev/null 2>&1 || true
  CXXFLAGS="-O2 $(pkg-config --cflags lua5.5)" make -j"$J" > "$L/hyprbars.log" 2>&1 )
install -Dm755 "$S/hyprland-plugins/hyprbars/hyprbars.so" "$P/lib/hyprland-plugins/hyprbars.so"

cmk hyprtoolkit
cmk hyprland-guiutils
cmk xdg-desktop-portal-hyprland
cmk hyprlock
cmk hypridle

# --- session, PAM file, manifest / session, fichier PAM, manifeste
install -Dm755 "$FORK/session/hypr-stack-session" "$P/bin/hypr-stack-session"
install -Dm644 "$FORK/session/hyprland-stack.desktop" "$P/share/hypr-stack/hyprland-stack.desktop"
install -Dm644 "$S/hyprlock/pam/hyprlock" "$P/share/hypr-stack/pam/hyprlock"
install -Dm644 "$MANIFEST" "$P/share/hypr-stack/manifest.txt"

log done
ldd "$P/bin/Hyprland" | grep -E "hyprutils|aquamarine|lua|libinput|not found" || true
