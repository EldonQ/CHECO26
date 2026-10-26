#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Composition-identity audit: do the land-cover proportions sum to 1?

Every delivered `_prop` layer belongs to a group (product, year[, scenario]) whose
members are the classes of one categorical source. Where a source was one-hot
encoded and area-weighted, the members of a group must sum to 1 in every valid
cell, up to float32 representation.

This reads each group once, accumulating a running sum so a nine-class group never
holds nine rasters in memory at the same time.

Output: audit/composition_identity.csv, one row per group, plus a printed verdict.
A group with a member that fails to open is reported, not skipped.
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np
import rasterio

ROOT = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
COV = os.path.join(ROOT, "data", "covariates", "glo")
AUD = os.path.join(ROOT, "audit")
NODATA = np.float32(-9999.0)

TOL_STRICT = 1e-6
TOL_LOOSE = 1e-3


def group_key(rel):
    """(dataset, year, scenario) for a base proportion layer, or None.

    `rel` is relative to COV_ROOT, which already consumes the leading `glo/`
    level, so parts[0] is the theme and parts[1] the dataset. Only base layers
    count: a focal variant (``_prop_f1000``) is a window mean and does not sum to
    1 across classes, so including it would make every group fail by construction.
    """
    parts = rel.split("/")
    fname = parts[-1]
    if not fname.endswith("_prop.tif"):
        return None
    # scenario form: <theme>/<dataset>/scenario/<year>/<ssp>/<class>/file
    if len(parts) >= 7 and parts[2] == "scenario":
        return (parts[1], parts[3], parts[4])
    # plain form: <theme>/<dataset>/<year>/<class>/file
    if len(parts) >= 5 and re.fullmatch(r"\d{4}", parts[2]):
        return (parts[1], parts[2], "NA")
    return None


def work(job):
    key, rels = job
    ds, year, ssp = key
    acc = None
    n_layers = 0
    err = ""
    for rel in rels:
        p = os.path.join(COV, rel.replace("/", os.sep))
        try:
            with rasterio.open(p) as s:
                a = s.read(1)
        except Exception as e:
            err = "%s: %s" % (os.path.basename(rel), type(e).__name__)
            continue
        a = np.where(a == NODATA, np.float32(0), a)
        if acc is None:
            acc = a.astype(np.float64)
        else:
            acc += a
        n_layers += 1
    if acc is None:
        return {"dataset": ds, "year": year, "scenario": ssp, "n_layers": 0,
                "n_classes": len(rels), "n_cells": 0, "max_abs_dev": "",
                "p99_abs_dev": "", "n_off_1e-6": "", "n_off_1e-3": "",
                "sum_mean": "", "error": err}

    dev = acc - 1.0
    inside = acc > 0                     # cells where at least one class is present
    n_cells = int(inside.sum())
    if n_cells == 0:
        # A group with no inspectable cell used to report max|sum-1| = 0, which reads
        # as a perfect group. Nothing was checked, so nothing may be reported as fine.
        return {"dataset": ds, "year": year, "scenario": ssp,
                "n_layers": n_layers, "n_classes": len(rels), "n_cells": 0,
                "max_abs_dev": "", "p99_abs_dev": "", "n_off_1e-6": "",
                "n_off_1e-3": "", "sum_mean": "",
                "error": "no_cells_inspected"}
    d = np.abs(dev[inside])
    return {
        "dataset": ds, "year": year, "scenario": ssp,
        "n_layers": n_layers, "n_classes": len(rels),
        "n_cells": n_cells,
        "max_abs_dev": float(d.max()),
        "p99_abs_dev": float(np.percentile(d, 99)),
        "n_off_1e-6": int((d > TOL_STRICT).sum()),
        "n_off_1e-3": int((d > TOL_LOOSE).sum()),
        "sum_mean": float(acc[inside].mean()) if n_cells else "",
        "error": err,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--out", default=os.path.join(AUD, "composition_identity.csv"))
    args = ap.parse_args()

    groups = {}
    for dp, dn, fn in os.walk(COV):
        for f in fn:
            if not (f.endswith(".tif") and not f.endswith(".tmp.tif")):
                continue
            rel = os.path.relpath(os.path.join(dp, f), COV).replace("\\", "/")
            k = group_key(rel)
            if k:
                groups.setdefault(k, []).append(rel)

    jobs = [(k, sorted(v)) for k, v in sorted(groups.items())]
    print("proportion layers: %d in %d groups; workers %d"
          % (sum(len(v) for _, v in jobs), len(jobs), args.workers), flush=True)

    rows = []
    t0 = time.time()
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(work, j) for j in jobs]
        for i, fut in enumerate(as_completed(futs), 1):
            rows.append(fut.result())
            if i % 100 == 0:
                print("  %d/%d groups, %.1f min" % (i, len(jobs),
                      (time.time() - t0) / 60), flush=True)

    rows.sort(key=lambda r: (r["dataset"], r["year"], r["scenario"]))
    cols = ["dataset", "year", "scenario", "n_layers", "n_classes", "n_cells",
            "max_abs_dev", "p99_abs_dev", "n_off_1e-6", "n_off_1e-3", "sum_mean", "error"]
    os.makedirs(AUD, exist_ok=True)
    with open(args.out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    bad = [r for r in rows if r["error"] or (r["n_off_1e-3"] not in ("", 0))]
    by_ds = {}
    for r in rows:
        by_ds.setdefault(r["dataset"], []).append(r["max_abs_dev"] if r["max_abs_dev"] != "" else 0.0)

    print("\n=== composition identity ===")
    for ds, v in sorted(by_ds.items()):
        print("  %-10s groups %4d  max |sum-1| %.3e  median %.3e"
              % (ds, len(v), max(v), float(np.median(v))))
    print("  groups failing 1e-3: %d / %d" % (len(bad), len(rows)))
    for r in bad[:10]:
        print("    %s %s %s  max=%.3e  err=%s"
              % (r["dataset"], r["year"], r["scenario"], r["max_abs_dev"] or 0, r["error"]))
    print("written:", args.out)


if __name__ == "__main__":
    main()
