"""P2/P3 时序入库：landscan 25 年(+4 focal)、footHII 20 年（盘上实测 2001-2020，+4 focal）、
GHS-SMOD 城市化比例 12 epoch、NDVI 3 年(+4 focal)、vege 静态结构 3 变量(+4 focal，基底层由 02 生产)。
零裁剪：config 年份列表即全量。幂等可重跑。"""
import csv
import multiprocessing as mp
import os
import sys
import traceback

import numpy as np
import rasterio
from rasterio.windows import from_bounds

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

SCRIPT = "03_ingest_timeseries.py"
SMOD_WINDOW = (72.5, 17.0, 136.5, 55.5)   # SMOD 指示层截取范围（覆盖中国全境含缓冲）


def focal_tasks(cfg, base_parts, radii):
    # focal 后缀用米数（N-SDM 2.0.1 解析器只认 _f<米数>）
    return [(base_parts, "_f%d" % (r * 1000)) for r in radii]


def build_manifest(cfg):
    P = cfg["paths"]
    radii = cfg["focal"]["radii_km"]
    tasks = []
    # ---- landscan 人口 2000-2024：raw + 4 focal ----
    for y in cfg["landscan_years"]:
        src = os.path.join(P["landscan"], "landscan-global-%d-assets" % y,
                           "landscan-global-%d.tif" % y)
        parts = ["glo", "anthro", "landscan", str(y), "pop"]
        tasks.append(dict(kind="warp", parts=parts, suffix="", src=src,
                          rule="continuous", scale=None, src_nodata=-2147483647.0))
        for bp, sfx in focal_tasks(cfg, parts, radii):
            tasks.append(dict(kind="focal", parts=bp, suffix=sfx, base=bp))
    # ---- footHII 2001-2020：指数 = 存值 x 0.01；+4 focal（人为压力多尺度语境） ----
    for y in cfg["foothii_years"]:
        src = os.path.join(P["foothii"], "hii_%d-01-01.tif" % y)
        parts = ["glo", "anthro", "foothii", str(y), "hii"]
        tasks.append(dict(kind="warp", parts=parts,
                          suffix="", src=src, rule="downscale_continuous",
                          scale=float(cfg["units_scale"]["foothii"]), src_nodata=-32768.0))
        for bp, sfx in focal_tasks(cfg, parts, radii):
            tasks.append(dict(kind="focal", parts=bp, suffix=sfx, base=bp))
    # ---- GHS-SMOD 城市化比例 12 epoch ----
    for y in cfg["smod_epochs"]:
        d = "GHS_SMOD_E%d_GLOBE_R2023A_4326_30ss_V2_0" % y
        src = os.path.join(P["smod_ghs"], d, d + ".tif")
        tasks.append(dict(kind="smod", parts=["glo", "anthro", "smod", str(y), "urbanprop"],
                          suffix="", src=src))
    # ---- NDVI 2020-2022：raw + 4 focal ----
    for y in cfg["ndvi_years"]:
        src = os.path.join(P["ndvi_30m"], str(y), "NDVImax%d.tif" % y)
        parts = ["glo", "vege", "glassndvi", str(y), "ndvimax"]
        tasks.append(dict(kind="warp", parts=parts, suffix="", src=src,
                          rule="downscale_continuous",
                          scale=float(cfg["units_scale"]["ndvi"]), src_nodata=32767.0))
        for bp, sfx in focal_tasks(cfg, parts, radii):
            tasks.append(dict(kind="focal", parts=bp, suffix=sfx, base=bp))
    # ---- vege 静态结构 3 变量 focal（基底层由 02 生产，本脚本只做窗口派生） ----
    for bp in (["glo", "vege", "catcd", "treecover"],
               ["glo", "vege", "ch2019", "ch"],
               ["glo", "vege", "agb2019", "agb"]):
        for _, sfx in focal_tasks(cfg, bp, radii):
            tasks.append(dict(kind="focal", parts=bp, suffix=sfx, base=bp))
    return tasks


def do_warp(cfg, t):
    dst = common.layer_path(cfg, t["parts"], t["suffix"])
    common.warp_to_template(t["src"], dst, cfg, resampling=cfg["resampling"][t["rule"]],
                            dtype="float32", src_nodata=t["src_nodata"], scale=t["scale"])
    return dst


def do_focal(cfg, t):
    dst = common.layer_path(cfg, t["parts"], t["suffix"])
    base = common.layer_path(cfg, t["base"])
    radius_km = int(t["suffix"][2:]) / 1000.0   # '_f5000' -> 5 km
    radius_cells = int(round(radius_km * 1000.0 / cfg["grid"]["resolution"]))
    with rasterio.open(base) as ds:
        a = ds.read(1)
    out = common.focal_mean(a, radius_cells, invalid=np.isnan(a))
    # focal 窗口会把边界有效值扩散到境外 nodata 区，落盘前掩膜限回中国区内
    common.apply_china_mask(out, cfg, np.nan)
    common.atomic_write_raster(dst, out, cfg, dtype="float32",
                               nodata=cfg["nodata"]["float"])
    return dst


