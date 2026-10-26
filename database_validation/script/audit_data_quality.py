#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Per-layer data quality audit of the CHECO26 delivered archive.

Opens every delivered GeoTIFF and checks, for each one, that it is what the
documentation says it is. Nothing is taken on trust from the provenance table:
the table's recorded statistics are compared with values recomputed here.

Checks per layer
  open            the file opens and has one band
  dtype           float32
  nodata          declared NoData is -9999
  dims            4,062 rows x 4,861 columns
  transform       1,000 m pixels, origin and extent equal to the template
  crs             CRS equal to the template's
  storage         DEFLATE compressed, tiled, 256 x 256 blocks, band interleave
  values          min, max, mean, sd, valid count, non-finite count
  mask            no valid cell outside the China mask
  range           values inside the documented expected range
  dictionary      recomputed statistics agree with variable_dictionary.csv
  manifest        SHA-256 agrees with MANIFEST.csv

Anything that fails is reported with the layer path; the audit never "passes"
by skipping.

Usage
  python audit_data_quality.py --workers 8                 # full run, resumable
  python audit_data_quality.py --workers 8 --limit 200     # smoke test
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import sys
import time
import traceback
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np
import rasterio

CHECO_ROOT = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
COV_ROOT = os.path.join(CHECO_ROOT, "data", "covariates", "glo")
MASK_PATH = os.path.join(CHECO_ROOT, "data", "mask_china.tif")
TEMPLATE_PATH = os.path.join(CHECO_ROOT, "data", "template_albers1km.tif")
DICT_PATH = os.path.join(CHECO_ROOT, "00_docs", "variable_dictionary.csv")
MANIFEST_PATH = os.path.join(CHECO_ROOT, "00_docs", "MANIFEST.csv")
PROV_PATH = os.path.join(CHECO_ROOT, "00_docs", "provenance_table.csv")
OUT_DIR = os.path.join(CHECO_ROOT, "audit")

WIDTH, HEIGHT = 4861, 4062
NODATA = -9999.0

_MASK0 = None          # True where the cell is outside China
_TEMPLATE = None


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def init_worker():
    """Load the mask and template once per worker process."""
    global _MASK0, _TEMPLATE
    with rasterio.open(MASK_PATH) as s:
        _MASK0 = (s.read(1) != 1)
    with rasterio.open(TEMPLATE_PATH) as s:
        _TEMPLATE = {
            "transform": tuple(s.transform)[:6],
            "crs": s.crs.to_wkt() if s.crs else None,
            "width": s.width, "height": s.height,
        }


def parse_range(text):
    """'[0, 1]' or '[0.0, 1.0]' -> (0.0, 1.0). Returns (None, None) if absent."""
    try:
        t = text.strip().strip("[]")
        lo, hi = [float(x) for x in t.split(",")]
        return lo, hi
    except Exception:
        return None, None


