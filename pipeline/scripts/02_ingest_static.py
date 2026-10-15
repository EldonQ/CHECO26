"""P2 静态迁移：bioclim 现状 28 + soil 168 + topo 2 + hydro/dist 40 + vege 3 = 241 层。
manifest 驱动、层间进程池并行、逐层模板四查+值域记录、谱系留痕。幂等可重跑。"""
import csv
import glob
import multiprocessing as mp
import os
import sys
import traceback

import numpy as np
import rasterio

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

SCRIPT = "02_ingest_static.py"

BIOCLIM_VARS = ["bio%02d" % i for i in range(1, 24)] + ["prec", "sunp", "tave", "tmax", "tmin"]
SOIL_DEPTHS = [("0-5", "0"), ("5-15", "5"), ("15-30", "15"), ("30-60", "30"),
               ("60-100", "60"), ("100-200", "100")]
SOIL_ATTR_DIR = {
    "AK": "ak", "AN": "an", "AP": "ap", "BD": "bd", "CEC": "cec",
    "Dry_B": "dry-b", "Dry_G": "dry-g", "Dry_R": "dry-r",
    "Dry_chroma": "dry-chroma", "Dry_hue": "dry-hue", "Dry_value": "dry-value",
    "OC": "oc", "SOCD": "socd", "TK": "tk", "TN": "tn", "TP": "tp",
    "Wet_B": "wet-b", "Wet_G": "wet-g", "Wet_R": "wet-r",
    "Wet_chroma": "wet-chroma", "Wet_hue": "wet-hue", "Wet_value": "wet-value",
    "clay": "clay", "gravel": "gravel", "pH": "ph", "porosity": "porosity",
    "sand": "sand", "silt": "silt",
}
DIST_VARS = ["stream_dist_proximity", "stream_dist_dw_near",
             "stream_dist_up_near", "stream_dist_up_farth"]


def build_manifest(cfg):
    """返回任务列表；每项 dict(parts, src, rule, scale, src_nodata, expect)。"""
    P = cfg["paths"]
    tasks = []

    # ---- bioclim 现状 28（0.01° WGS84 -> Albers，bilinear）----
    for v in BIOCLIM_VARS:
        src = os.path.join(P["bioclim"], "cnclim1km", "present", "1991_2020", v,
                           "bioclim_cnclim1km_present_1991_2020_%s.tif" % v)
        tasks.append(dict(parts=["glo", "bioclim", "cnclim1km", "present", v],
                          src=src, rule="continuous", scale=None, src_nodata=None))

    # ---- soil CSDLv2 1km：28 属性 x 6 深度 = 168（单位换算见 config units_scale）----
    us = cfg["units_scale"]["soil_csdlv2"]
    for attr, adir in SOIL_ATTR_DIR.items():
        scale = float(us.get(attr, us["default"]))
        for dsrc, dname in SOIL_DEPTHS:
            hits = sorted(glob.glob(os.path.join(P["soil_1km"], "GTiff", attr,
                                                 "%s_%scm_1km*.tif" % (attr, dsrc))))
            hits = [h for h in hits if not h.endswith(".aux.xml")]
            assert len(hits) == 1, "soil source ambiguous/missing: %s %s -> %s" % (attr, dsrc, hits)
            tasks.append(dict(parts=["glo", "soil", "csdlv2", adir, dname],
                              src=hits[0], rule="continuous", scale=scale, src_nodata=-32768.0))

    # ---- topo elev/slope（chdem 1km Albers-Krassovsky -> WGS84-Albers，bilinear）----
    tasks.append(dict(parts=["glo", "topo", "chinadem", "elev"],
                      src=r"E:\CHECO26\DEM\China_DEM_1km\Albers_105\DEM\chdem_105.tif",
                      rule="continuous", scale=None, src_nodata=-32768.0))
    tasks.append(dict(parts=["glo", "topo", "chinadem", "slope"],
                      src=r"E:\CHECO26\DEM\China_DEM_1km\Albers_105\TIFF\chdem_Slope.tif",
                      rule="continuous", scale=None, src_nodata=None))

    # ---- hydro 36 + dist 河流 4（Hydrography90m 90m 源，聚合降尺度）----
    hcfg = cfg["hydro90m_vars"]
    scale_set = set(hcfg["scale_cm2m"])
    withdrawn = set(hcfg.get("withdrawn", []))     # 源产品数值不可用，已撤出交付
    for v in hcfg["categorical"] + hcfg["continuous"]:
        if v in withdrawn:
            continue
        src = os.path.join(P["hydro_final"], v, "%s_china.tif" % v)
        cat = v in hcfg["categorical"]
        if v in DIST_VARS:
            parts = ["glo", "dist", "h90m", v.replace("_", "-")]
        else:
            parts = ["glo", "hydro", "h90m", v.replace("_", "-")]
        tasks.append(dict(parts=parts, src=src,
                          rule="downscale_categorical" if cat else "downscale_continuous",
                          scale=0.01 if v in scale_set else None,
                          # 分类层 nodata 实测各异（uint8/uint32=0, int16/int32=-9999）：用源自带值
                          src_nodata=None if cat else -9999.0))

    # ---- vege 静态 3 层 ----
    tasks.append(dict(parts=["glo", "vege", "agb2019", "agb"],
                      src=os.path.join(P["agb"], "China_Forest_AGB_2019.tif"),
                      rule="downscale_continuous", scale=None, src_nodata=None))
    tasks.append(dict(parts=["glo", "vege", "ch2019", "ch"],
                      src=os.path.join(P["canopy_height"], "China_Forest_Canopy_Height_2019.tif"),
                      rule="downscale_continuous", scale=float(cfg["units_scale"]["canopy_height"]),
                      src_nodata=65535.0))
    tasks.append(dict(parts=["glo", "vege", "catcd", "treecover"],
                      src=P["catcd"], rule="downscale_continuous", scale=None,
                      src_nodata=-128.0))
    return tasks


