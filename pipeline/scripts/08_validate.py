"""P5 全库校验：manifest 计划层数 vs 盘上实际层数（0 缺漏）、100% 层模板四查、
逐层值域/NA 统计、命名校验、每主题抽样与源数据 cell-by-cell 比对。
产出 logs/p5_validation_report.csv + logs/p5_summary.txt（复制入 00_docs）。"""
import csv
import multiprocessing as mp
import os
import random
import sys
import traceback

import numpy as np
import rasterio

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

import importlib
s02 = importlib.import_module("02_ingest_static")
s02b = importlib.import_module("02b_hydro_stats_addon")
s03 = importlib.import_module("03_ingest_timeseries")
s04 = importlib.import_module("04_derive_lulc")
s05 = importlib.import_module("05_derive_dist")
s07 = importlib.import_module("07_future_chains")

SCRIPT = "08_validate.py"

SOIL_ATTR_DIR = s02.SOIL_ATTR_DIR
PROFILE_DEPTHS = ["0", "5", "15", "30", "60"]


def expected_layers(cfg):
    """全部生产脚本 manifest 并集 -> 期望层集合 {relpath: dict(theme, src)}。"""
    exp = {}

    def add(parts, suffix, theme, src="", scale=None):
        p = common.layer_path(cfg, parts, suffix)
        exp[common.relpath(cfg, p)] = dict(theme=theme, src=src, scale=scale)

    # P2 静态（02）：bioclim 28 + soil 168 + topo 2 + hydro/dist 40 + vege 3
    for t in s02.build_manifest(cfg):
        add(t["parts"], "", "p2-static", t.get("src", ""), t.get("scale"))
    # P2b hydro 精选统计增补（02b）：minmax 8 x2 + maxonly 3 = 19（cti/channel_grad 审计定案不补）
    for t in s02b.build_manifest(cfg):
        add(t["parts"], t["suffix"], "p2b-hydro-stats", t["src"], t.get("scale"))
    # P3 时序（03）：anthro 158 + vege ndvi 15（smod 为派生层，无直接可比源）
    for t in s03.build_manifest(cfg):
        src = t.get("src", "") if t["kind"] == "warp" else ""
        add(t["parts"], t["suffix"], "p3-timeseries", src, t.get("scale"))
    # P3 LULC（04）：10 快照 x 54 = 540（patchdensity-all_f1000 常量层不产出）
    legend = {int(k): v for k, v in cfg["lulc_legend"].items()}
    radii = cfg["focal"]["radii_km"]
    for snap in s04.SNAPSHOTS:
        for code, cname in legend.items():
            add(s04.snapshot_parts(cfg, snap, [cname]), "_prop", "p3-lulc")
            for r in radii:
                add(s04.snapshot_parts(cfg, snap, [cname]), "_prop_f%d" % (r * 1000), "p3-lulc")
        for r in radii:
            add(s04.snapshot_parts(cfg, snap, []), "_shannon_f%d" % (r * 1000), "p3-lulc")
        add(s04.snapshot_parts(cfg, snap, []), "_edge", "p3-lulc")
        for r in radii:
            add(s04.snapshot_parts(cfg, snap, []), "_edge_f%d" % (r * 1000), "p3-lulc")
        for scope in ("all", "forest"):
            for r in radii:
                if not (scope == "all" and r == radii[0]):
                    add(s04.snapshot_parts(cfg, snap, []), "_patchdensity-%s_f%d" % (scope, r * 1000), "p3-lulc")
                add(s04.snapshot_parts(cfg, snap, []), "_patchsize-%s_f%d" % (scope, r * 1000), "p3-lulc")
    # P3 距离（05）：5 层
    for parts, _, _ in s05.TASKS:
        add(parts, "", "p3-dist")
    # P3 topo aspect/TRI + 土壤剖面 28（06）
    add(["glo", "topo", "chinadem", "aspect"], "", "p3-topo")
    add(["glo", "topo", "chinadem", "tri"], "", "p3-topo")
    for adir in sorted(set(SOIL_ATTR_DIR.values())):
        add(["glo", "soil", "csdlv2", adir], "_profile", "p3-soilprofile")
    # P4 未来气候（07）：504（N-SDM 规范 scenario/<year>/<ssp> 口径）
    for t in s07.build_manifest(cfg):
        add(t["parts"], "", "p4-scenario", t.get("src", ""))
    return exp


def scan_disk(cfg):
    """盘上实际层集合。"""
    cov = cfg["paths"]["covariates"]
    disk = {}
    for dirpath, _, filenames in os.walk(cov):
        for fn in filenames:
            if fn.endswith(".tif"):
                full = os.path.join(dirpath, fn)
                disk[common.relpath(cfg, full)] = full
    return disk


