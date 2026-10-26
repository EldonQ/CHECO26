#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Source-to-delivery fidelity check at the level of individual cells.

For a fixed random sample of valid China cells, this reads the value in the
original source product and in the delivered CHECO26 layer, and reports the
correlation and the mean absolute difference. It answers one question the format
audit cannot: did the delivered layer keep the source's values through
reprojection, rescaling and masking?

Each pair declares the scale factor the ingest applied (`/100` where the source
stores hundredths, `-` where the source is already in target units). Getting that
declaration wrong shows up immediately as a large bias, which is how the DEM row
was caught during the first manual run of this check.

Output: audit/source_fidelity.csv
"""
from __future__ import annotations

import csv
import os
import sys

import numpy as np
import rasterio
from rasterio.warp import transform as rio_transform
from rasterio.crs import CRS

ROOT = os.environ.get("CHECO_ROOT", os.getcwd())
# The source rasters this check compares against are not part of the repository or the
# delivery; point CHECO_SRC at the directory that holds them (DEM/, CSDLv2/, Bioclim/).
SRC = os.environ.get("CHECO_SRC", "")
AUD = os.path.join(ROOT, "audit")
COV = os.path.join(ROOT, "data", "covariates", "glo")
MASK = os.path.join(ROOT, "data", "mask_china.tif")
ALBERS = ("+proj=aea +lat_0=0 +lon_0=105 +lat_1=25 +lat_2=47 "
          "+datum=WGS84 +units=m +no_defs")
SEED = 20261025
N_POINTS = 3000

# (label, source path, delivered path relative to COV, scale, offset)
PAIRS = [
    ("topo/elev",
     os.path.join(SRC, "DEM", "China_DEM_1km", "Albers_105", "DEM", "chdem_105.tif"),
     "topo/chinadem/elev/glo_topo_chinadem_elev.tif", 1.0, 0.0),
    ("soil/ph_0_5",
     os.path.join(SRC, "CSDLv2", "1km", "GTiff", "pH", "pH_0-5cm_1km.tif"),
     "soil/csdlv2/ph/0/glo_soil_csdlv2_ph_0.tif", 0.01, 0.0),
    ("anthro/hfp_2000",
     os.path.join(ROOT, "archive", "hfp", "HFP-2000-2018", "16571064",
                  "hfp2000", "hfp2000.tif"),
     "anthro/hfp/2000/hfp/glo_anthro_hfp_2000_hfp.tif", 1.0, 0.0),
    ("bioclim/bio01_present",
     os.path.join(SRC, "Bioclim", "CHNECO26_Bioclim", "bioclim", "cnclim1km", "present",
                  "1991_2020", "bio01", "bioclim_cnclim1km_present_1991_2020_bio01.tif"),
     "bioclim/cnclim1km/present/bio01/glo_bioclim_cnclim1km_present_bio01.tif",
     1.0, 0.0),
    ("bioclim/bio12_present",
     os.path.join(SRC, "Bioclim", "CHNECO26_Bioclim", "bioclim", "cnclim1km", "present",
                  "1991_2020", "bio12", "bioclim_cnclim1km_present_1991_2020_bio12.tif"),
     "bioclim/cnclim1km/present/bio12/glo_bioclim_cnclim1km_present_bio12.tif",
     1.0, 0.0),
]


def main():
    rng = np.random.default_rng(SEED)
    with rasterio.open(MASK) as s:
        m = s.read(1)
        tr = s.transform
    idx = np.flatnonzero(m.ravel() == 1)
    pick = rng.choice(idx, N_POINTS, replace=False)
    rows, cols = np.unravel_index(pick, m.shape)
    xs, ys = tr * (cols + 0.5, rows + 0.5)

    out = []
    for label, sp, drel, scale, offset in PAIRS:
        dp = os.path.join(COV, drel.replace("/", os.sep))
        if not (os.path.exists(sp) and os.path.exists(dp)):
            out.append({"layer": label, "n": 0, "r": "", "mean_abs_diff": "",
                        "mean_bias": "", "src_min": "", "src_max": "",
                        "dst_min": "", "dst_max": "", "note": "missing path"})
            print("  %-24s SKIP (source or delivery missing)" % label)
            continue
        with rasterio.open(sp) as s:
            sx, sy = rio_transform(CRS.from_proj4(ALBERS), s.crs,
                                   xs.tolist(), ys.tolist())
            sv = np.array([v[0] for v in s.sample(zip(sx, sy))], dtype="float64")
        with rasterio.open(dp) as s2:
            dv = np.array([v[0] for v in s2.sample(zip(xs.tolist(), ys.tolist()))],
                          dtype="float64")
            dnd = s2.nodata
        ok = (np.isfinite(sv) & (sv > -1e30) & np.isfinite(dv)
              & (dv != (dnd if dnd is not None else -1e30)))
        a = sv[ok] * scale + offset
        b = dv[ok]
        r = float(np.corrcoef(a, b)[0, 1]) if len(a) > 2 else float("nan")
        rec = {"layer": label, "n": int(len(a)), "r": round(r, 6),
               "mean_abs_diff": round(float(np.mean(np.abs(b - a))), 6),
               "mean_bias": round(float(np.mean(b - a)), 6),
               "src_min": round(float(a.min()), 4), "src_max": round(float(a.max()), 4),
               "dst_min": round(float(b.min()), 4), "dst_max": round(float(b.max()), 4),
               "note": ""}
        out.append(rec)
        print("  %-24s n=%4d  r=%.5f  MAD=%.4f  bias=%+.4f"
              % (label, len(a), r, rec["mean_abs_diff"], rec["mean_bias"]))

    os.makedirs(AUD, exist_ok=True)
    p = os.path.join(AUD, "source_fidelity.csv")
    with open(p, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)
    print("written:", p)


if __name__ == "__main__":
    main()
