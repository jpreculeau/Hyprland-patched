#!/usr/bin/env python3
"""Rewrites C++23 append_range/insert_range calls (missing in libstdc++ 14) into an equivalent insert().
Réécrit les appels C++23 append_range/insert_range (absents de libstdc++ 14) en insert() équivalent.
Usage: gcc14-compat.py <dir>...   Idempotent / idempotent (only touches the calls still present)."""
import re, sys, pathlib

def match_paren(s, i):  # i: index of '(' -> index of the matching ')' / index de la ')' correspondante
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '(': depth += 1
        elif s[j] == ')':
            depth -= 1
            if depth == 0: return j
    raise ValueError("unclosed parenthesis / parenthèse non fermée")

def split_top(args):  # split on the first top-level comma / découpe sur la première virgule de niveau 0
    depth = 0
    for k, c in enumerate(args):
        if c in '([{<': depth += 1
        elif c in ')]}>': depth -= 1
        elif c == ',' and depth == 0: return args[:k].strip(), args[k+1:].strip()
    return None, args.strip()

PAT = re.compile(r'([A-Za-z_][\w\.\->]*)\s*\.\s*(append_range|insert_range)\s*\(')

def rewrite(src):
    out, pos, n = [], 0, 0
    for m in PAT.finditer(src):
        if m.start() < pos: continue
        lp = m.end() - 1; rp = match_paren(src, lp)
        obj, kind, args = m.group(1), m.group(2), src[lp+1:rp]
        if kind == 'append_range':
            where, rng = f'{obj}.end()', args.strip()
        else:
            where, rng = split_top(args)
        repl = (f'[&]{{ auto&& _hw_r = {rng}; {obj}.insert({where}, std::ranges::begin(_hw_r), '
                f'std::ranges::end(_hw_r)); }}()')
        out.append(src[pos:m.start()]); out.append(repl); pos = rp + 1; n += 1
    out.append(src[pos:])
    return ''.join(out), n

total = 0
for root in sys.argv[1:]:
    for f in pathlib.Path(root).rglob('*'):
        if f.suffix not in ('.cpp', '.hpp', '.h', '.cc') or 'build-stack' in f.parts or 'subprojects' in f.parts:
            continue
        s = f.read_text(errors='surrogateescape')
        if 'append_range' not in s and 'insert_range' not in s: continue
        new, n = rewrite(s)
        if n:
            if '#include <ranges>' not in new: new = '#include <ranges>\n' + new
            f.write_text(new, errors='surrogateescape'); total += n; print(f'{f}: {n}')
print(f'gcc14-compat: {total} call(s) rewritten')
