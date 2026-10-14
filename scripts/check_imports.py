#!/usr/bin/env python3
"""Guard against unused (and missing) relative imports, without a Dart SDK.

`flutter analyze --no-fatal-infos` still fails the build on *warnings*, and an
unused import is one of the easiest warnings to leave behind when a file is
rewritten — it is invisible in the editor and only shows up in CI, which costs
a full Actions round-trip.

For every relative import this script:

1. Works out the imported file's **public top-level names** (classes, enums,
   typedefs, extensions, mixins, top-level functions and constants).
2. Strips comments and string literals out of the importing file, so a name
   mentioned only in a doc comment does not keep an import alive.
3. Reports the import if **none** of those names appears in what is left.

It errs towards silence on purpose: a single surviving reference is enough,
because extension members invoked as `context.accent` cannot be resolved
without the analyzer.

    python3 scripts/check_imports.py [path ...]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

IMPORT_RE = re.compile(
    r"""^\s*import\s+'(?P<rel>[^']+)'(?:\s+as\s+(?P<prefix>\w+))?\s*(?:show[^;]*?)?\s*;""",
    re.MULTILINE,
)

# A declaration that starts at column 0 — i.e. a top-level name.
TOP_CLASS_RE = re.compile(
    r"^(?:abstract\s+|base\s+|final\s+|sealed\s+|interface\s+)*"
    r"(?:class|enum|typedef|extension|mixin)\s+(?P<name>\w+)",
    re.MULTILINE,
)
TOP_VAR_RE = re.compile(
    r"^(?:const|final|late\s+final)\s+[\w<>,\s\[\]{}?]+\s+(?P<name>\w+)\s*=",
    re.MULTILINE,
)
# A top-level function. The parameter list often spans several lines — e.g.
# `Future<void> openArtistByName(` — so only the opening paren is required on
# the declaration's first line.
#
# The return type must start at column 0 and may not contain whitespace, so an
# indented call like `return ColoredBox(` cannot masquerade as a declaration.
TOP_FUNC_RE = re.compile(
    r"^(?!import\b|export\b|part\b|library\b|@|//)"
    r"(?:external\s+)?(?:[\w<>\[\]{}?]+[ \t]+)?(?P<name>[A-Za-z_]\w*)\s*"
    r"(?:<[^>]*>\s*)?\([^;]*$",
    re.MULTILINE,
)

# Extensions are invoked through their receiver (`context.accent`), which this
# script cannot resolve, so a file that declares one is never reported.
EXTENSION_RE = re.compile(r"^extension\s+\w+\s+on\s+", re.MULTILINE)

# Names that appear everywhere and prove nothing about an import.
NOISE = {
    "build", "main", "dispose", "initState", "didChangeDependencies",
    "didUpdateWidget", "deactivate", "reassemble", "toString", "createState",
    "copyWith", "lerp", "toStringShort", "debugFillProperties",
}


def strip_non_code(src: str) -> str:
    """Remove comments, doc comments and string literals.

    A reference that only survives inside a comment is not a real reference,
    and the original version of this script was fooled by exactly that.
    """
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        # line comment
        if ch == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        # block / doc comment
        if ch == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        # string literal (single / double, with \escapes).
        #
        # Interpolations are kept: '${Fmt.count(3)} songs' is text, but it is
        # also a genuine reference to the imported `format.dart`, and dropping
        # it made the script report live imports as dead.
        if ch in "\"'":
            quote = ch
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    out.append(src[j : j + 2])
                    j += 2
                    continue
                if src[j] == quote:
                    break
                if src[j] == "\n":  # unterminated; treat as literal text
                    break
                if src[j] == "$" and j + 1 < n and src[j + 1] == "{":
                    depth, k = 1, j + 2
                    while k < n and depth:
                        if src[k] == "{":
                            depth += 1
                        elif src[k] == "}":
                            depth -= 1
                        elif src[k] == "\n":
                            break
                        k += 1
                    # Padded: without the separator the interpolation
                    # would butt straight onto the text before it and \b
                    # would no longer see a word boundary.
                    out.append(" " + src[j + 2 : k - 1] + " ")
                    j = k
                    continue
                j += 1
            i = j + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def top_level_names(src: str) -> set[str]:
    src = strip_non_code(src)
    names: set[str] = set()
    for pattern in (TOP_CLASS_RE, TOP_VAR_RE, TOP_FUNC_RE):
        for m in pattern.finditer(src):
            name = m.group("name")
            if name and name not in NOISE and len(name) > 2:
                names.add(name)
    return names


def check(root: Path) -> list[str]:
    problems: list[str] = []
    files = sorted(root.rglob("*.dart")) if root.is_dir() else [root]
    for f in files:
        src = f.read_text(encoding="utf-8", errors="replace")
        body = strip_non_code(IMPORT_RE.sub("", src))
        for m in IMPORT_RE.finditer(src):
            target = m.group("rel")
            if not target.startswith("."):
                continue
            if m.group("prefix"):
                continue  # `as foo`: usage is prefixed, not nameable
            target_path = (f.parent / target).resolve()
            if not target_path.exists():
                problems.append(f"{f}: missing import target {target}")
                continue
            source = strip_non_code(
                target_path.read_text(encoding="utf-8", errors="replace")
            )
            names = top_level_names(source)
            if not names:
                continue
            if any(re.search(r"\b" + re.escape(n) + r"\b", body) for n in names):
                continue
            # Only now give it the benefit of the doubt: an extension's members
            # are reached through the receiver (`context.accent`), which cannot
            # be resolved without the analyzer. Skipping earlier would hide real
            # unused imports in any file that happens to declare an extension.
            if EXTENSION_RE.search(source):
                continue
            problems.append(f"{f}: unused import '{target}'")
    return problems


def main(argv: list[str]) -> int:
    targets = argv[1:] or ["lib", "test"]
    problems: list[str] = []
    for t in targets:
        problems.extend(check(Path(t)))
    if problems:
        for p in problems:
            print(p)
        print(f"\n{len(problems)} unused/missing import(s)")
        return 1
    print("OK — no obviously unused relative imports")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
