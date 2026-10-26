#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Mutation tests for the audit scripts themselves.

The audit suite is only worth running if its checks actually fail on bad data. This
builds a throw-away delivery root in the temp directory, plants one known defect per
layer (or per proportion group, or per focal/base pair), runs the real scripts against
it through CHECO_ROOT, and asserts that each planted defect is reported.

The point is to catch checks that "pass because they did nothing": a blank statistic
read as zero, an empty group read as a perfect group, a missing range read as an
in-range layer. Every such path shows up here as NOT CAUGHT.

Usage:
    python scripts/audit/test_audit_scripts.py            # run and report
    python scripts/audit/test_audit_scripts.py --keep     # keep the temp root

Exit code 0 only when every planted defect was caught and every control still passed.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
import rasterio
from rasterio.transform import Affine

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT = os.path.join(HERE, "audit_data_quality.py")
SUMMARIZE = os.path.join(HERE, "audit_summarize.py")
COMPOSITION = os.path.join(HERE, "audit_composition.py")
FOCAL = os.path.join(HERE, "check_focal_nesting.py")

REAL = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
NODATA = -9999.0


# --------------------------------------------------------------------------- helpers
def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_tif(path, arr, transform, crs, nodata=NODATA, dtype="float32",
              compress=True, tiled=True, truncate=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    prof = dict(driver="GTiff", width=arr.shape[1], height=arr.shape[0], count=1,
                dtype=dtype, crs=crs, transform=transform, nodata=nodata)
    if tiled:
        prof.update(tiled=True, blockxsize=256, blockysize=256)
    if compress:
        prof.update(compress="deflate")
    with rasterio.open(path, "w", **prof) as s:
        s.write(arr.astype(dtype), 1)
    if truncate:
        n = os.path.getsize(path)
        with open(path, "r+b") as f:
            f.truncate(int(n * truncate))


def run(cmd, root):
    env = dict(os.environ, CHECO_ROOT=root, PYTHONIOENCODING="utf-8")
    return subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8",
                          errors="replace")


