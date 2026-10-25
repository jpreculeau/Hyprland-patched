#!/bin/bash
# Makes the tree build with GCC 14 / libstdc++ 14 (Debian 13). Idempotent: run it on a clean
# checkout of the patched branch, then commit the result (fork/sync.sh does both).
# Rend l'arbre compilable avec GCC 14 / libstdc++ 14 (Debian 13). Idempotent : à lancer sur la
# branche des correctifs, puis committer le résultat (fork/sync.sh fait les deux).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
F=fork

# 1. #embed is not supported by GCC 14: Debian's patch (xxd -i) for the default Lua config
#    #embed n'existe pas en GCC 14 : correctif Debian (xxd -i) pour la config Lua par défaut
if git apply --check "$F/embed.patch" 2>/dev/null; then
    git apply "$F/embed.patch"
elif ! git apply --reverse --check "$F/embed.patch" 2>/dev/null; then
    echo "gcc14: embed.patch no longer applies / ne s'applique plus" >&2
    exit 1
fi

# 2. append_range / insert_range (C++23, libstdc++ 15) -> insert()
python3 "$F/gcc14-compat.py" src hyprctl hyprpm start

# 3. string + string_view, ranges::starts_with/ends_with, std::format of a vector
#    string + string_view, ranges::starts_with/ends_with, std::format d'un vector
while read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || { echo "gcc14: $f missing / absent" >&2; exit 1; }
    rel=$(realpath --relative-to="$(dirname "$f")" "$F/gcc14-shim.hpp")
    grep -qF "gcc14-shim.hpp" "$f" || sed -i "1i #include \"$rel\"" "$f"
done < "$F/shim-files.txt"

# 4. ?: between CXCBConnection and nullptr / ?: entre CXCBConnection et nullptr
sed -i 's|return m_connection ? \*m_connection : nullptr;|return m_connection ? static_cast<xcb_connection_t*>(*m_connection) : nullptr;|' \
    src/xwayland/XWM.hpp
