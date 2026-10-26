#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Run the whole verification chain from a clean environment and record the result.

Each step is invoked as a subprocess with CHECO_ROOT set, its exit code and the last
line of its output are recorded, and the transcript is written next to the delivery
docs so that a reader can see what a full pass looks like rather than only its
individual results.

Usage:
    python scripts/audit/run_full_verification.py [--skip-slow]
"""

from __future__ import annotations

import os
import subprocess
import sys
import time

ROOT = os.environ.get("CHECO_ROOT") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RSCRIPT = os.environ.get("CHECO_RSCRIPT", r"D:\R\R-4.4.3\bin\Rscript.exe")
PYTHON = os.environ.get("CHECO_PYTHON", sys.executable)
OUT = os.path.join(ROOT, "00_docs", "VERIFICATION_RUN.md")

# (label, command, slow?)
STEPS = [
    ("header audit V1/V2 (21,110 layers)", [PYTHON, r"scripts\audit\audit_data_quality.py"], True),
    ("composition identities", [PYTHON, r"scripts\audit\audit_composition.py"], True),
    ("focal nesting", [PYTHON, r"scripts\audit\check_focal_nesting.py"], True),
    ("independent re-derivation (16 checks)", [RSCRIPT, "--vanilla", r"R\tools\verify_independent.R"], True),
    ("provenance final (29 checks)", [PYTHON, r"scripts\audit\verify_provenance_final.py"], False),
    ("provenance columns (24)", [PYTHON, r"scripts\audit\provenance_column_audit.py"], False),
    ("documentation consistency (18)", [RSCRIPT, "--vanilla", r"R\tools\check_docs_consistency.R"], False),
    ("temporal consistency (39)", [RSCRIPT, "--vanilla", r"R\tools\check_trends.R"], False),
    ("table layer counts (17)", [RSCRIPT, "--vanilla", r"R\tools\check_table2.R"], False),
    ("cross-source numbers", [PYTHON, r"scripts\audit\check_cross_source_numbers.py"], False),
    ("mutation tests (20 cases)", [PYTHON, r"scripts\audit\test_audit_scripts.py"], False),
    ("R checker self-tests", [RSCRIPT, "--vanilla", r"R\tools\test_checkers.R"], False),
    ("submission package", [PYTHON, r"scripts\export_submission_package.py"], False),
]


def tail(text: str, n: int = 1) -> str:
    lines = [l.strip() for l in text.strip().splitlines() if l.strip()]
    return " | ".join(lines[-n:])[:160] if lines else "(no output)"


def main() -> int:
    skip_slow = "--skip-slow" in sys.argv
    env = dict(os.environ, CHECO_ROOT=ROOT, PYTHONIOENCODING="utf-8")
    rows = []
    print(f"delivery: {ROOT}\n")
    for label, cmd, slow in STEPS:
        if skip_slow and slow:
            rows.append((label, "skipped", 0.0, "slow step"))
            print(f"  {'skipped':8} {label}")
            continue
        t0 = time.time()
        try:
            p = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=7200)
            elapsed = time.time() - t0
            ok = p.returncode == 0
            note = tail(p.stdout + p.stderr)
            rows.append((label, "pass" if ok else "FAIL", elapsed, note))
            print(f"  {'pass' if ok else 'FAIL':8} {label}  ({elapsed:.0f}s)")
            if not ok:
                print(f"           {note}")
        except subprocess.TimeoutExpired:
            rows.append((label, "timeout", time.time() - t0, "exceeded 2 h"))
            print(f"  {'timeout':8} {label}")

    failed = [r for r in rows if r[1] == "FAIL"]
    print(f"\n{len(rows) - len(failed)} passed, {len(failed)} failed, "
          f"{sum(1 for r in rows if r[1] == 'skipped')} skipped")

    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# Full verification run\n\n")
        fh.write(f"Delivery root: `{ROOT}`\n\n")
        fh.write(f"Started: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        fh.write("| Step | Result | Time | Last line of output |\n|---|---|---:|---|\n")
        for label, res, el, note in rows:
            fh.write(f"| {label} | {res} | {el:.0f} s | {note.replace('|', '/')} |\n")
        fh.write(f"\n**{len(rows) - len(failed)} of {len(rows)} steps passed.**\n")
    print("written:", OUT)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