# ----------------------------------------------------------------------- per-layer
def case_per_layer(root):
    """Plant one defect per layer and see which ones the per-layer audit reports."""
    tpl = os.path.join(root, "data", "template_albers1km.tif")
    msk = os.path.join(root, "data", "mask_china.tif")
    with rasterio.open(tpl) as s:
        transform, crs, H, W = s.transform, s.crs, s.height, s.width
    with rasterio.open(msk) as s:
        mask = s.read(1)
    inside = mask == 1
    rr, cc = np.where(inside)
    r0, c0 = int(rr[0]), int(cc[0])                    # a cell inside China
    ro, co = 0, 0                                      # a corner, outside China

    base = np.where(inside, np.float32(1.0), np.float32(NODATA)).astype("float32")
    clean = base.copy()

    nan = base.copy(); nan[r0, c0] = np.nan
    outside = base.copy(); outside[ro, co] = np.float32(5.0)
    above = base.copy(); above[r0, c0] = np.float32(1e9)
    odd_nodata = base.copy(); odd_nodata[~inside] = np.float32(-32768.0)
    empty = np.full_like(base, np.float32(NODATA))     # not one valid cell

    shifted = transform * Affine.translation(1000, 0)

    # (name, array, transform, kwargs, expected failure text, metadata overrides)
    cases = [
        ("clean", clean, transform, {}, None, {}),
        ("p_nan", nan, transform, {}, "non_finite", {}),
        ("p_outside", outside, transform, {}, "valid_cells_outside_mask", {}),
        ("p_above", above, transform, {}, "above_range", {"range": "[0, 2]"}),
        ("p_dtype", clean, transform, {"dtype": "float64"}, "dtype", {}),
        ("p_nodata", odd_nodata, transform, {"nodata": -32768.0}, "nodata", {}),
        ("p_shift", clean, shifted, {}, "transform differs", {}),
        ("p_nocomp", clean, transform, {"compress": False}, "storage", {}),
        ("p_dims", clean[:100, :100], transform, {}, "dims", {}),
        ("p_corrupt", clean, transform, {"truncate": 0.3}, "open", {}),
        ("p_sha", clean, transform, {}, "manifest_sha", {"bad_sha": True}),
        ("p_dict", clean, transform, {}, "dictionary_mismatch", {"bad_dict": True}),
        ("p_norange", clean, transform, {}, "range_unverifiable", {"range": ""}),
        ("p_empty", empty, transform, {}, "range_unverifiable", {"range": "[0, 2]"}),
    ]

    cov = os.path.join(root, "data", "covariates", "glo")
    files = []
    for name, arr, tr, kw, want, meta in cases:
        p = os.path.join(cov, "topo", "mut", name + ".tif")
        write_tif(p, arr, tr, crs, **kw)
        files.append((name, p, tr, arr, want, meta))

    # metadata that is correct for every layer *except* the injected defect
    man, dic, prov = [], [], []
    for name, p, tr, arr, want, meta in files:
        rel = os.path.relpath(p, cov).replace("\\", "/")
        key = "glo/" + rel
        h = sha256(p)
        if meta.get("bad_sha"):
            h = "0" * 64
        man.append({"relpath": "covariates/" + key, "bytes": os.path.getsize(p),
                    "sha256": h, "mtime": ""})
        # take the statistics from the file as written, so the recorded metadata is
        # correct and the only failing check is the one that was planted
        try:
            with rasterio.open(p) as s:
                a = s.read(1)
                nd = s.nodata
            v = a[a != nd] if nd is not None else a.ravel()
            v = v[np.isfinite(v)]
            vmin = float(np.min(v)) if v.size else 0.0
            vmax = float(np.max(v)) if v.size else 0.0
        except Exception:
            vmin, vmax, v = 0.0, 0.0, np.array([])
        if meta.get("bad_dict"):
            vmax = vmax + 100.0
        dic.append({"relpath": key, "theme": "topo", "dataset": "mut", "unit": "-",
                    "value_min": repr(vmin), "value_max": repr(vmax),
                    "n_valid": str(int(v.size)), "suffix": "", "note": "", "sdm_note": ""})
        rng = meta.get("range", "[0, 2]")
        prov.append({"layer_path": key, "status": "active", "expected_range": rng})

    docs = os.path.join(root, "00_docs")
    os.makedirs(docs, exist_ok=True)
    for fn, rows in (("MANIFEST.csv", man), ("variable_dictionary.csv", dic),
                     ("provenance_table.csv", prov)):
        with open(os.path.join(docs, fn), "w", newline="", encoding="utf-8-sig") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)

    r = run([sys.executable, AUDIT, "--workers", "1"], root)
    if r.returncode != 0:
        print("    audit failed to run:\n%s\n%s" % (r.stdout[-2000:], r.stderr[-2000:]))
        return [("all", False, "audit script crashed")]
    r = run([sys.executable, SUMMARIZE], root)
    fails = {}
    with open(os.path.join(root, "audit", "audit_failures.csv"), newline="",
              encoding="utf-8") as f:
        for row in csv.DictReader(f):
            fails[os.path.basename(row["relpath"]).replace(".tif", "")] = row["failures"]

    out = []
    for name, p, tr, arr, want, meta in files:
        got = fails.get(name, "")
        if want is None:
            ok = got == ""
            out.append((name, got or "(passed)", "control must pass", ok))
        else:
            ok = want in got
            out.append((name, got or "(passed)", want, ok))
    return out


# --------------------------------------------------------------------- composition
def case_composition(root):
    """A group that sums to 1 must pass; a group that sums to 0.9 must fail."""
    tpl = os.path.join(root, "data", "template_albers1km.tif")
    with rasterio.open(tpl) as s:
        transform, crs = s.transform, s.crs
    H = W = 64
    a = np.full((H, W), 0.6, "float32")
    b = np.full((H, W), 0.4, "float32")     # 0.6 + 0.4 = 1.0
    c = np.full((H, W), 0.6, "float32")
    d = np.full((H, W), 0.3, "float32")     # 0.6 + 0.3 = 0.9  -> must fail

    cov = os.path.join(root, "data", "covariates", "glo")
    nul = np.full((H, W), np.float32(NODATA), "float32")
    for ds, year, cls, arr in (("good", "2020", "cropland", a), ("good", "2020", "forest", b),
                               ("bad", "2020", "cropland", c), ("bad", "2020", "forest", d),
                               ("zero", "2020", "cropland", nul), ("zero", "2020", "forest", nul)):
        p = os.path.join(cov, "lulc", ds, year, cls,
                         "glo_lulc_%s_%s_%s_prop.tif" % (ds, year, cls))
        write_tif(p, arr, transform, crs)

    r = run([sys.executable, COMPOSITION, "--workers", "1"], root)
    if r.returncode != 0:
        print("    composition failed to run:\n%s\n%s" % (r.stdout[-1500:], r.stderr[-1500:]))
        return [("composition", False, "script crashed")]
    path = os.path.join(root, "audit", "composition_identity.csv")
    rows = {x["dataset"]: x for x in csv.DictReader(open(path, encoding="utf-8"))}
    out = []
    g = rows.get("good", {})
    out.append(("comp_good", "max|sum-1|=%s" % g.get("max_abs_dev", "?"),
                "must pass", float(g.get("max_abs_dev") or 1) < 1e-3))
    nl = rows.get("zero", {})
    out.append(("comp_null", "error=%s" % (nl.get("error") or "(none)"),
                "no_cells_inspected", nl.get("error") == "no_cells_inspected"))
    bd = rows.get("bad", {})
    out.append(("comp_bad", "max|sum-1|=%s n_off_1e-3=%s" % (bd.get("max_abs_dev", "?"),
                                                            bd.get("n_off_1e-3", "?")),
                "must fail", float(bd.get("max_abs_dev") or 0) > 1e-3))
    return out


