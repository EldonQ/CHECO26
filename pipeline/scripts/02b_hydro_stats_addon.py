"""P2b hydro 精选统计增补（2026-08-08 定案）：Hydrography90m 90m 源 -> 1km 窗口极值统计。
只补有生态语义的统计量（config hydro_stats_addon，入库前审计定案后 19 层）：
  minmax 组 8 变量 x (min,max) = 16；maxonly 组 3 变量 x max = 3。
  （cti / channel_grad 3 变量因源产品单位异常于入库前审计定案移除，见 config 注释）
stream_dist_* 4 变量归 dist 主题，其余归 hydro 主题（与 02 一致）。
逐层：warp(GDAL min/max 重采样, nodata 感知) -> cm->m 单位换算(查 config scale_cm2m)
-> 中国掩膜 -> 模板四查 -> 方差筛查(拦截常量层) -> 值域报告 -> 谱系。幂等可重跑。"""
import multiprocessing as mp
import os
import sys

import numpy as np
import rasterio

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

SCRIPT = "02b_hydro_stats_addon.py"
DIST_VARS = ["stream_dist_proximity", "stream_dist_dw_near",
             "stream_dist_up_near", "stream_dist_up_farth"]


def build_manifest(cfg):
    addon = cfg["hydro_stats_addon"]
    scale_set = set(cfg["hydro90m_vars"]["scale_cm2m"])
    withdrawn = set(cfg["hydro90m_vars"].get("withdrawn", []))
    tasks = []
    for v in addon["minmax"]:
        if v in withdrawn:
            continue
        for st in ("min", "max"):
            tasks.append((v, st))
    for v in addon["maxonly"]:
        if v in withdrawn:
            continue
        tasks.append((v, "max"))
    out = []
    for v, st in tasks:
        if v in DIST_VARS:
            parts = ["glo", "dist", "h90m", v.replace("_", "-")]
        else:
            parts = ["glo", "hydro", "h90m", v.replace("_", "-")]
        src = os.path.join(cfg["paths"]["hydro_final"], v, "%s_china.tif" % v)
        out.append(dict(
            parts=parts, suffix="_%s" % st, var=v, stat=st, src=src,
            scale=0.01 if v in scale_set else None,
        ))
    return out


def worker(t):
    cfg = common.load_config()
    dst = common.layer_path(cfg, t["parts"], t["suffix"])
    if os.path.exists(dst) and not common.force_rerun() and common.check_alignment(dst, cfg):
        return dict(status="skip", dst=dst, src=t["src"], var=t["var"], stat=t["stat"])
    if not os.path.exists(t["src"]):
        return dict(status="error", dst=dst, src=t["src"], var=t["var"], stat=t["stat"],
                    err="source missing: %s" % t["src"])
    common.warp_to_template(t["src"], dst, cfg,
                            resampling=cfg["resampling"]["downscale_%s" % t["stat"]],
                            dtype="float32", src_nodata=-9999.0, scale=t["scale"])
    # ---- 逐层自检：模板四查 + 方差筛查（拦截常量/空层） ----
    assert common.check_alignment(dst, cfg), "alignment check failed: %s" % dst
    with rasterio.open(dst) as ds:
        a = ds.read(1)
        nod = ds.nodata
    v = a[~np.isnan(a)] if a.dtype.kind == "f" else a.ravel()
    if nod is not None:
        v = v[v != nod]
    if v.size == 0:
        return dict(status="error", dst=dst, src=t["src"], var=t["var"], stat=t["stat"],
                    err="empty layer")
    vmin, vmax = float(v.min()), float(v.max())
    span = vmax - vmin
    rel_span = span / max(abs(vmax), 1e-9)
    if rel_span < 1e-6:
        return dict(status="error", dst=dst, src=t["src"], var=t["var"], stat=t["stat"],
                    err="near-constant layer rejected: [%.6g, %.6g]" % (vmin, vmax))
    return dict(status="ok", dst=dst, src=t["src"], var=t["var"], stat=t["stat"],
                n_valid=int(v.size), vmin=vmin, vmax=vmax)


def main():
    cfg = common.load_config()
    tasks = build_manifest(cfg)
    print("hydro stats addon tasks:", len(tasks))
    results = []
    # 90m 全国源单 warp 内存占用大，限制并发
    with mp.Pool(min(len(tasks), 4)) as pool:
        for i, r in enumerate(pool.imap_unordered(worker, tasks), 1):
            results.append(r)
            print("[%2d/%d] %-8s %-24s %-3s %s" % (
                i, len(tasks), r["status"], r["var"], r["stat"],
                r.get("err", "[%.4g, %.4g] n=%d" % (r["vmin"], r["vmax"], r["n_valid"])
                     if r["status"] == "ok" else "")))
    errs = [r for r in results if r["status"] == "error"]
    ok = [r for r in results if r["status"] == "ok"]
    skipped = [r for r in results if r["status"] == "skip"]
    for e in errs:
        print("ERROR:", e["dst"], e["err"])
    # 谱系
    common.lineage(cfg, [dict(relpath=common.relpath(cfg, r["dst"]),
                              source=r["src"], script=SCRIPT,
                              note="hydro_stats_addon %s (GDAL %s resampling)" % (r["stat"], r["stat"]))
                         for r in ok + skipped if "src" in r])
    assert not errs and len(results) == len(tasks)
    print("02b DONE: ok=%d skipped=%d" % (len(ok), len(skipped)))


if __name__ == "__main__":
    main()