def worker(t):
    """单任务：warp -> 四查 -> 值域统计。返回结果 dict。"""
    cfg = common.load_config()
    dst = common.layer_path(cfg, t["parts"])
    resamp = cfg["resampling"][t["rule"]]
    try:
        if os.path.exists(dst) and not common.force_rerun():
            ok = common.check_alignment(dst, cfg)
            if ok:
                return dict(status="skip", dst=dst, note="exists & aligned")
        common.warp_to_template(t["src"], dst, cfg, resampling=resamp,
                                dtype="float32", src_nodata=t["src_nodata"],
                                scale=t["scale"])
        assert common.check_alignment(dst, cfg), "alignment check failed"
        with rasterio.open(dst) as ds:
            a = ds.read(1)
        v = a[~np.isnan(a)]
        stat = dict(n_valid=int(v.size),
                    vmin=float(v.min()) if v.size else None,
                    vmax=float(v.max()) if v.size else None)
        return dict(status="ok", dst=dst, src=t["src"], stat=stat)
    except Exception as e:
        return dict(status="error", dst=dst, src=t.get("src"),
                    note="%s\n%s" % (e, traceback.format_exc()))


def main():
    cfg = common.load_config()
    tasks = build_manifest(cfg)
    # 校验目标文件名全局唯一
    names = [os.path.basename(common.layer_path(cfg, t["parts"])) for t in tasks]
    assert len(set(names)) == len(names), "duplicate target filenames!"
    print("manifest: %d layers" % len(tasks))

    workers = int(cfg["runtime"]["workers"])
    results = []
    with mp.Pool(workers) as pool:
        for i, r in enumerate(pool.imap_unordered(worker, tasks), 1):
            results.append(r)
            tag = r["status"].upper()
            print("[%d/%d] %s %s" % (i, len(tasks), tag,
                                     common.relpath(cfg, r["dst"]) if r.get("dst") else ""))
            if r["status"] == "error":
                print("    ERROR:", r["note"].splitlines()[0])

    ok = [r for r in results if r["status"] == "ok"]
    skip = [r for r in results if r["status"] == "skip"]
    err = [r for r in results if r["status"] == "error"]
    print("=" * 60)
    print("ok=%d skip=%d error=%d" % (len(ok), len(skip), len(err)))

    # 值域报告
    rpt = os.path.join(cfg["paths"]["logs"], "p2_value_report.csv")
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

    # 谱系
    common.lineage(cfg, [
        dict(relpath=common.relpath(cfg, r["dst"]), source=r.get("src", ""),
             script=SCRIPT, note="P2 warp rule=%s" % next(
                 (t["rule"] for t in tasks if common.layer_path(cfg, t["parts"]) == r["dst"]), ""))
        for r in ok
    ])

    # 命名校验
    errs = common.validate_naming(cfg)
    print("naming validator errors:", len(errs))
    for e in errs[:10]:
        print("  ", e)

    assert not err and not errs, "P2 has errors; see above"
    print("P2 DONE")


if __name__ == "__main__":
    main()