# --------------------------------------------------------------------------- focal
def case_focal(root):
    """A focal layer outside its base range must be flagged; one inside must not."""
    aud = os.path.join(root, "audit")
    os.makedirs(aud, exist_ok=True)
    rows = [
        # base with range [0, 10]
        {"relpath": "glo/topo/mut/base.tif", "vmin": "0", "vmax": "10"},
        {"relpath": "glo/topo/mut/base_f1000.tif", "vmin": "1", "vmax": "9"},   # fine
        {"relpath": "glo/topo/mut/base_f5000.tif", "vmin": "-1", "vmax": "9"},  # below base
        {"relpath": "glo/topo/mut/base_f10000.tif", "vmin": "1", "vmax": "11"}, # above base
    ]
    cols = sorted({k for r in rows for k in r})
    with open(os.path.join(aud, "layer_audit.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols, restval="")
        w.writeheader()
        w.writerows(rows)
    r = run([sys.executable, FOCAL], root)
    if r.returncode not in (0, 1):
        print("    focal check failed to run:\n%s\n%s" % (r.stdout[-1500:], r.stderr[-1500:]))
        return [("focal", False, "script crashed")]
    path = os.path.join(aud, "focal_nesting.csv")
    st = {os.path.basename(x["focal"]): x["status"]
          for x in csv.DictReader(open(path, encoding="utf-8"))}
    return [
        ("focal_inside", st.get("base_f1000.tif", "?"), "ok", st.get("base_f1000.tif") == "ok"),
        ("focal_below", st.get("base_f5000.tif", "?"), "OUT_OF_BASE_RANGE",
         st.get("base_f5000.tif") == "OUT_OF_BASE_RANGE"),
        ("focal_above", st.get("base_f10000.tif", "?"), "OUT_OF_BASE_RANGE",
         st.get("base_f10000.tif") == "OUT_OF_BASE_RANGE"),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()

    root = tempfile.mkdtemp(prefix="checo_mut_")
    os.makedirs(os.path.join(root, "data"), exist_ok=True)
    shutil.copy2(os.path.join(REAL, "data", "template_albers1km.tif"),
                 os.path.join(root, "data", "template_albers1km.tif"))
    shutil.copy2(os.path.join(REAL, "data", "mask_china.tif"),
                 os.path.join(root, "data", "mask_china.tif"))

    print("变异根目录:", root)
    results = []
    print("\n=== 逐层审计 ===")
    for name, got, want, ok in case_per_layer(root):
        results.append(ok)
        print("  %-12s %-8s 期望 %-28s 实际 %s" %
              (name, "CAUGHT" if ok else "MISSED", want, got[:90]))
    print("\n=== 组成恒等式 ===")
    for name, got, want, ok in case_composition(root):
        results.append(ok)
        print("  %-12s %-8s 期望 %-28s 实际 %s" %
              (name, "CAUGHT" if ok else "MISSED", want, got[:90]))
    print("\n=== 焦点不越基底 ===")
    for name, got, want, ok in case_focal(root):
        results.append(ok)
        print("  %-12s %-8s 期望 %-28s 实际 %s" %
              (name, "CAUGHT" if ok else "MISSED", want, got[:90]))

    n = len(results)
    npass = sum(results)
    print("\n=== 合计: %d/%d 项符合预期 ===" % (npass, n))
    if not args.keep:
        shutil.rmtree(root, ignore_errors=True)
    else:
        print("保留:", root)
    return 0 if npass == n else 1


if __name__ == "__main__":
    sys.exit(main())
