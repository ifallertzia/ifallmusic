#!/usr/bin/env python3
"""Heuristic guard against unused relative imports.

`flutter analyze --no-fatal-infos` still fails the build on *warnings*, and an
unused import is one of the easiest warnings to leave behind when a file is
rewritten. For every relative import this script pulls the public top-level
names out of the imported file and reports imports whose declarations are never
mentioned in the importing file.

It errs towards silence: an import survives if **any** of its declarations is
referenced, so extension members invoked through `context.foo` still count as
long as the declaring file exports at least one used name.

    python3 scripts/check_imports.py [path ...]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

IMPORT_RE = re.compile(
    r"^\s*import\s+(?:'(?P<rel>[^']+)'|\"(?P<rel2>[^\"]+)\")"
    r"(?:\s+as\s+(?P<prefix>\w+))?\s*;",
    re.MULTILINE,
)

DECL_RE = re.compile(
    r"^\s*(?:abstract\s+|base\s+|final\s+|sealed\s+|mixin\s+)*"
    r"(?:class|enum|typedef|extension|mixin)\s+(?P<name>\w+)"
    r"|^\s*(?:const|final)\s+(?:[\w<>,\s\[\]]+?\s+)?(?P<varname>\w+)\s*="
    r"|^\s*(?:[\w<>,\s\[\]?]+\s+)?(?P<fname>\w+)\s*\(",
    re.MULTILINE,
)


def top_level_names(path: Path) -> set[str]:
    src = path.read_text(encoding="utf-8", errors="replace")
    names: set[str] = set()
    for m in DECL_RE.finditer(src):
        for key in ("name", "varname", "fname"):
            value = m.group(key)
            if value and not value[0].isupper() is False or value:
                names.add(value)
    # Constants and classes are the useful signal; drop obviously generic words.
    noise = {"build", "main", "dispose", "initState", "copyWith", "lerp", "toString"}
    return {n for n in names if n not in noise and len(n) > 2}


def check(root: Path) -> list[str]:
    problems: list[str] = []
    files = sorted(root.rglob("*.dart")) if root.is_dir() else [root]
    for f in files:
        src = f.read_text(encoding="utf-8", errors="replace")
        body = IMPORT_RE.sub("", src)  # ignore import lines themselves
        for m in IMPORT_RE.finditer(src):
            target = m.group("rel") or m.group("rel2")
            if not target or not target.startswith("."):
                continue
            if m.group("prefix"):
                continue
            target_path = (f.parent / target).resolve()
            if not target_path.exists():
                problems.append(f"{f}: missing import target {target}")
                continue
            names = top_level_names(target_path)
            if not names:
                continue
            if any(re.search(r"\b" + re.escape(n) + r"\b", body) for n in names):
                continue
            problems.append(f"{f}: possibly unused import '{target}'")
    return problems


def main(argv: list[str]) -> int:
    targets = argv[1:] or ["lib", "test"]
    problems: list[str] = []
    for t in targets:
        problems.extend(check(Path(t)))
    if problems:
        for p in problems:
            print(p)
        print(f"\n{len(problems)} possible unused import(s)")
        return 1
    print("OK — no obviously unused relative imports")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