def do_smod(cfg, t):
    """SMOD 城市类别 -> 0/1 指示层(截取中国区) -> average 聚合 = 城市化比例。"""
    dst = common.layer_path(cfg, t["parts"], t["suffix"])
    tmp = os.path.join(cfg["paths"]["scratch"],
                       "smod-indicator-%s.tif" % os.path.basename(dst)[:-4])
    urban = set(cfg["smmod_urban_classes"])
    with rasterio.open(t["src"]) as ds:
        w = from_bounds(*SMOD_WINDOW, transform=ds.transform)
        a = ds.read(1, window=w)
        nod = ds.nodata
        win_transform = ds.window_transform(w)
        crs = ds.crs
    ind = np.full(a.shape, 255, dtype=np.uint8)
    valid = a != nod
    ind[valid] = np.isin(a[valid], list(urban)).astype(np.uint8)
    profile = dict(driver="GTiff", width=ind.shape[1], height=ind.shape[0], count=1,
                   dtype="uint8", crs=crs, transform=win_transform, nodata=255,
                   compress="deflate", tiled=True, blockxsize=256, blockysize=256)
    with rasterio.open(tmp, "w", **profile) as o:
        o.write(ind, 1)
    del a, ind
    common.warp_to_template(tmp, dst, cfg,
                            resampling=cfg["resampling"]["downscale_continuous"],
                            dtype="float32", src_nodata=255.0)
    os.remove(tmp)
    return dst


def worker(t):
    cfg = common.load_config()
    dst = common.layer_path(cfg, t["parts"], t["suffix"])
    try:
        if t["kind"] == "focal":
            base = common.layer_path(cfg, t["base"])
            if not os.path.exists(base):
                return dict(status="pending", dst=dst, note="base not ready")
        if os.path.exists(dst) and not common.force_rerun() \
                and common.check_alignment(dst, cfg):
            return dict(status="skip", dst=dst, note="exists & aligned")
        fn = {"warp": do_warp, "focal": do_focal, "smod": do_smod}[t["kind"]]
        fn(cfg, t)
        assert common.check_alignment(dst, cfg), "alignment check failed"
        with rasterio.open(dst) as ds:
            a = ds.read(1)
        v = a[~np.isnan(a)]
        stat = dict(n_valid=int(v.size),
                    vmin=float(v.min()) if v.size else None,
                    vmax=float(v.max()) if v.size else None)
        return dict(status="ok", dst=dst, src=t.get("src", ""), stat=stat, kind=t["kind"])
    except Exception as e:
        return dict(status="error", dst=dst, src=t.get("src", ""),
                    note="%s\n%s" % (e, traceback.format_exc()))


def main():
    cfg = common.load_config()
    tasks = build_manifest(cfg)
    names = [os.path.basename(common.layer_path(cfg, t["parts"], t["suffix"])) for t in tasks]
    assert len(set(names)) == len(names), "duplicate target filenames!"
    print("manifest: %d layers" % len(tasks))

    workers = int(cfg["runtime"]["workers"])
    results, pending = [], list(tasks)
    # focal 依赖 raw 层，分两轮：先非 focal，再 focal
    for round_tasks in ([t for t in pending if t["kind"] != "focal"],
                        [t for t in pending if t["kind"] == "focal"]):
        with mp.Pool(workers) as pool:
            for i, r in enumerate(pool.imap_unordered(worker, round_tasks), 1):
                results.append(r)
                print("[%d/%d] %s %s" % (i, len(round_tasks), r["status"].upper(),
                                         common.relpath(cfg, r["dst"])))
                if r["status"] == "error":
                    print("    ERROR:", r["note"].splitlines()[0])

    ok = [r for r in results if r["status"] == "ok"]
    skip = [r for r in results if r["status"] == "skip"]
    err = [r for r in results if r["status"] == "error"]
    print("=" * 60)
    print("ok=%d skip=%d error=%d" % (len(ok), len(skip), len(err)))

    rpt = os.path.join(cfg["paths"]["logs"], "p3_timeseries_value_report.csv")
    with open(rpt, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["relpath", "source", "n_valid", "vmin", "vmax"])
        for r in sorted(results, key=lambda x: x.get("dst") or ""):
            if r["status"] in ("ok", "skip"):
                s = r.get("stat") or {}
                if not s and os.path.exists(r["dst"]):
                    with rasterio.open(r["dst"]) as ds:
                        a = ds.read(1)
                    v = a[~np.isnan(a)]
                    s = dict(n_valid=int(v.size),
                             vmin=float(v.min()) if v.size else None,
                             vmax=float(v.max()) if v.size else None)
                w.writerow([common.relpath(cfg, r["dst"]), r.get("src", ""),
                            s.get("n_valid", ""), s.get("vmin", ""), s.get("vmax", "")])
    print("value report:", rpt)

    common.lineage(cfg, [
        dict(relpath=common.relpath(cfg, r["dst"]), source=r.get("src", ""),
             script=SCRIPT, note="kind=%s" % r.get("kind", ""))
        for r in ok
    ])

    errs = common.validate_naming(cfg)
    print("naming validator errors:", len(errs))
    for e in errs[:10]:
        print("  ", e)

    assert not err and not errs, "03 has errors; see above"
    print("03 DONE")


if __name__ == "__main__":
    main()
