#!/usr/bin/env python3
"""A coarse Dart sanity check.

There is no Dart toolchain in every environment this repo is touched from, and
a mistyped brace is the one mistake that silently breaks a whole file. This
script tokenizes just enough of the language — strings, raw strings, character
literals, comments — to make sure the structural brackets balance and that no
file ends mid-construct.

It is a safety net, not a compiler:

    python3 scripts/dart_sanity.py [path ...]
"""

from __future__ import annotations

import sys
from pathlib import Path

PAIRS = {')': '(', ']': '[', '}': '{'}


def check(path: Path) -> list[str]:
    src = path.read_text(encoding="utf-8", errors="replace")
    errors: list[str] = []
    stack: list[tuple[str, int]] = []  # (char, line)
    i = 0
    n = len(src)
    line = 1
    while i < n:
        ch = src[i]
        nxt = src[i + 1] if i + 1 < n else ""

        # newlines
        if ch == "\n":
            line += 1
            i += 1
            continue

        # line comment
        if ch == "/" and nxt == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue

        # block comment (nestable in Dart)
        if ch == "/" and nxt == "*":
            depth = 1
            i += 2
            while i < n and depth:
                if src[i] == "\n":
                    line += 1
                if src[i] == "/" and i + 1 < n and src[i + 1] == "*":
                    depth += 1
                    i += 2
                    continue
                if src[i] == "*" and i + 1 < n and src[i + 1] == "/":
                    depth -= 1
                    i += 2
                    continue
                i += 1
            continue

        # raw strings: r'...' and r"..."
        if ch == "r" and nxt in ("'", '"'):
            quote = nxt
            i += 2
            while i < n and src[i] != quote:
                if src[i] == "\n":
                    line += 1
                if src[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue

        # string interpolation-aware single/double quoted strings
        if ch in ("'", '"'):
            quote = ch
            # triple-quoted
            if src[i : i + 3] == quote * 3:
                i += 3
                while i < n and src[i : i + 3] != quote * 3:
                    if src[i] == "\n":
                        line += 1
                    i += 1
                i += 3
                continue
            i += 1
            brace_depth = 0
            while i < n:
                c = src[i]
                if c == "\n":
                    line += 1
                if c == "\\":
                    i += 2
                    continue
                if brace_depth == 0 and c == quote:
                    i += 1
                    break
                if c == "$" and i + 1 < n and src[i + 1] == "{":
                    brace_depth += 1
                    i += 2
                    continue
                if brace_depth and c == "{":
                    brace_depth += 1
                elif brace_depth and c == "}":
                    brace_depth -= 1
                i += 1
            continue

        if ch in "([{":
            stack.append((ch, line))
            i += 1
            continue

        if ch in ")]}":
            if not stack:
                errors.append(f"{path}:{line}: unmatched closing '{ch}'")
            else:
                open_ch, open_line = stack.pop()
                if PAIRS[ch] != open_ch:
                    errors.append(
                        f"{path}:{line}: '{ch}' closes '{open_ch}' opened at line {open_line}"
                    )
            i += 1
            continue

        i += 1

    for open_ch, open_line in stack:
        errors.append(f"{path}:{open_line}: unclosed '{open_ch}'")

    return errors


def main(argv: list[str]) -> int:
    targets = argv[1:] or ["lib", "test"]
    files: list[Path] = []
    for t in targets:
        p = Path(t)
        if p.is_file():
            files.append(p)
        else:
            files.extend(sorted(p.rglob("*.dart")))

    total = 0
    for f in files:
        errs = check(f)
        if errs:
            total += len(errs)
            for e in errs[:20]:
                print(e)
    if total:
        print(f"\n{total} structural problem(s) in {len(files)} file(s)")
        return 1
    print(f"OK — {len(files)} file(s) structurally balanced")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
