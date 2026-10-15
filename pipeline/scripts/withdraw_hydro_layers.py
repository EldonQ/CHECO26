# -*- coding: utf-8 -*-
"""withdraw_hydro_layers.py -- move the source-defective hydro layers out of the
delivery tree into an archive, with a reversible manifest.

Withdrawn (8 layers): the Hydrography90m variables whose SOURCE values are
unusable -- verified by reprojecting the source with the pipeline's own rule and
reproducing the shipped values bit for bit, so re-running cannot fix them:

    cti                      source int32 [-5.65e8, 1.87e9]; ln(a/tan b) cannot
                             reach that magnitude (99.7% of cells negative)
    channel-grad-dw-seg      source int32 max 1.42e9 cm/m vs physical limit 100
    channel-grad-up-cel      same
    channel-grad-up-seg      same
    slope-curv-max-dw-cel    source int32 saturated at +/-384900 in 1/m
    slope-curv-min-dw-cel    same
    accumulation             source km2 flow accumulation contains negatives
    accumulation_max         derived from the same defective source

Nothing is deleted: files are MOVED to archive/withdrawn_source_defective/ keeping
their relative path, and every move is written to a manifest so it can be undone.

Usage:
  python withdraw_hydro_layers.py            # dry run
  python withdraw_hydro_layers.py --apply
  python withdraw_hydro_layers.py --rollback
"""
from __future__ import annotations

import argparse
import csv
import os
import shutil

ROOT = r"E:\CHECO26\N-SDM"
COV = os.path.join(ROOT, "data", "covariates", "glo")
DEST = os.path.join(ROOT, "archive", "withdrawn_source_defective")
MANIFEST = os.path.join(ROOT, "logs", "withdrawn_layers_manifest.csv")

TARGETS = [
    r"hydro\h90m\cti\glo_hydro_h90m_cti.tif",
    r"hydro\h90m\channel-grad-dw-seg\glo_hydro_h90m_channel-grad-dw-seg.tif",
    r"hydro\h90m\channel-grad-up-cel\glo_hydro_h90m_channel-grad-up-cel.tif",
    r"hydro\h90m\channel-grad-up-seg\glo_hydro_h90m_channel-grad-up-seg.tif",
    r"hydro\h90m\slope-curv-max-dw-cel\glo_hydro_h90m_slope-curv-max-dw-cel.tif",
    r"hydro\h90m\slope-curv-min-dw-cel\glo_hydro_h90m_slope-curv-min-dw-cel.tif",
    r"hydro\h90m\accumulation\glo_hydro_h90m_accumulation.tif",
    r"hydro\h90m\accumulation\glo_hydro_h90m_accumulation_max.tif",
]


def move(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.move(src, dst)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--rollback", action="store_true")
    args = ap.parse_args()

    if args.rollback:
        if not os.path.exists(MANIFEST):
            print("no manifest at %s" % MANIFEST)
            return 1
        n = 0
        for row in csv.DictReader(open(MANIFEST, encoding="utf-8")):
            src, dst = row["original"], row["archived"]
            if os.path.exists(dst):
                move(dst, src)
                n += 1
                print("restored %s" % os.path.relpath(src, ROOT))
        print("rolled back %d layers" % n)
        return 0

    print("withdrawing %d layers%s" % (len(TARGETS), "" if args.apply else "  (DRY RUN)"))
    rows = []
    total = 0
    for rel in TARGETS:
        src = os.path.join(COV, rel)
        dst = os.path.join(DEST, rel)
        if not os.path.exists(src):
            print("  MISSING (already withdrawn?) %s" % rel)
            continue
        total += os.path.getsize(src)
        print("  %-72s %10.1f MB -> archive" % (os.path.basename(rel),
                                                 os.path.getsize(src) / 1e6))
        rows.append(dict(original=src, archived=dst,
                         relpath=rel.replace("\\", "/"), bytes=os.path.getsize(src)))
        if args.apply:
            move(src, dst)

    if args.apply and rows:
        os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
        with open(MANIFEST, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=["relpath", "original", "archived", "bytes"])
            w.writeheader()
            w.writerows(rows)
        print("\nmoved %d layers (%.0f MB) -> %s"
              % (len(rows), total / 1e6, os.path.relpath(DEST, ROOT)))
        print("manifest -> %s" % MANIFEST)
        print("rollback : python withdraw_hydro_layers.py --rollback")
    else:
        print("\ntotal %.0f MB ; pass --apply to move" % (total / 1e6))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
