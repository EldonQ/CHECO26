#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the database-validation result dataframes from the delivery.

The delivered archive ships three fact tables that together describe every
layer without re-reading 169 GB of rasters:

    00_docs/variable_dictionary.csv   per-layer unit, value_min, value_max, n_valid
    00_docs/MANIFEST.csv              per-file bytes and SHA-256
    00_docs/PUBLIC_RELEASE_MANIFEST.csv  per-layer licence class (21,105 rows)
    00_docs/RESTRICTED_LAYERS.csv     the 5 layers withheld from release

This script joins them into the two result dataframes the validation folder
publishes, so the numbers quoted in the README and in the figures can be traced
back to a delivered file rather than to a run log.

Outputs (default: ../result_dataframe/):
    per_layer_stats.csv        one row per delivered layer
    licence_summary.csv        layer counts per licence class

Usage:
    python make_result_dataframes.py --delivery <delivery-root> --outdir ../result_dataframe
"""
from __future__ import annotations

import argparse
import collections
import csv
import os

MASK_CELLS = 9490310            # valid cells inside the China mask
GRID_CELLS = 4861 * 4062        # 19,745,382


def read(path, **kw):
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f, **kw))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--delivery", required=True,
                    help="delivery root holding 00_docs/")
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args()

    docs = os.path.join(args.delivery, "00_docs")
    os.makedirs(args.outdir, exist_ok=True)

    dic = read(os.path.join(docs, "variable_dictionary.csv"))
    man = {r["relpath"]: r for r in read(os.path.join(docs, "MANIFEST.csv"))}
    pub = read(os.path.join(docs, "PUBLIC_RELEASE_MANIFEST.csv"))
    res = read(os.path.join(docs, "RESTRICTED_LAYERS.csv"))

    licence_of = {}
    for r in pub:
        key = r["relpath"].replace("covariates/", "", 1)
        licence_of[key] = (r["licence_class"], r["licence"], "released")
    for r in res:
        key = r["relpath"].replace("covariates/", "", 1)
        licence_of[key] = (r["licence_class"], r["licence"], "withheld")

    out = []
    for r in dic:
        rel = r["relpath"]
        m = man.get("covariates/" + rel, {})
        n_valid = int(float(r["n_valid"])) if r["n_valid"] not in ("", "NA") else 0
        lc, lic, status = licence_of.get(rel, ("", "", ""))
        out.append({
            "relpath": rel,
            "theme": r["theme"],
            "dataset": r["dataset"],
            "unit": r["unit"],
            "n_valid": n_valid,
            "na_frac": "%.6f" % (1.0 - n_valid / GRID_CELLS),
            "vmin": r["value_min"],
            "vmax": r["value_max"],
            "bytes": m.get("bytes", ""),
            "sha256": m.get("sha256", ""),
            "licence_class": lc,
            "licence": lic,
            "release_status": status,
        })
    out.sort(key=lambda r: r["relpath"])

    cols = ["relpath", "theme", "dataset", "unit", "n_valid", "na_frac",
            "vmin", "vmax", "bytes", "sha256",
            "licence_class", "licence", "release_status"]
    p1 = os.path.join(args.outdir, "per_layer_stats.csv")
    with open(p1, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(out)

    # licence summary at the level of the whole archive
    by_class = collections.Counter(r["licence_class"] for r in out)
    by_status = collections.Counter(r["release_status"] for r in out)
    p2 = os.path.join(args.outdir, "licence_summary.csv")
    with open(p2, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["group", "value", "layers"])
        for k, v in sorted(by_class.items()):
            w.writerow(["licence_class", k, v])
        for k, v in sorted(by_status.items()):
            w.writerow(["release_status", k, v])
        w.writerow(["total", "all", len(out)])

    print("per_layer_stats.csv : %d rows -> %s" % (len(out), p1))
    print("licence_summary.csv : %s" % p2)
    print("  by licence class:", dict(by_class))
    print("  by release status:", dict(by_status))
    missing = [r for r in out if not r["sha256"]]
    if missing:
        print("  WARNING: %d layers have no manifest digest" % len(missing))


if __name__ == "__main__":
    main()