def align_worker(rel):
    cfg = common.load_config()
    path = os.path.join(cfg["paths"]["covariates"], *rel.split("/"))
    try:
        ok = common.check_alignment(path, cfg)
        with rasterio.open(path) as ds:
            a = ds.read(1)
            nod = ds.nodata
            dty = ds.dtypes[0]
        # 有效 = 非 NaN 且不等于 nodata（LULC 等 float 层 nodata 存为 -9999 实值，须显式排除）
        valid = ~np.isnan(a) if a.dtype.kind == "f" else np.ones(a.shape, dtype=bool)
        if nod is not None:
            valid &= (a != nod)
        v = a[valid]
        return dict(relpath=rel, aligned=ok, dtype=dty, nodata=str(nod),
                    n_valid=int(v.size),
                    na_frac=round(1.0 - v.size / float(a.size), 4),
                    vmin=float(v.min()) if v.size else None,
                    vmax=float(v.max()) if v.size else None,
                    error="")
    except Exception as e:
        return dict(relpath=rel, aligned=False, dtype="", nodata="",
                    n_valid=None, na_frac=None, vmin=None, vmax=None,
                    error=str(e))


def sampled_cell_check(cfg, rel, src_path, info_scale):
    """抽样 cell-by-cell：1000 个随机有效像元，源数据按最近邻读取比对。
    判定：一致率 >= 95%，且不一致样本差异仅来自重采样（量级合理）。"""
    path = os.path.join(cfg["paths"]["covariates"], *rel.split("/"))
    if not (src_path and os.path.exists(src_path)):
        return dict(relpath=rel, verdict="skip", note="source not accessible")
    with rasterio.open(path) as ds:
        a = ds.read(1)
        tr = ds.transform
    v = np.argwhere(~np.isnan(a)) if a.dtype.kind == "f" else np.argwhere(a != ds.nodata)
    if v.size == 0:
        return dict(relpath=rel, verdict="skip", note="no valid cells")
    rng = random.Random(20260808)
    idx = rng.sample(range(len(v)), min(1000, len(v)))
    rows = v[idx]
    xs = tr.c + (rows[:, 1] + 0.5) * tr.a
    ys = tr.f + (rows[:, 0] + 0.5) * tr.e
    # 目标像元中心 -> 源 CRS 坐标，再在源上逐点取值（sample 块感知，对超大源安全）
    with rasterio.open(path) as ds, rasterio.open(src_path) as sds:
        from rasterio.warp import transform as wtrans
        sx, sy = wtrans(ds.crs, sds.crs, xs, ys)
        pts = list(zip(sx, sy))
        raw = np.array([s[0] for s in sds.sample(pts, indexes=1)], dtype=float)
        if sds.nodata is not None:
            raw[raw == sds.nodata] = np.nan
        scale = info_scale
        if scale is not None:
            raw = raw * float(scale)
        vals = raw
    dst_vals = a[rows[:, 0], rows[:, 1]]
    both = ~np.isnan(vals) & ~np.isnan(dst_vals.astype(float))
    if both.sum() == 0:
        return dict(relpath=rel, verdict="skip", note="no overlapping valid samples")
    d = np.abs(vals[both] - dst_vals[both].astype(float))
    tol = max(1e-6, 0.05 * np.nanmax(np.abs(vals[both])))
    match = float((d <= tol).mean())
    verdict = "pass" if match >= 0.95 else "fail"
    return dict(relpath=rel, verdict=verdict, n=int(both.sum()),
                match_rate=round(match, 4), max_abs_diff=float(d.max()),
                note="tol=%g" % tol)


