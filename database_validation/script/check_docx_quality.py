#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Check a Word manuscript for the things that make it unsubmittable.

Generating a .docx is not the same as producing one that can be uploaded. This
inspects the file rather than the source: page geometry, the font that is actually
recorded on the runs, whether any table or figure is wider than the text column,
and whether any Markdown syntax survived into the document.

Usage:
    python scripts/audit/check_docx_quality.py [file.docx ...]
Exit code 0 when clean, 1 when a problem is found.
"""

from __future__ import annotations

import os
import re
import sys

from docx import Document
from docx.shared import Cm, Emu

TEXT_WIDTH_CM = 21.0 - 2.1 - 2.1  # A4 minus the left and right margins
MARKDOWN_LEFTOVERS = ["**", "## ", "|---", "`"]
REQUIRED_SECTIONS_EN = [
    "Abstract", "Background & Summary", "Methods", "Data Records",
    "Technical Validation", "Usage Notes", "Code availability", "Data availability",
    "References", "Figure legends", "Tables",
]
# The Chinese manuscript numbers its headings, so they are matched as prefixes.
REQUIRED_SECTIONS_ZH = [
    "摘要", "背景与概要", "方法", "数据记录", "技术验证", "使用说明",
    "代码可用性", "数据可用性", "参考文献", "图表",
]


def cm(v) -> float:
    return v / 360000.0 if v is not None else 0.0


def check(path: str) -> list[str]:
    problems: list[str] = []
    doc = Document(path)

    # --- page geometry
    s = doc.sections[0]
    w, h = cm(s.page_width), cm(s.page_height)
    if abs(w - 21.0) > 0.15 or abs(h - 29.7) > 0.15:
        problems.append(f"page size {w:.1f} x {h:.1f} cm, expected A4 21.0 x 29.7")
    text_w = w - cm(s.left_margin) - cm(s.right_margin)
    if text_w <= 0:
        problems.append("negative text width; margins are wrong")

    # --- font recorded on runs (sample the body, skip the title)
    fonts: dict[str, int] = {}
    sizes: dict[float, int] = {}
    for p in doc.paragraphs:
        for r in p.runs:
            nm = r.font.name
            if nm:
                fonts[nm] = fonts.get(nm, 0) + 1
            if r.font.size:
                pt = r.font.size.pt
                sizes[pt] = sizes.get(pt, 0) + 1
    if not fonts:
        problems.append("no run carries an explicit font name")
    elif "Times New Roman" not in fonts:
        problems.append(f"Times New Roman not used; saw {sorted(fonts)}")

    # --- tables
    for i, t in enumerate(doc.tables, 1):
        widths = [cm(c.width) for c in t.columns]
        total = sum(w for w in widths if w)
        if total and total > text_w + 0.2:
            problems.append(f"table {i} is {total:.1f} cm wide, text column is {text_w:.1f} cm")
        if any(w == 0 for w in widths):
            problems.append(f"table {i} has a column with no explicit width")

    # --- images
    for i, sh in enumerate(doc.inline_shapes, 1):
        iw = cm(sh.width)
        if iw > text_w + 0.2:
            problems.append(f"figure {i} is {iw:.1f} cm wide, text column is {text_w:.1f} cm")

    # --- markdown survivors
    for p in doc.paragraphs:
        t = p.text
        for tok in MARKDOWN_LEFTOVERS:
            if tok in t:
                problems.append(f"markdown left in text: {tok!r} in {t[:60]!r}")
                break

    # --- structure
    heads = [p.text.strip() for p in doc.paragraphs if p.text.strip()]
    if any(h in REQUIRED_SECTIONS_EN for h in heads):
        missing = [x for x in REQUIRED_SECTIONS_EN if x not in heads]
    else:
        # the Chinese headings are numbered ("1  背景与概要"), so compare with the number stripped
        stripped = [re.sub(r"^\d+\s*", "", h) for h in heads]
        missing = [x for x in REQUIRED_SECTIONS_ZH
                   if not any(h.startswith(x) for h in stripped)]
    if missing:
        problems.append(f"missing sections: {missing}")

    return problems


def summarise(path: str) -> None:
    doc = Document(path)
    s = doc.sections[0]
    words = len(re.findall(r"[A-Za-z][A-Za-z'\u2019-]*|\d[\d,.]*",
                           " ".join(p.text for p in doc.paragraphs)))
    print(f"  {os.path.basename(path)}")
    print(f"    page      {cm(s.page_width):.1f} x {cm(s.page_height):.1f} cm; "
          f"margins {cm(s.top_margin):.1f}/{cm(s.left_margin):.1f}; text width "
          f"{cm(s.page_width) - cm(s.left_margin) - cm(s.right_margin):.1f} cm")
    print(f"    content   {len(doc.paragraphs)} paragraphs, {len(doc.tables)} tables, "
          f"{len(doc.inline_shapes)} figures, ~{words} words")
    if doc.tables:
        for i, t in enumerate(doc.tables, 1):
            print(f"    table {i}   {len(t.rows)} rows x {len(t.columns)} cols, "
                  f"width {sum(cm(c.width) for c in t.columns):.1f} cm")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not args:
        root = os.environ.get(
            "CHECO_ROOT",
            os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
        args = [os.path.join(root, "00_docs", "SUBMISSION", n)
                for n in ("CHECO26_manuscript.docx", "CHECO26_论文_中文.docx")]
    bad = 0
    print("=== document inspection ===")
    for path in args:
        if not os.path.exists(path):
            print(f"  missing: {path}")
            bad += 1
            continue
        summarise(path)
        problems = check(path)
        if problems:
            bad += 1
            for p in problems:
                print("    FAIL " + p)
        else:
            print("    OK")
    print(f"\n=== {len(args) - bad} of {len(args)} documents clean ===")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
