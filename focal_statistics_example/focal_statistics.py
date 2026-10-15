#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CHECO26 focal statistics -- worked example.

Computes the multi-scale focal-mean layers (`_f1000` ... `_f20000` suffixes)
that provide landscape context around every cell, using the corrected
equal-weight window implementation of the production pipeline
(`pipeline/scripts/common.py :: focal_mean`).

Window semantics on the 1-km grid (square windows, radius in cells):

    suffix    window    coverage      equivalent circle radius
    _f1000    3 x 3     3 km x 3 km   ~1.69 km
    _f5000    11 x 11   11 km x 11 km ~6.2 km
    _f10000   21 x 21   21 km x 21 km ~11.9 km
    _f20000   41 x 41   41 km x 41 km ~23.1 km

Note: `_f1000` is the *smallest multi-cell window* (3 x 3 cells), not a 1-km
radius disc -- a strict 1-km disc on a 1-km grid is degenerate.

The implementation guards the historical defect: a window that holds no valid
cell must output NoData. The validity test uses the exact float criterion
`c >= 0.5 / size^2` (c = window mean of the validity mask), verified against
exact integer counts for all four window sizes.

Usage:
    python focal_statistics.py \
        --source ../data/sample_layers/glo/bioclim/cnclim1km/present/bio01/glo_bioclim_cnclim1km_present_bio01.tif \
        --radius-km 5 \
        --output focal_bio01_f5000.tif
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
import rasterio
from scipy.ndimage import uniform_filter

HERE = os.path.dirname(os.path.abspath(__file__))
MASK = os.path.join(HERE, "..", "data", "mask_china.tif")
NODATA = -9999.0


def focal_mean(arr, radius_cells, invalid=None):
    """Equal-weight square-window mean with edge-NA adaptation."""
    if invalid is None:
        invalid = np.isnan(arr)
    valid = ~invalid
    a = np.where(valid, arr, 0.0).astype(np.float64)
    size = 2 * int(radius_cells) + 1
    s = uniform_filter(a, size=size, mode="constant", cval=0.0)
    c = uniform_filter(valid.astype(np.float32), size=size, mode="constant",
                       cval=0.0)
    out = np.full(arr.shape, np.nan, dtype=np.float32)
    ok = c >= 0.5 / float(size * size)   # window holds >= 1 valid cell
    out[ok] = (s[ok] / c[ok]).astype(np.float32)
    return out


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True)
    ap.add_argument("--radius-km", type=int, required=True,
                    choices=[1, 5, 10, 20])
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    radius_cells = args.radius_km  # 1 km grid -> radius in cells == radius in km
    size = 2 * radius_cells + 1

    with rasterio.open(args.source) as ds:
        base = ds.read(1).astype(np.float64)
        profile = ds.profile.copy()
        nd = ds.nodata
    if nd is not None:
        base[base == nd] = np.nan
    with rasterio.open(MASK) as ds:
        mask = ds.read(1) == 1

    b = base[np.isfinite(base)]
    bmin, bmax = float(b.min()), float(b.max())

    out = focal_mean(base, radius_cells)
    out[~mask] = np.nan

    v = out[np.isfinite(out)]
    vmin, vmax = float(v.min()), float(v.max())
    n_oor = int(((v < bmin - 1e-4) | (v > bmax + 1e-4)).sum())

    profile.update(dtype="float32", nodata=NODATA, compress="deflate",
                   tiled=True, blockxsize=256, blockysize=256,
                   BIGTIFF="IF_SAFER")
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with rasterio.open(args.output, "w", **profile) as ds:
        ds.write(np.where(np.isfinite(out), out, NODATA).astype(np.float32), 1)

    print("window            : %d x %d cells (%d km x %d km)"
          % (size, size, size, size * 1))
    print("base range        : [%.6g, %.6g]" % (bmin, bmax))
    print("focal range       : [%.6g, %.6g]" % (vmin, vmax))
    print("valid cells       : %d of %d" % (v.size, out.size))
    print("G1 out-of-range   : %d (must be 0)" % n_oor)
    print("output            : %s" % args.output)
    return 0 if n_oor == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
