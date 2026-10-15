#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CHECO26 layer standardization -- minimal worked example.

Standardizes an arbitrary source raster onto the CHECO26 grid, following the
fixed, type-driven rules of the production pipeline
(`pipeline/scripts/common.py :: warp_to_template`):

  1. read the source raster (any CRS, any resolution);
  2. pick the resampling rule from the variable type
     (continuous -> bilinear, categorical -> nearest; fine-resolution sources
     are aggregated with average / mode);
  3. reproject + resample onto the CHECO26 grid
     (China_Albers, 1000 m, 4861 x 4062);
  4. clip to the China mask (cells outside the boundary become NoData);
  5. write the GeoTIFF with the standard profile (DEFLATE, tiled, BIGTIFF);
  6. verify alignment against the standard grid and print value statistics.

Usage:
    python standardization_example.py \
        --source ../../data/sample_layers/glo/bioclim/cnclim1km/present/bio01/glo_bioclim_cnclim1km_present_bio01.tif \
        --kind   continuous \
        --output standardized_bio01.tif
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
import rasterio
import yaml
from rasterio.enums import Resampling
from rasterio.warp import reproject

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, "config_example.yaml")
GRID = os.path.join(HERE, "..", "data", "CHECO26-standardgrid.tif")
MASK = os.path.join(HERE, "..", "data", "mask_china.tif")

_RESAMPLE = {
    "nearest": Resampling.nearest,
    "bilinear": Resampling.bilinear,
    "average": Resampling.average,
    "mode": Resampling.mode,
}


def load_config(path=CONFIG):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def grid_spec(cfg):
    """Template geometry: CRS / transform / width / height / resolution."""
    g = cfg["grid"]
    res = float(g["resolution"])
    from rasterio.transform import from_origin
    return dict(
        crs=g["crs_wkt"],
        transform=from_origin(g["xmin"], g["ymax"], res, res),
        width=int(round((g["xmax"] - g["xmin"]) / res)),
        height=int(round((g["ymax"] - g["ymin"]) / res)),
        res=res,
    )


def read_mask():
    with rasterio.open(MASK) as ds:
        return ds.read(1) == 1


def stats(arr):
    v = arr[np.isfinite(arr)] if arr.dtype.kind == "f" else arr[arr != arr.min()]
    return (int(v.size), float(v.min()), float(v.max())) if v.size else (0, None, None)


def standardize(src_path, kind, out_path, cfg, nodata=None, apply_mask=True):
    spec = grid_spec(cfg)
    out_dtype = "float32" if kind in ("continuous", "proportion", "distance") else "uint8"
    nd = cfg["nodata"]["float"] if out_dtype == "float32" else cfg["nodata"]["uint8_categorical"]
    if nodata is not None:
        nd = nodata
    fill = np.nan if out_dtype == "float32" else nd
    buf_dtype = np.float64 if out_dtype == "uint8" else out_dtype

    rule = cfg["resampling"]
    if kind in ("continuous", "proportion", "distance"):
        method = rule["continuous"] if kind == "continuous" else rule[kind]
    elif kind == "categorical":
        method = rule["categorical"]
    else:
        raise ValueError("kind must be continuous / categorical / proportion / distance")

    with rasterio.open(src_path) as src:
        src_res = abs(src.res[0])
        # fine-resolution source -> aggregate instead of interpolating
        if src_res < spec["res"] * 0.9:
            method = rule["downscale_continuous"] if kind != "categorical" \
                else rule["downscale_categorical"]
            print("source resolution %.1f m finer than template %.0f m -> %s"
                  % (src_res, spec["res"], method))
        dst = np.full((spec["height"], spec["width"]), fill, dtype=buf_dtype)
        reproject(
            source=rasterio.band(src, 1),
            destination=dst,
            dst_crs=spec["crs"],
            dst_transform=spec["transform"],
            dst_nodata=nd,
            src_nodata=src.nodata,
            resampling=_RESAMPLE[method],
        )
    out = dst.astype(out_dtype)

    if apply_mask:
        m = read_mask()
        out[~m] = fill
        print("China mask applied: %d of %d cells valid" % (int(m.sum()), m.size))

    profile = dict(driver="GTiff", width=spec["width"], height=spec["height"],
                   count=1, dtype=out_dtype, crs=spec["crs"],
                   transform=spec["transform"], nodata=nd,
                   compress="deflate", tiled=True, blockxsize=256,
                   blockysize=256, BIGTIFF="IF_SAFER")
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with rasterio.open(out_path, "w", **profile) as ds:
        ds.write(out, 1)
    return out, spec


def check_alignment(path, spec):
    with rasterio.open(path) as ds:
        return bool(
            rasterio.crs.CRS.from_user_input(ds.crs) ==
            rasterio.crs.CRS.from_user_input(spec["crs"])
            and ds.width == spec["width"] and ds.height == spec["height"]
            and ds.res == (spec["res"], spec["res"])
            and ds.transform.almost_equals(spec["transform"], 1e-6))


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True, help="source raster (any CRS)")
    ap.add_argument("--kind", default="continuous",
                    choices=["continuous", "categorical", "proportion", "distance"],
                    help="variable type -> resampling rule")
    ap.add_argument("--output", required=True, help="output GeoTIFF")
    ap.add_argument("--no-mask", action="store_true",
                    help="skip the China mask (not recommended)")
    args = ap.parse_args()

    cfg = load_config()
    with rasterio.open(args.source) as src:
        print("source : %s (%s, %.4f deg or m)" % (args.source, src.crs, abs(src.res[0])))
    out, spec = standardize(args.source, args.kind, args.output, cfg,
                            apply_mask=not args.no_mask)
    n, vmin, vmax = stats(out)
    print("output : %s" % args.output)
    print("         dtype=%s nodata=%s valid=%d min=%.6g max=%.6g"
          % (out.dtype, cfg["nodata"]["float"] if out.dtype.kind == "f"
             else cfg["nodata"]["uint8_categorical"], n, vmin or 0, vmax or 0))
    print("aligned with CHECO26-standardgrid.tif: %s"
          % check_alignment(args.output, spec))


if __name__ == "__main__":
    sys.exit(main())
