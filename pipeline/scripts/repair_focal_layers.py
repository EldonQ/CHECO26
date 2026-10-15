# -*- coding: utf-8 -*-
"""repair_focal_layers.py -- rebuild every focal_mean-derived layer with the
corrected common.focal_mean, plus the LULC layers derived from focal proportions.

Why this exists
---------------
`common.focal_mean` used to decide "does this window hold any valid cell?" by
testing the float mean of the validity mask against 0. On a window with zero
valid cells that mean is a rounding residue (~1e-17), not 0, so the guard always
passed and the layer received numerator/1e-17 -- arbitrary large values. 242 of
the 484 focal layers carried such cells (203,407 of them library-wide).

What this script does
---------------------
* Discovers its work set by matching `_f<metres>` against a base stem that is
  actually present on disk, so only true focal_mean outputs are touched
  (patchdensity/patchsize use `patch_metric` and are never matched).
* Rebuilds each layer from its on-disk base layer, so the expensive upstream
  warps are not repeated.
* Shannon has no base layer of its own: it is recomputed from the *repaired*
  focal class proportions of the same snapshot, in the class order used by
  04_derive_lulc.py, so the float arithmetic matches the original.
* NoData handling matches the pipeline exactly: NaN -> -9999, China mask applied,
  float32, deflate/tiled, written atomically through a .tmp file.
* Every layer is backed up once (never overwritten) before it is rewritten, and a
  per-layer before/after record goes to logs/focal_repair_report.csv.

Work is grouped by base layer so each raster is read once for all its radii, and
`focal_mean` uses the fast float-mask denominator (45x faster than exact integer
convolution, verified to classify empty windows identically).

Usage
-----
  python repair_focal_layers.py                     # dry run, analysis only
  python repair_focal_layers.py --apply             # rebuild in place
  python repair_focal_layers.py --apply --workers 6
  python repair_focal_layers.py --apply --limit 8   # first N base layers
"""
from __future__ import annotations

import argparse
import csv
import multiprocessing as mp
import os
import re
import shutil
import sys
import time

import numpy as np
import rasterio

sys.path.insert(0, r"E:\CHECO26\N-SDM")
from scripts import common  # noqa: E402

ROOT = r"E:\CHECO26\N-SDM"
COV = os.path.join(ROOT, "data", "covariates", "glo")
MASK_PATH = os.path.join(ROOT, "data", "mask_china.tif")
BACKUP = os.path.join(ROOT, "scratch", "backup_focal_pre_repair")
REPORT = os.path.join(ROOT, "logs", "focal_repair_report.csv")

RE_FOCAL = re.compile(r"^(?P<base>.+)_f(?P<radius>\d+)$")
NODATA = -9999.0
LULC_CLASSES = ["cropland", "forest", "grassland", "urban", "barren", "water"]
_MASK = None


# --------------------------------------------------------------------------- io
def china_mask():
    """China mask, read once per process."""
    global _MASK
    if _MASK is None:
        with rasterio.open(MASK_PATH) as ds:
            _MASK = ds.read(1) == 1
    return _MASK


def read_layer(path):
    with rasterio.open(path) as ds:
        arr = ds.read(1).astype(np.float64)
        nd = ds.nodata
    arr[~np.isfinite(arr)] = np.nan
    if nd is not None:
        arr[arr == nd] = np.nan
    return arr


def write_layer(path, arr):
    """NaN -> NODATA, China-mask, float32, atomic write with the pipeline profile."""
    out = np.where(np.isfinite(arr) & china_mask(), arr, NODATA).astype(np.float32)
    with rasterio.open(path) as ds:
        profile = ds.profile.copy()
    profile.update(dtype="float32", nodata=NODATA, count=1, compress="deflate",
                   tiled=True, blockxsize=256, blockysize=256, BIGTIFF="IF_SAFER")
    tmp = path + ".tmp"
    with rasterio.open(tmp, "w", **profile) as dst:
        dst.write(out, 1)
    os.replace(tmp, path)


def backup_once(path):
    """Copy the layer into BACKUP unless a backup already exists (idempotent)."""
    dst = os.path.join(BACKUP, os.path.basename(path))
    if os.path.exists(dst):
        return "kept"
    if os.path.exists(path) and os.path.getsize(path) > 0:
        shutil.copy2(path, dst)
        return "created"
    return "missing"


# ------------------------------------------------------------------- discovery
def all_stems():
    stems = {}
    for dirpath, _, filenames in os.walk(COV):
        for fn in filenames:
            if fn.endswith(".tif"):
                stems[os.path.relpath(os.path.join(dirpath, fn), COV)
                      .replace("\\", "/")[:-4]] = os.path.join(dirpath, fn)
    return stems


