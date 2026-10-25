#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Full-library integrity validation for the CHECO26 raster database.

Self-contained re-implementation of the production acceptance gates
(the v1.0 ``scripts/08_validate.py``), driven only by the public artefacts in
this repository:

  * ``data/CHECO26_datalayers_details.csv`` -- the layer manifest
  * ``data/CHECO26-standardgrid.tif``       -- the template grid
  * ``data/mask_china.tif``                 -- the China mask

Gates (all hard, all must pass for a delivery):

  G0  EXISTENCE   every manifest layer exists on disk; no extra .tif
  G1  ALIGNMENT   CRS / resolution / extent / grid origin match the template
  G2  MASK        no layer has more valid cells than the China mask
  G3  NAMING      folder names carry no underscore; file name = folder names
                  joined by underscores + allowed suffix; depth 4-7; unique
  G4  VALUES      per-layer dtype / nodata / valid-cell count / NA fraction /
                  min / max are recorded for downstream reporting

Usage:
    python database_validation.py \
        --root      path/to/covariates_tree   (directory containing glo/) \
        --manifest  ../../data/CHECO26_datalayers_details.csv \
        --grid      ../../data/CHECO26-standardgrid.tif \
        --mask      ../../data/mask_china.tif \
        --output    validation_report.csv
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import sys

import numpy as np
import rasterio

# allowed file-name suffixes: derivation + focal radius (metres) + window stat
SUFFIX_RE = re.compile(
    r"^(_prop|_shannon|_edge|_profile|_patchdensity-(all|forest)|"
    r"_patchsize-(all|forest))?(_f\d+)*(_mean|_sd|_min|_max)?$")

MANIFEST_COLS = ["category", "dataset", "variable", "period", "scenario",
                 "sub_period", "start_year", "end_year", "attribute", "focal",
                 "variable_long", "unit", "path", "valid"]


def load_manifest(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f, delimiter=";"))
    if not rows:
        sys.exit("empty manifest: %s" % path)
    return [r["path"].lstrip("./") for r in rows]


def grid_spec(grid_path):
    with rasterio.open(grid_path) as ds:
        return dict(crs=ds.crs, width=ds.width, height=ds.height,
                    res=ds.res, transform=ds.transform)


def scan_tree(root):
    out = {}
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn.endswith(".tif"):
                full = os.path.join(dp, fn)
                out[os.path.relpath(full, root).replace("\\", "/")] = full
    return out


def check_alignment(path, spec):
    with rasterio.open(path) as ds:
        return bool(
            rasterio.crs.CRS.from_user_input(ds.crs) ==
            rasterio.crs.CRS.from_user_input(spec["crs"])
            and ds.width == spec["width"]
            and ds.height == spec["height"]
            and ds.res == spec["res"]
            and ds.transform.almost_equals(spec["transform"], 1e-6))


def layer_stats(path):
    with rasterio.open(path) as ds:
        a = ds.read(1)
        nod = ds.nodata
        dty = ds.dtypes[0]
    valid = ~np.isnan(a) if a.dtype.kind == "f" else np.ones(a.shape, bool)
    if nod is not None:
        valid &= (a != nod)
    v = a[valid]
    return dict(dtype=dty, nodata=str(nod), n_valid=int(v.size),
                na_frac=round(1.0 - v.size / float(a.size), 4),
                vmin=float(v.min()) if v.size else "",
                vmax=float(v.max()) if v.size else "")


def validate_naming(root):
    errors = []
    seen = set()
    for dp, dns, fns in os.walk(root):
        for d in dns:
            if "_" in d:
                errors.append("folder has underscore: %s" % os.path.join(dp, d))
        for fn in fns:
            if not fn.endswith(".tif"):
                continue
            full = os.path.join(dp, fn)
            parts = os.path.relpath(dp, root).split(os.sep)
            depth = len([p for p in parts if p != "scenario"]) + 1
            if not (4 <= depth <= 7):
                errors.append("depth %d out of 4-7: %s" % (depth, full))
            stem = fn[:-4]
            prefix = "_".join(parts)
            if not stem.startswith(prefix):
                errors.append("filename not prefix-joined: %s" % full)
            elif not SUFFIX_RE.match(stem[len(prefix):]):
                errors.append("illegal suffix: %s" % full)
            if fn in seen:
                errors.append("duplicate filename: %s" % fn)
            seen.add(fn)
    return errors


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", required=True,
                    help="covariates tree root (the directory containing glo/)")
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--grid", required=True)
    ap.add_argument("--mask", required=True)
    ap.add_argument("--output", default="validation_report.csv")
    args = ap.parse_args()

    spec = grid_spec(args.grid)
    with rasterio.open(args.mask) as ds:
        m = ds.read(1)
    mask_n = int((m == 1).sum())

    expected = set(load_manifest(args.manifest))
    disk = scan_tree(args.root)
    missing = sorted(expected - set(disk))
    extra = sorted(set(disk) - expected)
    print("expected=%d disk=%d missing=%d extra=%d"
          % (len(expected), len(disk), len(missing), len(extra)))

    rows, bad_align, over_mask = [], [], []
    for i, rel in enumerate(sorted(expected), 1):
        path = os.path.join(args.root, *rel.split("/"))
        try:
            aligned = check_alignment(path, spec)
            st = layer_stats(path)
            st.update(relpath=rel, aligned=aligned, error="")
        except Exception as e:  # noqa: BLE001 - report and continue
            aligned, st = False, dict(relpath=rel, aligned=False, dtype="",
                                      nodata="", n_valid="", na_frac="",
                                      vmin="", vmax="", error=str(e))
        if not aligned:
            bad_align.append(rel)
        if st["n_valid"] != "" and st["n_valid"] > mask_n:
            over_mask.append(rel)
        rows.append(st)
        if i % 200 == 0:
            print("checked %d/%d" % (i, len(expected)))

    naming = validate_naming(args.root)

    with open(args.output, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["relpath", "aligned", "dtype", "nodata",
                                          "n_valid", "na_frac", "vmin", "vmax",
                                          "error"])
        w.writeheader()
        w.writerows(rows)

    print("alignment failures : %d" % len(bad_align))
    print("over-mask layers   : %d (mask valid cells=%d)" % (len(over_mask), mask_n))
    print("naming errors      : %d" % len(naming))
    print("report             : %s" % args.output)

    ok = not (missing or extra or bad_align or over_mask or naming)
    print("VALIDATION %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
