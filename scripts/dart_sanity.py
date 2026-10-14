#!/usr/bin/env python3
"""A coarse Dart sanity check.

There is no Dart toolchain in every environment this repo is touched from, and
a mistyped brace is the one mistake that silently breaks a whole file. This
script tokenizes just enough of the language — strings, raw strings, character
literals, comments — to make sure the structural brackets balance and that no
file ends mid-construct.

It also checks that every top-level declaration really is top level. A function
moved between scopes without its closing brace keeps every bracket balanced —
the counts cancel out — but it swallows every declaration after it, which is
exactly the failure this second check exists to catch.

It is a safety net, not a compiler:

    python3 scripts/dart_sanity.py [path ...]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

PAIRS = {')': '(', ']': '[', '}': '{'}

# A declaration that must sit at column 0, i.e. outside any other declaration.
DECL_RE = re.compile(
    r"^(?:abstract\s+|base\s+|final\s+|sealed\s+)*"
    r"(?:class|enum|typedef|extension|mixin)\s+\w"
)


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


def blank_out(src: str) -> str:
    """Replace the inside of comments and strings with inert filler.

    Braces inside `'...'` or `// ...` are text, not structure, so they must not
    move the depth counter. Newlines are kept so line numbers stay correct.
    """
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if ch == "/" and nxt == "/":
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if ch == "/" and nxt == "*":
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(c if c == "\n" else " " for c in src[i:j]))
            i = j
            continue
        if ch in "\"'":
            quote = ch
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == quote or src[j] == "\n":
                    break
                j += 1
            out.append("".join(c if c == "\n" else " " for c in src[i : j + 1]))
            i = j + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def check_declaration_depth(path: Path) -> list[str]:
    """Every `class`/`enum`/`mixin` must start at brace depth 0.

    A function lifted out of a class without its closing brace leaves the
    bracket counts balanced while the parser stays inside an expression, so
    everything after it is misread. This is the only cheap way to see it.
    """
    errors: list[str] = []
    depth = 0
    src = blank_out(path.read_text(encoding="utf-8", errors="replace"))
    for number, text in enumerate(src.split("\n"), 1):
        if DECL_RE.match(text) and depth != 0:
            errors.append(
                f"{path}:{number}: declaration inside another construct "
                f"(brace depth {depth}) — a brace is probably missing above: "
                f"{text.strip()[:50]}"
            )
        depth += text.count("{") - text.count("}")
    if depth != 0:
        errors.append(f"{path}: unbalanced braces (ends at depth {depth})")
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
        errs = check(f) + check_declaration_depth(f)
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