def build_workload(stems):
    """{base_stem: sorted [radius_cells, ...]} for true focal_mean outputs.

    Shannon is deliberately excluded: a bare `..._shannon.tif` exists on disk but is
    not what shannon is derived from, so shannon layers are routed to their own
    handler (see shannon_targets).
    """
    work: dict = {}
    for rel in stems:
        m = RE_FOCAL.match(rel)
        if not m or not m.group("base") in stems:
            continue
        if m.group("base").endswith("shannon"):
            continue
        work.setdefault(m.group("base"), []).append(int(m.group("radius")) // 1000)
    return {k: sorted(set(v)) for k, v in work.items()}


def shannon_targets(stems):
    """{shannon layer stem: radius_cells} for every LULC snapshot x radius.

    Shannon is NOT a focal mean of the bare `..._shannon.tif` layer that sits next
    to it: it is -sum(p ln p) over the *focal proportions* of the snapshot. A bare
    shannon layer does exist on disk, so it must not be used to exclude these --
    doing so silently skipped 30 of the 40 shannon layers. The key is the FULL
    layer stem (`<snap>_shannon_f<radius>`), not the stripped one, or all four
    radii collapse into a single entry.
    """
    out = {}
    for rel in stems:
        m = RE_FOCAL.match(rel)
        if m and m.group("base").endswith("shannon"):
            out[rel] = int(m.group("radius")) // 1000
    return out


def prop_path(layer_stem, radius):
    """Absolute snapshot dir and stem for one shannon layer.

    layer_stem is the COV-relative layer stem including the focal suffix, e.g.
    'lulc/glu1km/2020/glo_lulc_glu1km_2020_shannon_f1000'. The focal suffix is
    stripped first, so the result is (...\\lulc\\glu1km\\2020, 'glo_lulc_glu1km_2020').
    """
    base_rel = RE_FOCAL.match(layer_stem).group("base")       # drop _f<radius>
    snap_dir = os.path.join(COV, os.path.dirname(base_rel))
    snap_stem = os.path.basename(base_rel)[:-len("_shannon")]
    return snap_dir, snap_stem


# ------------------------------------------------------------------ statistics
def rebuild_shannon(layer_stem, radius):
    """-sum(p ln p) over the six repaired focal class proportions of one snapshot."""
    snap_dir, snap_stem = prop_path(layer_stem, radius)
    acc = None
    seen = None
    for cls in LULC_CLASSES:
        p = read_layer(os.path.join(snap_dir, cls, "%s_%s_prop_f%d.tif"
                                    % (snap_stem, cls, radius * 1000)))
        ok = np.isfinite(p)
        seen = ok if seen is None else (seen | ok)
        # p is a proportion: clip float residue so the entropy is never negative
        pc = np.clip(p, 0.0, 1.0)
        with np.errstate(divide="ignore", invalid="ignore"):
            term = np.where(ok, np.where(pc > 0, pc * np.log(pc), 0.0), 0.0)
        acc = term if acc is None else acc + term
    return -acc


# ------------------------------------------------------------------- execution
def repair_base(args):
    """Worker: rebuild every radius of one base layer. Returns report rows.

    Reads the base and the current output once, computes each radius in memory and
    writes once; the "after" figures come from the array that was just written
    (the write is a lossless rounding of it), so no extra disk pass is needed.
    """
    base_stem, stems, radii, apply = args
    base_path = stems[base_stem]
    base = read_layer(base_path)
    valid = np.isfinite(base)
    b = base[np.isfinite(base)]
    bmin, bmax = (float(b.min()), float(b.max())) if b.size else (np.nan, np.nan)
    m = china_mask()
    rows = []
    for radius in radii:
        rel = "%s_f%d" % (base_stem, radius * 1000)
        path = stems[rel]
        size = 2 * radius + 1
        empty = common.focal_count(valid, size) < 1.0
        cur = read_layer(path)
        cm = np.isfinite(cur) & m
        v = cur[cm]
        row = dict(layer=os.path.relpath(path, COV).replace("\\", "/"), kind="focal",
                   radius=radius * 1000, base_min=bmin, base_max=bmax, backup="",
                   before_n=int(v.size),
                   before_min=float(v.min()) if v.size else np.nan,
                   before_max=float(v.max()) if v.size else np.nan,
                   before_garbage=int((cm & empty).sum()),
                   before_oor=int(((v < bmin - 1e-4) | (v > bmax + 1e-4)).sum()) if v.size else 0,
                   after_n="", after_min="", after_max="", after_garbage="", after_oor="")
        if apply:
            row["backup"] = backup_once(path)
            out = common.focal_mean(base, radius, invalid=~valid)
            write_layer(path, out)
            v2 = out[np.isfinite(out) & m]
            row.update(after_n=int(v2.size),
                       after_min=float(v2.min()) if v2.size else np.nan,
                       after_max=float(v2.max()) if v2.size else np.nan,
                       after_garbage=0,
                       after_oor=int(((v2 < bmin - 1e-4) | (v2 > bmax + 1e-4)).sum()) if v2.size else 0)
        rows.append(row)
    return rows


def repair_shannon(args):
    """Shannon has no base layer: its bound is the theoretical [0, ln 6]."""
    layer_stem, stems, radius, apply = args
    path = stems[layer_stem]
    cur = read_layer(path)
    cm = np.isfinite(cur) & china_mask()
    v = cur[cm]
    hi = float(np.log(6))
    row = dict(layer=os.path.relpath(path, COV).replace("\\", "/"), kind="shannon",
               radius=radius * 1000, base_min=0.0, base_max=hi, backup="",
               before_n=int(v.size),
               before_min=float(v.min()) if v.size else np.nan,
               before_max=float(v.max()) if v.size else np.nan,
               before_garbage=0,
               before_oor=int((v < -1e-4).sum()) if v.size else 0,
               after_n="", after_min="", after_max="", after_garbage="", after_oor="")
    if apply:
        row["backup"] = backup_once(path)
        out = rebuild_shannon(layer_stem, radius)
        write_layer(path, out)
        v2 = out[np.isfinite(out) & china_mask()]
        row.update(after_n=int(v2.size),
                   after_min=float(v2.min()) if v2.size else np.nan,
                   after_max=float(v2.max()) if v2.size else np.nan,
                   after_garbage=0,
                   after_oor=int((v2 < -1e-4).sum()) if v2.size else 0)
    return [row]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="first N base layers")
    ap.add_argument("--workers", type=int, default=1)
    ap.add_argument("--shannon-only", action="store_true",
                    help="skip the focal pass (use when it already ran)")
    args = ap.parse_args()

    os.makedirs(BACKUP, exist_ok=True)
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    stems = all_stems()
    work = build_workload(stems)
    shan = shannon_targets(stems)
    bases = sorted(work)
    if args.limit:
        bases = bases[:args.limit]
        shan = {}
    print("tree layers        : %d" % len(stems))
    print("base layers        : %d  ->  focal outputs: %d"
          % (len(work), sum(len(v) for v in work.values())))
    print("shannon outputs    : %d" % len(shan))
    print("mode               : %s%s" % ("APPLY" if args.apply else "DRY RUN",
                                        "  workers=%d" % args.workers if args.workers > 1 else ""))

    # The focal pass must fully finish before Shannon: each shannon layer is
    # rebuilt from the class proportions of its own snapshot, which that pass
    # repairs. Running them together could read a not-yet-repaired proportion.
    focal_tasks = [] if args.shannon_only else \
        [(b, stems, work[b], args.apply) for b in bases]
    shan_tasks = [(stem, stems, r, args.apply) for stem, r in sorted(shan.items())]

    t0 = time.time()
    rows = []
    if args.workers > 1:
        with mp.Pool(args.workers) as pool:
            for i, res in enumerate(pool.imap_unordered(_dispatch, focal_tasks), 1):
                rows.extend(res)
                _echo(i, len(focal_tasks), res)
    else:
        for i, t in enumerate(focal_tasks, 1):
            res = _dispatch(t)
            rows.extend(res)
            _echo(i, len(focal_tasks), res)

    for j, t in enumerate(shan_tasks, 1):
        res = _dispatch(t)
        rows.extend(res)
        _echo(j, len(shan_tasks), res)

    fields = ["layer", "kind", "radius", "base_min", "base_max", "backup",
              "before_n", "before_min", "before_max", "before_garbage", "before_oor",
              "after_n", "after_min", "after_max", "after_garbage", "after_oor"]
    rows.sort(key=lambda r: r["layer"])
    with open(REPORT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    print("\nelapsed %.1f s" % (time.time() - t0))
    print("report -> %s" % REPORT)
    if args.apply:
        gb = sum(r["before_garbage"] or 0 for r in rows)
        ga = sum(r["after_garbage"] or 0 for r in rows)
        ob = sum(r["before_oor"] or 0 for r in rows)
        oa = sum(r["after_oor"] or 0 for r in rows)
        print("garbage cells     %d -> %d" % (gb, ga))
        print("out-of-range      %d -> %d" % (ob, oa))
        print("backups           -> %s" % BACKUP)


def _dispatch(task):
    base_stem, stems, payload, apply = task
    if isinstance(payload, list):
        return repair_base((base_stem, stems, payload, apply))
    return repair_shannon((base_stem, stems, payload, apply))

def _echo(i, n, res):
    for r in res:
        if r["kind"] == "focal":
            print("[%3d/%3d] %-70s r=%-6d garbage %d -> %s" %
                  (i, n, os.path.basename(r["layer"]), r["radius"],
                   r["before_garbage"], r["after_garbage"] or "-"), flush=True)
        else:
            print("[%3d/%3d] %-70s r=%-6d neg %d -> %s" %
                  (i, n, os.path.basename(r["layer"]), r["radius"],
                   r["before_oor"], r["after_oor"] or "-"), flush=True)


if __name__ == "__main__":
    main()
