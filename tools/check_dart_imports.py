#!/usr/bin/env python3
"""مدقّق بنية سريع لمشروع Dart/Flutter (بديل خفيف عن المحلّل عند غياب SDK).

يتحقّق من:
  1. أن كل استيراد نسبي أو package:ruview_wifi يشير إلى ملف موجود.
  2. توازن الأقواس والعلامات في كل ملف (مع تجاهل النصوص والتعليقات).
  3. أن أي رمز (class/enum/typedef) معرّف في المشروع ومستخدم داخل ملف آخر
     مستوردٌ صراحةً في ذلك الملف (يمنع أخطاء "undefined identifier").

التشغيل:  python3 tools/check_dart_imports.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
TEST = ROOT / "test"
PACKAGE_NAME = "ruview_wifi"

DECL_RE = re.compile(
    r"^(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+)*"
    r"(?:class|enum|mixin|extension|typedef)\s+([A-Za-z_]\w*)",
    re.MULTILINE,
)
IMPORT_RE = re.compile(r"""^\s*(?:import|export|part)\s+['"]([^'"]+)['"]""", re.MULTILINE)
IDENT_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\b")

OPENERS = "([{"
CLOSERS = ")]}"
PAIRS = {"(": ")", "[": "]", "{": "}"}


def strip_comments(source: str) -> str:
    """إزالة التعليقات فقط، مع احترام النصوص الحرفية التي تحتوي // أو /*."""
    out: list[str] = []
    index = 0
    length = len(source)
    quote: str | None = None
    triple = False

    while index < length:
        char = source[index]

        if quote is None:
            if source.startswith("//", index):
                newline = source.find("\n", index)
                if newline == -1:
                    break
                index = newline
                continue
            if source.startswith("/*", index):
                end = source.find("*/", index + 2)
                if end == -1:
                    break
                index = end + 2
                continue
            if source.startswith("'''", index):
                quote, triple = "'", True
                out.append("'''")
                index += 3
                continue
            if source.startswith('"""', index):
                quote, triple = '"', True
                out.append('"""')
                index += 3
                continue
            if char in ("'", '"'):
                quote, triple = char, False
                out.append(char)
                index += 1
                continue
            out.append(char)
            index += 1
            continue

        # داخل نص حرفي
        if char == "\\":
            out.append(source[index:index + 2])
            index += 2
            continue
        if triple and source.startswith(quote * 3, index):
            out.append(quote * 3)
            index += 3
            quote, triple = None, False
            continue
        if not triple and char == quote:
            out.append(char)
            index += 1
            quote = None
            continue
        out.append(char)
        index += 1

    return "".join(out)


def resolve_import(importer: Path, target: str) -> Path | None:
    if target.startswith("dart:"):
        return None
    if target.startswith("package:"):
        package_path = target[len("package:"):]
        prefix = PACKAGE_NAME + "/"
        if not package_path.startswith(prefix):
            return None
        return (LIB / package_path[len(prefix):]).resolve()
    return (importer.parent / target).resolve()


def collect_declarations(files: list[Path]) -> dict[str, Path]:
    declarations: dict[str, Path] = {}
    for path in files:
        source = strip_comments(path.read_text(encoding="utf-8"))
        for name in DECL_RE.findall(source):
            declarations.setdefault(name, path)
    return declarations


def check_balances(path: Path, source: str) -> list[str]:
    problems: list[str] = []
    stack: list[tuple[str, int]] = []
    line = 1
    for char in strip_comments(source):
        if char == "\n":
            line += 1
            continue
        if char in OPENERS:
            stack.append((char, line))
        elif char in CLOSERS:
            if not stack:
                problems.append(
                    f"{path.relative_to(ROOT)}:{line}: قوس إغلاق بلا فتح {char}"
                )
                continue
            opening, opening_line = stack.pop()
            if PAIRS[opening] != char:
                problems.append(
                    f"{path.relative_to(ROOT)}:{line}: قوس غير متطابق "
                    f"(فتح {opening} في السطر {opening_line} وأُغلق بـ {char})"
                )
    for opening, opening_line in stack:
        problems.append(
            f"{path.relative_to(ROOT)}:{opening_line}: قوس مفتوح غير مغلق {opening}"
        )
    return problems


def main() -> int:
    files = sorted(list(LIB.rglob("*.dart")) + list(TEST.rglob("*.dart")))
    if not files:
        print("لا توجد ملفات Dart")
        return 1

    problems: list[str] = []
    declarations = collect_declarations(files)

    for path in files:
        source = path.read_text(encoding="utf-8")
        code = strip_comments(source)

        imported: set[Path] = set()
        for target in IMPORT_RE.findall(source):
            resolved = resolve_import(path, target)
            if resolved is None:
                continue
            if not resolved.exists():
                problems.append(
                    f"{path.relative_to(ROOT)}: استيراد غير موجود '{target}'"
                )
                continue
            imported.add(resolved)

        problems.extend(check_balances(path, source))

        local_declarations = set(DECL_RE.findall(code))
        for name in set(IDENT_RE.findall(code)):
            if name in local_declarations:
                continue
            owner = declarations.get(name)
            if owner is None:
                continue
            if owner.resolve() == path.resolve():
                continue
            if owner.resolve() not in imported:
                problems.append(
                    f"{path.relative_to(ROOT)}: يستخدم '{name}' بدون استيراد "
                    f"{owner.relative_to(ROOT)}"
                )

    if problems:
        print(f"وُجدت {len(set(problems))} مشكلة:\n")
        for problem in sorted(set(problems)):
            print(" -", problem)
        return 1

    print(f"تم فحص {len(files)} ملف Dart — لا مشاكل هيكلية.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