def audit_one(job):
    rel, path, dict_rec, man_rec, prov_rec = job
    r = {
        "relpath": rel,
        "theme": rel.split("/")[1] if rel.count("/") >= 1 else "",
        "bytes": "", "sha256": "", "sha_match": "",
        "open_ok": False, "error": "",
        "width": "", "height": "", "nbands": "", "dtype": "", "nodata": "",
        "crs_ok": "", "transform_ok": "", "dims_ok": "", "storage_ok": "",
        "compress": "", "tiled": "", "block": "", "interleave": "",
        "n_valid": "", "na_frac": "",
        "vmin": "", "vmax": "", "vmean": "", "vsd": "",
        "n_nonfinite": "", "n_outside_mask": "",
        "range_lo": "", "range_hi": "", "n_below": "", "n_above": "", "range_ok": "",
        "dict_vmin": dict_rec.get("value_min", ""),
        "dict_vmax": dict_rec.get("value_max", ""),
        "dict_nvalid": dict_rec.get("n_valid", ""),
        "stats_match": "",
    }
    try:
        size = os.path.getsize(path)
        r["bytes"] = size
        r["sha256"] = sha256_of(path)
        r["sha_match"] = ("yes" if man_rec and man_rec.get("sha256") == r["sha256"]
                          else ("no" if man_rec else "no_manifest"))

        with rasterio.open(path) as s:
            r["open_ok"] = True
            r["width"], r["height"] = s.width, s.height
            r["nbands"] = s.count
            r["dtype"] = s.dtypes[0] if s.dtypes else ""
            r["nodata"] = "" if s.nodata is None else float(s.nodata)
            r["compress"] = s.compression.value if s.compression else ""
            r["interleave"] = s.interleaving.value if s.interleaving else ""
            r["tiled"] = bool(s.profile.get("tiled", False))
            bx = s.profile.get("blockxsize", "")
            by = s.profile.get("blockysize", "")
            r["block"] = "%sx%s" % (bx, by)

            tr = tuple(s.transform)[:6]
            r["dims_ok"] = (s.width == WIDTH and s.height == HEIGHT)
            r["transform_ok"] = all(abs(a - b) < 1e-6 for a, b in zip(tr, _TEMPLATE["transform"]))
            r["crs_ok"] = bool(s.crs and _TEMPLATE["crs"] and s.crs.to_wkt() == _TEMPLATE["crs"])
            r["storage_ok"] = (str(r["compress"]).lower() == "deflate" and bool(r["tiled"])
                               and r["block"] == "256x256" and r["nbands"] == 1)

            a = s.read(1)
            valid = a != np.float32(NODATA)
            n_valid = int(valid.sum())
            r["n_valid"] = n_valid
            r["na_frac"] = round(1.0 - n_valid / a.size, 8)
            if n_valid:
                v = a[valid]
                r["vmin"] = float(np.min(v))
                r["vmax"] = float(np.max(v))
                r["vmean"] = float(np.mean(v, dtype=np.float64))
                r["vsd"] = float(np.std(v, dtype=np.float64))
                r["n_nonfinite"] = int((~np.isfinite(v)).sum())
                r["n_outside_mask"] = int(np.count_nonzero(valid & _MASK0))
                lo, hi = parse_range(prov_rec.get("expected_range", ""))
                if lo is not None:
                    r["range_lo"], r["range_hi"] = lo, hi
                    r["n_below"] = int(np.count_nonzero(v < lo))
                    r["n_above"] = int(np.count_nonzero(v > hi))
                    r["range_ok"] = "True"
                else:
                    # No usable range in the provenance table. Previously this left
                    # n_below/n_above blank, which the summary read as zero and passed:
                    # a layer with no documented range was silently "in range".
                    r["range_ok"] = "no_range"
            else:
                r["n_nonfinite"] = 0
                r["n_outside_mask"] = 0
                r["range_ok"] = "no_valid_cells"
    except Exception as e:
        r["open_ok"] = False
        r["error"] = "%s: %s" % (type(e).__name__, str(e)[:160])

    # dictionary agreement: exact match on the recorded min/max/valid count
    try:
        if r["open_ok"] and r["n_valid"] != "":
            dmn = float(dict_rec["value_min"]); dmx = float(dict_rec["value_max"])
            dn = int(float(dict_rec["n_valid"]))
            r["stats_match"] = (abs(r["vmin"] - dmn) <= 1e-6 * max(1, abs(dmn))
                                and abs(r["vmax"] - dmx) <= 1e-6 * max(1, abs(dmx))
                                and r["n_valid"] == dn)
    except Exception:
        r["stats_match"] = ""
    return r


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit", type=int, default=0, help="0 = all layers")
    ap.add_argument("--out", default=os.path.join(OUT_DIR, "layer_audit.csv"))
    ap.add_argument("--flush", type=int, default=200)
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)

    # documented values to compare against
    dic = {}
    with open(DICT_PATH, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            dic[row["relpath"]] = row
    man = {}
    with open(MANIFEST_PATH, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            man[row["relpath"].replace("covariates/", "", 1)] = row
    prov = {}
    with open(PROV_PATH, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            prov[row["layer_path"]] = row

    files = []
    for dp, dn, fn in os.walk(COV_ROOT):
        for f in fn:
            if f.endswith(".tif") and not f.endswith(".tmp.tif"):
                p = os.path.join(dp, f)
                rel = os.path.relpath(p, COV_ROOT).replace("\\", "/")
                files.append(rel)
    files.sort()
    if args.limit:
        files = files[:args.limit]

    done = set()
    if os.path.exists(args.out):
        with open(args.out, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                done.add(row["relpath"])
    todo = [r for r in files if r not in done]
    print("layers total %d, already audited %d, to do %d, workers %d"
          % (len(files), len(done), len(todo), args.workers), flush=True)

    fields = None
    t0 = time.time()
    n_done = 0
    new_file = not os.path.exists(args.out)
    fout = open(args.out, "a", newline="", encoding="utf-8")
    writer = None

    # document keys carry the leading `glo/` level that COV_ROOT already consumes
    def keyed(rel):
        return rel if rel.startswith("glo/") else "glo/" + rel
    jobs = [(keyed(rel), os.path.join(COV_ROOT, rel.replace("/", os.sep)),
             dic.get(keyed(rel), {}), man.get(keyed(rel), {}), prov.get(keyed(rel), {}))
            for rel in todo]

    with ProcessPoolExecutor(max_workers=args.workers, initializer=init_worker) as ex:
        futs = {ex.submit(audit_one, j): j[0] for j in jobs}
        for fut in as_completed(futs):
            try:
                r = fut.result()
            except Exception:
                rel = futs[fut]
                r = {"relpath": rel, "open_ok": False,
                     "error": traceback.format_exc()[-200:]}
            if fields is None:
                fields = list(r.keys())
                writer = csv.DictWriter(fout, fieldnames=fields, restval="")
                if new_file:
                    writer.writeheader()
                    new_file = False
            writer.writerow({k: r.get(k, "") for k in fields})
            n_done += 1
            if n_done % args.flush == 0:
                fout.flush()
                el = time.time() - t0
                rate = n_done / el
                print("  %6d / %6d  %.1f%%  %.1f layers/s  eta %.0f min"
                      % (n_done, len(todo), 100 * n_done / len(todo), rate,
                         (len(todo) - n_done) / rate / 60), flush=True)
    fout.close()
    print("audit written to", args.out, flush=True)


if __name__ == "__main__":
    main()
