# -*- coding: utf-8 -*-
"""enrich_provenance.py -- enrich 00_docs/provenance_table.csv after R/13_make_provenance.R.

`R/13_make_provenance.R` writes the three newest datasets (anthro/hfp, lulc/clcd,
lulc/hlu1km) with `source_file = NA` and without an evidence grade, because `mk_row()`
has no argument for either. This script adds them, and records the time-invariance finding
for two of the classes. It is idempotent: run it as often as you like.

What it writes, and the evidence for each:

  source_file    The path patterns are the ones the ingest scripts actually read:
                   R/04_ingest_timeseries.R:40-43   hfp<YYYY>/hfp<YYYY>.tif
                   R/06_derive_lulc_clcd.R:24,34    CLCD_v01_<YYYY>_albert.tif
                   R/07_derive_lulc_hlu1km.R:26-43  <SSP>_country-f.tif, band = year-1959,
                                                    historic read from SSP1_RCP26
                 Every generated path is checked to exist before it is written.

  evidence grade Land-cover class layers in this table are graded [doc] (all 540 glu1km
                 rows are), and the class code is appended from the legend the product
                 ships with. Keep [proc] on documented CHECO26 derivations.
                 Legends are in archive/harmonised/Harmonised-1960-2100/README.md for hlu1km
                 and the CLCD v1.0.5 legend for clcd.

  note (urban)   Time-invariant: 400 scenario layers byte-identical, equal to 2020,
                 61 distinct fields over 461 instances; source holds 281,450 urban cells
                 at 2021/2050/2070/2100.

  note (water)   Near time-invariant: exactly two distinct fields over 461 instances
                 (425 / 36); scenario split 367 / 33; historic split 58 years / 2005, 2006,
                 2009. Source holds 362,271 water cells at 2021 and 2100.

  *_max/*_min    The 19 layers with a `_max` or `_min` suffix are produced with
                 config.yaml:hydro_stats_addon (minmax / maxonly) through GDAL min/max, so
                 their processing_steps must say so. Numeric nesting max >= base >= min
                 holds for all of them, which is why this is a text fix and not a data fix.

Run:
  E:\\CHECO26\\.venv\\Scripts\\python.exe scripts\\enrich_provenance.py [--check]

  --check  report what would change, write nothing
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import shutil
import sys

ROOT = os.environ.get("CHECO_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLE = os.path.join(ROOT, "00_docs", "provenance_table.csv")
ARCH = os.path.join(ROOT, "archive")

HLU_SSP = {"ssp126": "SSP1_RCP26", "ssp245": "SSP2_RCP45", "ssp370": "SSP3_RCP70",
           "ssp460": "SSP4_RCP60", "ssp585": "SSP5_RCP85"}
HLU_LEGEND = {"urban": (11, "Urban"), "cropland": (22, "Cropland"),
              "pasture": (33, "Pasture/rangeland"), "mngforest": (441, "Managed forest"),
              "forest": (442, "Unmanaged forest"),
              "grassshrub": (55, "Unmanaged grass/shrubland"),
              "sparse": (66, "Sparse/no vegetation"), "water": (77, "Water")}
CLCD_LEGEND = {"cropland": (1, "Cropland"), "forest": (2, "Forest"), "shrub": (3, "Shrub"),
               "grassland": (4, "Grassland"), "water": (5, "Water"),
               "snowice": (6, "Snow/Ice"), "barren": (7, "Barren"),
               "impervious": (8, "Impervious"), "wetland": (9, "Wetland")}

MARK = "TIME-INVARIANT IN THE SOURCE"
MARK2 = "NEAR TIME-INVARIANT IN THE SOURCE"
NOTE_URBAN = (
    " | " + MARK + ": the harmonised LULC product holds the urban "
    "class fixed over the whole future projection. Measured on the delivered archive "
    "(MANIFEST.csv SHA-256): all 400 scenario layers (80 years x 5 SSPs) are "
    "byte-identical, that field is also identical to the 2020 layer, and the other 60 "
    "historic years each differ -- 61 distinct fields over the 461 layer-year-scenario "
    "instances of 1960-2100. Measured on the source: the China window holds 281,450 "
    "urban cells unchanged at 2021, 2050, 2070 and 2100. Do not use this layer as a "
    "time-varying predictor for the future period.")
NOTE_WATER = (
    " | " + MARK2 + ": the harmonised LULC product changes the "
    "water class only marginally. Measured on the delivered archive (MANIFEST.csv "
    "SHA-256): the whole 1960-2100 series takes exactly two distinct fields -- one "
    "covers 425 of the 461 layer-year-scenario instances, the other 36. Within the "
    "scenario segment the split is 367 / 33 files; within the historic segment it is "
    "58 years / 3 years (2005, 2006 and 2009 differ from the rest). Measured on the "
    "source: the China window holds 362,271 water cells at both 2021 and 2100. The "
    "temporal signal is very weak; do not rely on this layer as a time-varying "
    "predictor.")


def parse_hlu(path):
    """(year, ssp, class). Historic is <year>/<class>; scenario adds two levels."""
    p = path.split("/")
    if p[3] == "scenario":
        return p[4], p[5], p[6]
    return p[3], None, p[4]


def src_hfp(y):
    return os.path.join(ARCH, "hfp", "HFP-2000-2018", "16571064", f"hfp{y}", f"hfp{y}.tif").replace("\\", "/")


def src_clcd(y):
    return os.path.join(ARCH, "clcd-albert", f"CLCD_v01_{y}_albert.tif").replace("\\", "/")


def src_hlu(y, ssp):
    key = "SSP1_RCP26" if ssp is None else HLU_SSP[ssp]
    f = os.path.join(ARCH, "harmonised", "Harmonised-1960-2100", f"{key}_country-f.tif").replace("\\", "/")
    band = int(y) - 1959
    note = "" if ssp is not None else (
        " (historic segment; the five scenario files are byte-identical over 1960-2020)")
    return "%s (band %d = year %s)%s" % (f, band, y, note)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    rows = list(csv.DictReader(open(TABLE, encoding="utf-8-sig")))
    cols = list(rows[0].keys())
    n0 = len(rows)
    c1 = c2 = c6 = c8 = 0
    unresolved = []

    for r in rows:
        p = r["layer_path"].split("/")
        ds = "/".join(p[1:3])

        # ---- source_file
        if (r["source_file"] or "").strip() in ("NA", ""):
            chk = None
            if ds == "anthro/hfp":
                r["source_file"] = "[path] " + src_hfp(p[3])
                chk = os.path.join(ARCH, "hfp", "HFP-2000-2018", "16571064",
                                   "hfp" + p[3], "hfp" + p[3] + ".tif")
            elif ds == "lulc/clcd":
                r["source_file"] = "[path] " + src_clcd(p[3])
                chk = os.path.join(ARCH, "clcd-albert",
                                   "CLCD_v01_%s_albert.tif" % p[3])
            elif ds == "lulc/hlu1km":
                y, ssp, _ = parse_hlu(r["layer_path"])
                r["source_file"] = "[path] " + src_hlu(y, ssp)
                key = "SSP1_RCP26" if ssp is None else HLU_SSP[ssp]
                chk = os.path.join(ARCH, "harmonised", "Harmonised-1960-2100",
                                   "%s_country-f.tif" % key)
            if r["source_file"]:
                c1 += 1
                if chk and not os.path.exists(chk):
                    unresolved.append(r["layer_path"])

        # ---- evidence grade (+ legend code for class layers)
        d = r["variable_definition"] or ""
        if not re.search(r"\[(doc|std|name|proc)\]", d):
            extra = ""
            cls = None
            if ds == "lulc/hlu1km":
                _y, _s, cls = parse_hlu(r["layer_path"])
                if cls in HLU_LEGEND:
                    extra = "; source legend code %d = %s" % HLU_LEGEND[cls]
            elif ds == "lulc/clcd":
                cls = p[4]
                if cls in CLCD_LEGEND:
                    extra = "; source legend code %d = %s" % CLCD_LEGEND[cls]
            m = re.search(r" \[[a-z][^\]]*\]$", d)
            if extra:
                d = (d[:m.start()] + extra + d[m.start():]) if m else (d + extra)
            r["variable_definition"] = d.rstrip() + " [doc]"
            c2 += 1

        # ---- urban / water time-invariance note
        if ds == "lulc/hlu1km":
            _y, _s, cls = parse_hlu(r["layer_path"])
            if cls in ("urban", "water"):
                cur = r["notes"] or ""
                # MARK is a substring of MARK2, so test the longer marker first and
                # match the delimiter / the start anchor exactly. Matching on `mk in cur`
                # alone dropped the pre-existing prefix of every water row that had one.
                for mk in (MARK2, MARK):
                    if " | " + mk in cur:
                        cur = cur.split(" | " + mk)[0].rstrip()
                        break
                    if cur.startswith(mk):
                        cur = ""
                        break
                txt = NOTE_URBAN if cls == "urban" else NOTE_WATER
                new = (cur + txt) if cur else txt.lstrip(" |")
                if new != (r["notes"] or ""):
                    r["notes"] = new
                    c6 += 1

        # ---- _max / _min resampling text
        m = re.search(r"_(max|min)\.tif$", r["layer_path"])
        if m:
            want = m.group(1)
            d2 = re.sub(r"resampling = average \(window mean over the source cells\)",
                        "resampling = %s (window %s of the source cells)" % (want, want),
                        r["processing_steps"])
            if d2 != r["processing_steps"]:
                r["processing_steps"] = d2
                c8 += 1

    print("source_file filled      : %d (unresolved paths: %d)"
          % (c1, len(unresolved)))
    print("evidence grade added    : %d" % c2)
    print("time-invariance notes   : %d rows rewritten" % c6)
    print("_max/_min rule fixed    : %d" % c8)
    for u in unresolved[:5]:
        print("   unresolved: %s" % u)

    if a.check:
        print()
        print("--check: nothing written")
        return 0
    if len(rows) != n0 or list(rows[0].keys()) != cols:
        print("ABORT: shape changed")
        return 1
    if unresolved:
        print("ABORT: some generated source paths do not exist")
        return 1
    tmp = TABLE + ".new"
    with open(tmp, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    back = list(csv.DictReader(open(tmp, encoding="utf-8-sig")))
    if back != rows or len(back) != n0:
        print("ABORT: re-read differs")
        os.remove(tmp)
        return 1
    shutil.move(tmp, TABLE)
    print("wrote %s" % TABLE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
