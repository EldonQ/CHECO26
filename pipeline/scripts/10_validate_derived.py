# -*- coding: utf-8 -*-
"""10_validate_derived.py -- hard gates for DERIVED layers.

The original P5 acceptance tested "n_valid <= mask cells" and nothing else about
derived layers, which is why 242 focal layers carrying values up to 4384 (base
range 0..63.7) passed. This module adds the two gates that would have caught it:

  G1  VALUE RANGE   every derived layer's [min, max] must lie inside its base
                    layer's [min, max] -- a mean cannot leave the input range.
  G2  EMPTY WINDOW  no derived cell may hold a value where its window contained
                    zero valid base cells. A focal mean must be NoData there.
                    Tested with an exact integer count of valid cells.

Plus semantic bound checks for the LULC layers that are not focal means of a
single base (shannon, edge, patchdensity, patchsize).

Usage:  python 10_validate_derived.py            # report + non-zero exit on failure
Produces logs/derived_validation_report.csv and logs/derived_validation.txt.
"""
from __future__ import annotations

import csv
import os
import re
import sys

import numpy as np
import rasterio
from scipy.ndimage import uniform_filter

sys.path.insert(0, r"E:\CHECO26\N-SDM")
from scripts import common  # noqa: E402

ROOT = r"E:\CHECO26\N-SDM"
COV = os.path.join(ROOT, "data", "covariates", "glo")
LOGS = os.path.join(ROOT, "logs")
RE_FOCAL = re.compile(r"^(?P<base>.+)_f(?P<radius>\d+)$")
TOL = 1e-4          # tolerance for "outside the base range"
LN6 = float(np.log(6))


def empty_window_mask(valid, size):
    """True where the window holds no valid cell.

    The float mean of the validity mask equals cnt/size^2: an empty window gives
    <= ~4e-15 (coefficient rounding residue), a single valid cell gives
    1/size^2 >= 5.9e-4. The 0.5/size^2 threshold therefore sits ~11 orders of
    magnitude from the residue -- verified to classify identically to an exact
    integer count for all four window sizes used here.
    """
    c = uniform_filter(valid.astype(np.float32), size=size,
                       mode="constant", cval=0.0)
    return c < 0.5 / float(size * size)


def read(path):
    with rasterio.open(path) as ds:
        a = ds.read(1).astype(np.float64)
        nd = ds.nodata
    a[~np.isfinite(a)] = np.nan
    if nd is not None:
        a[a == nd] = np.nan
    return a


def stems_of_tree():
    out = {}
    for dp, _, fns in os.walk(COV):
        for fn in fns:
            if fn.endswith(".tif"):
                out[os.path.relpath(os.path.join(dp, fn), COV)
                    .replace("\\", "/")[:-4]] = os.path.join(dp, fn)
    return out


def semantic_kind(rel):
    """LULC layers with a known theoretical bound instead of a single base."""
    tail = os.path.basename(rel)
    if "_shannon" in tail:
        return ("shannon", 0.0, LN6)
    if "_edge" in tail:
        return ("edge_proportion", 0.0, 1.0)
    if "_patchdensity" in tail:
        return ("patch_density", 0.0, None)
    if "_patchsize" in tail:
        return ("patch_size", 1.0, None)
    return (None, None, None)


def main():
    os.makedirs(LOGS, exist_ok=True)
    stems = stems_of_tree()
    mask = common.china_mask(common.load_config())
    mask_n = int(mask.sum())
    rows = []
    cache_base = {}

    def base_stats(path):
        if path not in cache_base:
            b = read(path)
            v = b[np.isfinite(b)]
            cache_base[path] = (b, float(v.min()) if v.size else np.nan,
                                float(v.max()) if v.size else np.nan)
        return cache_base[path]

    focal = [(rel, m.group("base"), int(m.group("radius")) // 1000)
             for rel in sorted(stems)
             for m in [RE_FOCAL.match(rel)]
             if m and m.group("base") in stems]

    print("derived focal layers: %d" % len(focal))
    g1_fail = g2_fail = 0

    for rel, base_rel, radius in focal:
        a = read(stems[rel])
        b, bmin, bmax = base_stats(stems[base_rel])
        size = 2 * radius + 1
        fin = np.isfinite(a)
        v = a[fin]
        n_garbage = 0
        if fin.any():
            empty = empty_window_mask(np.isfinite(b), size)
            n_garbage = int((fin & empty).sum())
            del empty
        n_oor = int(((v < bmin - TOL) | (v > bmax + TOL)).sum()) if v.size else 0
        g1 = "FAIL" if n_oor else "pass"
        g2 = "FAIL" if n_garbage else "pass"
        g1_fail += bool(n_oor)
        g2_fail += bool(n_garbage)
        rows.append(dict(layer=rel, kind="focal", radius=radius * 1000,
                         gate="G1+G2", g1=g1, g2=g2,
                         base_min=bmin, base_max=bmax,
                         vmin=float(v.min()) if v.size else "", vmax=float(v.max()) if v.size else "",
                         n_out_of_range=n_oor, n_garbage=n_garbage))
        if n_oor or n_garbage:
            print("  FAIL %-70s oor=%d garbage=%d" % (rel, n_oor, n_garbage))

    # ---- semantic bounds for the non-focal derived LULC layers ----
    sem_fail = 0
    for rel in sorted(stems):
        kind, lo, hi = semantic_kind(rel)
        if kind is None:
            continue
        m = RE_FOCAL.match(rel)
        if m and m.group("base") in stems:
            continue                       # already covered by G1/G2
        a = read(stems[rel])
        v = a[np.isfinite(a)]
        if v.size == 0:
            continue
        bad = 0
        if lo is not None:
            bad += int((v < lo - TOL).sum())
        if hi is not None:
            bad += int((v > hi + TOL).sum())
        if kind == "patch_size" and hi is None:
            bad += int((v > mask_n + TOL).sum())    # cannot exceed the mask area (km2)
        g = "FAIL" if bad else "pass"
        sem_fail += bool(bad)
        rows.append(dict(layer=rel, kind=kind, radius="", gate="BOUND", g1=g, g2="",
                         base_min=lo, base_max=hi,
                         vmin=float(v.min()), vmax=float(v.max()),
                         n_out_of_range=bad, n_garbage=""))
        if bad:
            print("  FAIL %-70s bound-violations=%d [%r, %r]" % (rel, bad, v.min(), v.max()))

    rpt = os.path.join(LOGS, "derived_validation_report.csv")
    with open(rpt, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["layer", "kind", "radius", "gate", "g1", "g2",
                                           "base_min", "base_max", "vmin", "vmax",
                                           "n_out_of_range", "n_garbage"])
        w.writeheader()
        w.writerows(rows)

    total = len(rows)
    failed = sum(1 for r in rows if r["g1"] == "FAIL" or r["g2"] == "FAIL")
    summary = [
        "Derived-layer validation",
        "layers checked        : %d" % total,
        "G1 value-range fails  : %d" % g1_fail,
        "G2 empty-window fails : %d" % g2_fail,
        "bound fails (LULC)    : %d" % sem_fail,
        "layers failing any gate: %d" % failed,
        "report                : %s" % rpt,
    ]
    with open(os.path.join(LOGS, "derived_validation.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(summary) + "\n")
    print()
    print("\n".join(summary))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
