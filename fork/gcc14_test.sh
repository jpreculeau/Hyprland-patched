#!/bin/bash
# Usage: fork/gcc14_test.sh   (temporary directory; needs the system g++, GCC 14 on Debian 13)
# Tests that fork/gcc14-compat.py rewrites the C++23/C++26 library calls missing in libstdc++ 14 into code
# this compiler builds, with the same result, and that a second run changes nothing (idempotent).
# Teste que gcc14-compat.py réécrit les appels C++23/C++26 absents de libstdc++ 14 en code que ce
# compilateur accepte, avec le même résultat, et qu'une deuxième passe ne change rien.
FORK=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0 total=0
check() { total=$((total+1)); if [ "$2" = "$3" ]; then echo "OK   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }

# one case per file: <name> <body of main, printing one line> <expected output>
# un cas par fichier : <nom> <corps de main, qui affiche une ligne> <sortie attendue>
case_() {
    mkdir -p "$T/src"
    printf '#include <iostream>\n#include <string>\n#include <variant>\n#include <vector>\nint main() {\n%s\n}\n' "$2" > "$T/src/$1.cpp"
    WANT[$1]=$3
}
declare -A WANT
case_ append_range 'std::vector<int> v{1}; std::vector<int> w{2, 3}; v.append_range(w); std::cout << v.size() << v[2] << "\n";' 33
case_ insert_range 'std::vector<int> v{1, 4}; std::vector<int> w{2, 3}; v.insert_range(v.begin() + 1, w); std::cout << v[1] << v[2] << v[3] << "\n";' 234
case_ visit 'std::variant<int, std::string> v = 4; auto f = [](int k) { return k; };
std::cout << v.visit([&](auto&& x) { if constexpr (std::is_same_v<std::decay_t<decltype(x)>, int>) return f((x)); else return 0; }) << "\n";' 4
case_ subview 'std::string s = "abcdef"; size_t i = 2; std::cout << s.subview(i, 2) << "|" << s.subview(i + 1) << "\n";' 'cd|def'

python3 "$FORK/gcc14-compat.py" "$T/src" > /dev/null
cp -r "$T/src" "$T/once"
python3 "$FORK/gcc14-compat.py" "$T/src" > /dev/null
check "second run changes nothing" "$(diff -r "$T/once" "$T/src" > /dev/null && echo same)" same
for n in "${!WANT[@]}"; do
    if g++ -std=gnu++26 -o "$T/$n" "$T/src/$n.cpp" 2> "$T/$n.err"; then
        check "$n: rewritten and built" "$("$T/$n")" "${WANT[$n]}"
    else
        check "$n: rewritten and built" "$(grep -m1 'error:' "$T/$n.err")" "${WANT[$n]}"
    fi
done

echo "$((total-fails))/$total"
[ "$fails" = 0 ]
