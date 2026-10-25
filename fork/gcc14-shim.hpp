// GCC 14 / libstdc++ 14 compatibility (Debian 13) for code written for GCC 15+.
// Compatibilité GCC 14 / libstdc++ 14 (Debian 13) pour du code écrit pour GCC 15+.
// Included at the top of the files listed in fork/shim-files.txt by fork/gcc14.sh.
// Inclus en tête des fichiers listés dans fork/shim-files.txt par fork/gcc14.sh.
// No effect once the standard library provides these functions (feature-test macros).
// Sans effet dès que la bibliothèque standard fournit ces fonctions (macros de test).
#pragma once
#include <version> // feature-test macros before testing them / macros de test avant de les tester
#include <string>
#include <string_view>
#include <ranges>
#include <algorithm>
#include <functional>

// P2591 (C++26): std::string + std::string_view
#if !defined(__cpp_lib_string_view) || __cpp_lib_string_view < 202403L
namespace std {
inline string operator+(const string& a, string_view b) { string r; r.reserve(a.size() + b.size()); r.append(a).append(b); return r; }
inline string operator+(string&& a, string_view b) { a.append(b); return std::move(a); }
inline string operator+(string_view a, const string& b) { string r; r.reserve(a.size() + b.size()); r.append(a).append(b); return r; }
inline string operator+(string_view a, string&& b) { b.insert(0, a); return std::move(b); }
} // namespace std
#endif

// P1659 (C++23): std::ranges::starts_with / ends_with
#if !defined(__cpp_lib_ranges_starts_ends_with)
namespace std::ranges {
struct __hw_starts_with_fn {
    template <class R1, class R2, class Pred = ranges::equal_to>
    constexpr bool operator()(R1&& r1, R2&& r2, Pred pred = {}) const {
        auto i1 = ranges::begin(r1); auto e1 = ranges::end(r1);
        for (auto&& x : r2) { if (i1 == e1 || !std::invoke(pred, *i1, x)) return false; ++i1; }
        return true;
    }
};
struct __hw_ends_with_fn {
    template <class R1, class R2, class Pred = ranges::equal_to>
    constexpr bool operator()(R1&& r1, R2&& r2, Pred pred = {}) const {
        const auto n1 = ranges::distance(r1), n2 = ranges::distance(r2);
        if (n2 > n1) return false;
        auto i1 = ranges::begin(r1); ranges::advance(i1, n1 - n2);
        for (auto&& x : r2) { if (!std::invoke(pred, *i1, x)) return false; ++i1; }
        return true;
    }
};
inline constexpr __hw_starts_with_fn starts_with{};
inline constexpr __hw_ends_with_fn   ends_with{};
} // namespace std::ranges
#endif

// P2286 (C++23, libstdc++ 15): std::format of a std::vector, same output as the standard: [1, 2] / ["a", "b"]
// std::format d'un std::vector, sortie identique au standard
#if !defined(__cpp_lib_format_ranges)
#include <format>
#include <vector>
namespace std {
template <class T, class A>
struct formatter<vector<T, A>, char> {
    constexpr auto parse(format_parse_context& ctx) { return ctx.begin(); }
    template <class Ctx>
    auto format(const vector<T, A>& v, Ctx& ctx) const {
        auto out = ctx.out();
        *out++ = '[';
        bool first = true;
        for (const auto& e : v) {
            if (!first) { *out++ = ','; *out++ = ' '; }
            first = false;
            if constexpr (is_convertible_v<const T&, string_view>) out = format_to(out, "\"{}\"", string_view(e));
            else out = format_to(out, "{}", e);
        }
        *out++ = ']';
        return out;
    }
};
} // namespace std
#endif
