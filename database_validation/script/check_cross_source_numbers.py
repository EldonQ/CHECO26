#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Cross-source number audit for CHECO26.

The same facts appear in four places: the Chinese manuscript, the English draft,
the provenance table and the public repository. This script recomputes the
authoritative values from the delivery wherever it can, then checks that each
source it can reach carries the correct value and none of the retired ones.

Sources that cannot be located are reported as skipped, not as failures: the
repository and the delivery tree are separate checkouts and either may be absent.

Usage:
    CHECO_ROOT=/path/to/delivery CHECO_REPO=/path/to/repo \
        python check_cross_source_numbers.py
Exit code 0 when clean, 1 when a discrepancy is found, 2 when the delivery cannot
be located at all.
"""

from __future__ import annotations

import csv
import os
import re
import sys
from collections import Counter


def find_root(start: str, marker: str) -> str:
    """Walk up from `start` until a directory containing `marker` is found."""
    d = os.path.abspath(start)
    while True:
        if os.path.exists(os.path.join(d, marker)):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return ""
        d = parent


HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("CHECO_ROOT") or find_root(HERE, os.path.join("00_docs", "provenance_table.csv"))
REPO = os.environ.get("CHECO_REPO") or find_root(HERE, os.path.join("pipeline_r", "config.yaml"))

def under(root: str, *parts: str) -> str:
    """Join only when the root is known; otherwise return "" so the source is skipped."""
    return os.path.join(root, *parts) if root else ""


SOURCES = {
    "zh": under(ROOT, "00_docs", "SUBMISSION", "PAPER_ZH.md"),
    "en": under(ROOT, "00_docs", "SUBMISSION", "PAPER_EN_DRAFT.md"),
    "repo_readme": under(REPO, "README.md"),
    "repo_data_readme": under(REPO, "data", "README.md"),
    "repo_verify": under(REPO, "database_validation", "VERIFICATION_REPORT.md"),
}


def read(path: str) -> str:
    if not path or not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def authoritative() -> dict:
    """Recompute the headline numbers from the delivered evidence."""
    prov_path = os.path.join(ROOT, "00_docs", "provenance_table.csv")
    with open(prov_path, encoding="utf-8-sig") as fh:
        rows = list(csv.DictReader(fh))
    active = [r for r in rows if r["status"] == "active"]

    # byte sizes live in the manifest, not in the provenance table
    total_bytes = 0
    for cand in (os.path.join(ROOT, "00_docs", "MANIFEST.csv"),
                 os.path.join(ROOT, "audit", "layer_audit.csv")):
        if not os.path.exists(cand):
            continue
        with open(cand, encoding="utf-8-sig") as fh:
            man = list(csv.DictReader(fh))
        key = "relpath" if "relpath" in man[0] else "path"
        by_name: dict[str, int] = {}
        for r in man:
            if r.get("bytes"):
                nm = r[key].split("/")[-1]
                by_name[nm] = by_name.get(nm, 0) + int(r["bytes"])
        total_bytes = sum(by_name.get(r["layer_path"].split("/")[-1], 0) for r in active)
        break

    themes = Counter(r["layer_path"].split("/")[1] for r in active)
    datasets = {r["source_dataset"] for r in active}

    focal = prop = profile = extremes = topographic = 0
    for r in active:
        name = r["layer_path"].rsplit("/", 1)[-1]
        if re.search(r"_f\d+\.tif$", name):
            focal += 1
        elif name.endswith("_prop.tif"):
            prop += 1
        elif "_profile" in name:
            profile += 1
        elif name.endswith("_min.tif") or name.endswith("_max.tif"):
            extremes += 1
        elif name.endswith("_aspect.tif") or name.endswith("_tri.tif"):
            topographic += 1
    derived = focal + prop + profile + extremes + topographic

    lic: Counter = Counter()
    manifest = os.path.join(ROOT, "00_docs", "PUBLIC_RELEASE_MANIFEST.csv")
    published = 0
    if os.path.exists(manifest):
        with open(manifest, encoding="utf-8-sig") as fh:
            pub = list(csv.DictReader(fh))
        published = len(pub)
        lic = Counter((r["licence"] or "").strip() for r in pub)

    return {
        "layers": len(active),
        "provenance_rows": len(rows),
        "bytes": total_bytes,
        "gb": round(total_bytes / 1e9, 2),
        "themes": dict(themes),
        "datasets": len(datasets),
        "focal": focal,
        "prop": prop,
        "profile": profile,
        "extremes": extremes,
        "topographic": topographic,
        "derived": derived,
        "direct": len(active) - derived,
        "published": published,
        "licences": dict(lic),
    }


def check(name: str, must: list[str], must_not: list[str], texts: dict, only: tuple = ()) -> list:
    """`must` is a list of alternatives (any match passes); `must_not` must all be absent."""
    problems = []
    for key in (only or texts.keys()):
        t = texts.get(key, "")
        if not t:
            continue  # source not available in this checkout
        if must and not any(s in t for s in must):
            problems.append(f"{name}: {key} lacks any of {must!r}")
        for s in must_not:
            if s in t:
                problems.append(f"{name}: {key} still contains retired {s!r}")
    return problems


def main() -> int:
    if not ROOT or not os.path.exists(os.path.join(ROOT, "00_docs", "provenance_table.csv")):
        print("cannot locate the delivery tree; set CHECO_ROOT to the directory holding 00_docs/")
        return 2
    print(f"delivery  : {ROOT}")
    print(f"repository: {REPO or '(not found - repository sources will be skipped)'}")

    a = authoritative()
    texts = {k: read(v) for k, v in SOURCES.items()}
    skipped = [k for k, v in texts.items() if not v]

    print("\n=== authoritative values recomputed from the delivery ===")
    for k, v in a.items():
        print(f"  {k:18} {v}")

    problems: list[str] = []
    problems += check("layers", [f"{a['layers']:,}"], [], texts)
    problems += check("provenance rows", [f"{a['provenance_rows']:,}"], [], texts, only=("zh", "en"))
    problems += check("total size", ["170.9"], ["169.4"], texts)
    problems += check("derived split", [f"{a['derived']:,}", f"{a['direct']:,}"],
                      ["20,314", "796 (3.77"], texts, only=("zh", "en"))
    problems += check("focal layers", [f"{a['focal']:,}"], [], texts, only=("zh", "en"))
    problems += check("datasets", [f"{a['datasets']}"], [], texts)
    problems += check("mask cells", ["9,490,310"], [], texts, only=("zh", "en", "repo_data_readme"))
    problems += check("distinct hashes", ["14,050"], [], texts, only=("zh", "en"))
    problems += check("dedup size", ["134.9", "135.0"], ["133.5"], texts, only=("zh", "en", "repo_verify"))
    problems += check("glu1km uniqueness", ["465"], ["462"], texts, only=("zh", "en", "repo_verify"))
    problems += check("licence split", ["21,105", "21,025"], [], texts, only=("zh", "en"))
    problems += check("no results claim", [], ["the difference is the covariates"], texts, only=("zh", "en"))

    print("\n=== cross-source checks ===")
    if skipped:
        print("  skipped (not present in this checkout): " + ", ".join(skipped))
    if problems:
        for p in problems:
            print("  FAIL " + p)
        print(f"\n=== {len(problems)} problem(s) ===")
        return 1
    print("  all reachable sources agree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
