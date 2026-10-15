#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CHECO26 distance layers -- worked example.

Linear and areal features cannot enter a raster SDM stack as vectors; they are
converted to distance surfaces. The production pipeline
(`pipeline/scripts/05_derive_dist.py`) rasterizes the feature vectors onto the
CHECO26 grid (`all_touched=True`) and applies a Euclidean distance transform,
in metres:

    distance_transform_edt(feature == 0) * grid_resolution

Production tasks (17 delivered layers in the `dist` theme):
    GRIP4 roads           distance to the full road network
    GRIP4 major roads     distance to Highways + Primary + Secondary roads
    OSM trails            distance to paths / footways
    GHS-SMOD urban        distance to built-up cells (SMOD classes 21-23)
    JRC GSW water         distance to seasonal + permanent surface water
    Hydrography90m        distance to the nearest stream (proximity /
                          upstream-near / upstream-far / downstream-near),
                          aggregated to 1 km as mean / min / max

This self-contained example demonstrates the same computation without any
external vector data: the distance from every in-China cell to the national
boundary ("distance to the coast or border"), derived from the China mask.

Usage:
    python distance_layers.py --from-mask --output dist_to_boundary.tif

    # or from any binary feature raster (1 = feature, 0 = background):
    python distance_layers.py --source feature.tif --output dist.tif
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
import rasterio
from scipy.ndimage import distance_transform_edt

HERE = os.path.dirname(os.path.abspath(__file__))
MASK = os.path.join(HERE, "..", "data", "mask_china.tif")
GRID = os.path.join(HERE, "..", "data", "CHECO26-standardgrid.tif")
NODATA = -9999.0


def distance_surface(feature, resolution):
    """Euclidean distance (metres) from every background cell to the
    nearest feature cell; feature cells themselves are 0."""
    return (distance_transform_edt(feature == 0) * float(resolution)).astype(np.float32)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", help="binary feature raster (1 = feature)")
    ap.add_argument("--from-mask", action="store_true",
                    help="demo mode: distance to the national boundary")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    if not (args.source or args.from_mask):
        ap.error("provide --source or --from-mask")

    with rasterio.open(GRID) as ds:
        resolution = abs(ds.res[0])
        profile = ds.profile.copy()

    if args.from_mask:
        with rasterio.open(MASK) as ds:
            mask = ds.read(1) == 1
        feature = ~mask  # target cells = outside China
    else:
        with rasterio.open(args.source) as ds:
            feature = ds.read(1) == 1
        with rasterio.open(MASK) as ds:
            mask = ds.read(1) == 1

    dist = distance_surface(feature, resolution)
    dist[~mask] = NODATA  # every delivered layer is clipped to China
    valid = dist[dist != NODATA]
    print("resolution        : %.0f m" % resolution)
    print("target cells      : %d of %d" % (int((~mask).sum()), mask.size))
    print("distance range    : [%.1f, %.1f] m" % (valid.min(), valid.max()))

    profile.update(dtype="float32", nodata=NODATA, compress="deflate",
                   tiled=True, blockxsize=256, blockysize=256,
                   BIGTIFF="IF_SAFER")
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with rasterio.open(args.output, "w", **profile) as ds:
        ds.write(dist, 1)
    print("output            : %s" % args.output)


if __name__ == "__main__":
    sys.exit(main())