def main():
    cfg = common.load_config()
    exp = expected_layers(cfg)
    disk = scan_disk(cfg)
    missing = sorted(set(exp) - set(disk))
    extra = sorted(set(disk) - set(exp))
    n_exp, n_disk = len(exp), len(disk)
    print("expected=%d disk=%d missing=%d extra=%d" % (n_exp, n_disk, len(missing), len(extra)))
    for m in missing[:20]:
        print("  MISSING:", m)
    for x in extra[:20]:
        print("  EXTRA:", x)

    # ---- 全量模板四查 + 值域 ----
    results = []
    with mp.Pool(int(cfg["runtime"]["workers"])) as pool:
        for i, r in enumerate(pool.imap_unordered(align_worker, sorted(exp)), 1):
            results.append(r)
            if not r["aligned"] or r["error"]:
                print("ALIGN-FAIL:", r["relpath"], r["error"])
            if i % 200 == 0:
                print("aligned checked %d/%d" % (i, len(exp)))
    bad_align = [r for r in results if not r["aligned"]]

    # ---- 掩膜一致性硬门槛：任何层的有效像元数不得超过中国国界掩膜 ----
    mask_n = int(common.china_mask(cfg).sum())
    over_mask = [r for r in results
                 if r["n_valid"] is not None and r["n_valid"] > mask_n]

    rpt = os.path.join(cfg["paths"]["logs"], "p5_validation_report.csv")
    with open(rpt, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["relpath", "theme", "aligned", "dtype", "nodata",
                    "n_valid", "na_frac", "vmin", "vmax", "error"])
        for r in sorted(results, key=lambda x: x["relpath"]):
            w.writerow([r["relpath"], exp[r["relpath"]]["theme"], r["aligned"],
                        r["dtype"], r["nodata"], r["n_valid"], r["na_frac"],
                        r["vmin"], r["vmax"], r["error"]])
    print("report:", rpt)

    # ---- 命名校验 ----
    naming = common.validate_naming(cfg)

    # ---- 每主题抽样 cell-by-cell（仅 warp 类层有直接源）----
    cell_checks = []
    cand = [rel for rel, info in exp.items()
            if info["src"] and info["theme"] in ("p2-static", "p3-timeseries", "p4-scenario")]
    rng = random.Random(20260808)
    by_theme = {}
    for rel in cand:
        by_theme.setdefault(exp[rel]["theme"], []).append(rel)
    picked = []
    for theme, rels in by_theme.items():
        picked += rng.sample(rels, min(3, len(rels)))
    for rel in sorted(picked):
        r = sampled_cell_check(cfg, rel, exp[rel]["src"], exp[rel].get("scale"))
        cell_checks.append(r)
        print("CELL", r["verdict"].upper(), r["relpath"],
              r.get("match_rate", ""),
              ("max_abs_diff=%.6g" % r["max_abs_diff"]) if r.get("max_abs_diff") is not None else "",
              r.get("note", ""))

    # ---- 派生层硬门槛：值域包含 + 空窗口无值（历史上漏掉、导致 242 个焦点层带垃圾值）----
    derived_rc = None
    try:
        import subprocess
        proc = subprocess.run(
            [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                          "10_validate_derived.py")],
            capture_output=True, text=True)
        derived_rc = proc.returncode
        print(proc.stdout.strip().splitlines()[-6:])
        if proc.returncode != 0:
            print(proc.stdout[-4000:])
    except Exception as e:
        print("derived-layer validation could not run:", e)

    # ---- 汇总 ----
    summary = [
        "P5 validation summary",
        "expected layers: %d" % n_exp,
        "disk layers: %d" % n_disk,
        "missing: %d" % len(missing),
        "extra (outside manifest): %d" % len(extra),
        "alignment failures: %d" % len(bad_align),
        "over-china-mask layers: %d (mask valid cells=%d)" % (len(over_mask), mask_n),
        "naming validator errors: %d" % len(naming),
        "derived-layer gates (value range + empty window): %s" % (
            "PASS" if derived_rc == 0 else "FAIL" if derived_rc else "not run"),
        "cell-by-cell checks: %d pass / %d" % (
            sum(1 for c in cell_checks if c["verdict"] == "pass"), len(cell_checks)),
    ]
    spath = os.path.join(cfg["paths"]["logs"], "p5_summary.txt")
    with open(spath, "w", encoding="utf-8") as f:
        f.write("\n".join(summary) + "\n")
        for m in missing:
            f.write("MISSING %s\n" % m)
        for x in extra:
            f.write("EXTRA %s\n" % x)
        for r in bad_align:
            f.write("ALIGN-FAIL %s %s\n" % (r["relpath"], r["error"]))
        for r in over_mask:
            f.write("OVER-MASK %s n_valid=%d\n" % (r["relpath"], r["n_valid"]))
        for e in naming:
            f.write("NAMING %s\n" % e)
        # 抽样比对明细（差异仅允许来自重采样，统计如实入档）
        for c in cell_checks:
            f.write("CELL %s %s match=%s n=%s max_abs_diff=%s %s\n" % (
                c["verdict"].upper(), c["relpath"], c.get("match_rate", ""),
                c.get("n", ""),
                ("%.6g" % c["max_abs_diff"]) if c.get("max_abs_diff") is not None else "",
                c.get("note", "")))
    print("\n".join(summary))
    assert not missing and not extra and not bad_align and not naming, "P5 validation failed"
    assert not over_mask, "%d layers have cells outside China mask" % len(over_mask)
    assert derived_rc == 0, "derived-layer gates failed (see 10_validate_derived.py)"
    print("P5 DONE")


if __name__ == "__main__":
    main()
