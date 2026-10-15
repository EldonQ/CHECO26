"""P4 未来气候链：bioclim 未来 504 层（2 链 ensmean/bcc_csm2_mr × 3 SSP × 3 时段中心年 × 28 变量）。
目录口径：glo/bioclim/cnclim1km-{chain}/scenario/{2030|2055|2085}/{ssp}/{var}（深度 7）。
N-SDM 2.0.1 要求情景层位于名为 scenario 的子文件夹且顺序为 scenario/<year>/<scenario>。
链并入数据集名（连字符连接，文件夹名不含下划线），保证两链同名变量文件名唯一。
源时段 -> 中心年映射与链清单全部来自 config climate 区块。幂等可重跑。"""
import csv
import multiprocessing as mp
import os
import sys
import traceback

import numpy as np
import rasterio

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

SCRIPT = "07_future_chains.py"

BIOCLIM_VARS = ["bio%02d" % i for i in range(1, 24)] + ["prec", "sunp", "tave", "tmax", "tmin"]


def build_manifest(cfg):
    P = cfg["paths"]
    clim = cfg["climate"]
    tasks = []
    for chain in clim["chains"]:
        dsname = "cnclim1km-" + chain.replace("_", "-")   # 链入数据集名，连字符连接
        for cyear, speriod in clim["periods"].items():
            for ssp in clim["ssps"]:
                for v in BIOCLIM_VARS:
                    src = os.path.join(
                        P["bioclim"], "cnclim1km_%s" % chain, "future", speriod,
                        ssp, v, "bioclim_cnclim1km_%s_future_%s_%s_%s.tif" % (
                            chain, speriod, ssp, v))
                    tasks.append(dict(
                        parts=["glo", "bioclim", dsname, "scenario", cyear, ssp, v],
                        src=src, chain=chain, cyear=cyear, speriod=speriod, ssp=ssp, v=v))
    return tasks


def worker(t):
    cfg = common.load_config()
    dst = common.layer_path(cfg, t["parts"])
    try:
        if os.path.exists(dst) and not common.force_rerun() \
                and common.check_alignment(dst, cfg):
            return dict(status="skip", dst=dst)
        if not os.path.exists(t["src"]):
            return dict(status="error", dst=dst, src=t["src"],
                        note="source missing: %s" % t["src"])
        common.warp_to_template(t["src"], dst, cfg,
                                resampling=cfg["resampling"]["continuous"],
                                dtype="float32", src_nodata=None, scale=None)
        assert common.check_alignment(dst, cfg), "alignment check failed"
        with rasterio.open(dst) as ds:
            a = ds.read(1)
        v = a[~np.isnan(a)]
        return dict(status="ok", dst=dst, src=t["src"],
                    stat=dict(n_valid=int(v.size),
                              vmin=float(v.min()) if v.size else None,
                              vmax=float(v.max()) if v.size else None))
    except Exception as e:
        return dict(status="error", dst=dst, src=t.get("src"),
                    note="%s\n%s" % (e, traceback.format_exc()))


def main():
    cfg = common.load_config()
    tasks = build_manifest(cfg)
    assert len(tasks) == 504, "future bioclim manifest != 504: %d" % len(tasks)
    names = [os.path.basename(common.layer_path(cfg, t["parts"])) for t in tasks]
    assert len(set(names)) == len(names), "duplicate target filenames!"
    print("manifest: %d layers" % len(tasks))

    results = []
    with mp.Pool(int(cfg["runtime"]["workers"])) as pool:
        for i, r in enumerate(pool.imap_unordered(worker, tasks), 1):
            results.append(r)
            print("[%d/%d] %s %s" % (i, len(tasks), r["status"].upper(),
                                     common.relpath(cfg, r["dst"]) if r.get("dst") else ""))
            if r["status"] == "error":
                print("    ERROR:", r["note"].splitlines()[0])

    ok = [r for r in results if r["status"] == "ok"]
    skip = [r for r in results if r["status"] == "skip"]
    err = [r for r in results if r["status"] == "error"]
    print("=" * 60)
    print("ok=%d skip=%d error=%d" % (len(ok), len(skip), len(err)))

    # 值域报告
    rpt = os.path.join(cfg["paths"]["logs"], "p4_value_report.csv")
    with open(rpt, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["relpath", "source", "n_valid", "vmin", "vmax"])
        for r in sorted(results, key=lambda x: x.get("dst") or ""):
            if r["status"] in ("ok", "skip"):
                s = r.get("stat")
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
    by_dst = {common.layer_path(cfg, t["parts"]): t for t in tasks}
    common.lineage(cfg, [
        dict(relpath=common.relpath(cfg, r["dst"]), source=r.get("src", ""),
             script=SCRIPT,
             note="P4 future chain=%s period=%s->%s ssp=%s var=%s" % (
                 by_dst[r["dst"]]["chain"], by_dst[r["dst"]]["speriod"],
                 by_dst[r["dst"]]["cyear"], by_dst[r["dst"]]["ssp"],
                 by_dst[r["dst"]]["v"]))
        for r in ok
    ])

    # 情景命名与配对校验：每链 x 每 SSP x 每中心年必须恰好 28 层
    from collections import Counter
    cnt = Counter()
    for r in results:
        if r["status"] in ("ok", "skip"):
            t = by_dst[r["dst"]]
            cnt[(t["chain"], t["ssp"], t["cyear"])] += 1
    bad = [k for k, c in cnt.items() if c != 28]
    assert len(cnt) == len(cfg["climate"]["chains"]) * 3 * 3, "scenario combos missing"
    assert not bad, "scenario pairing incomplete: %s" % bad

    errs = common.validate_naming(cfg)
    print("naming validator errors:", len(errs))
    for e in errs[:10]:
        print("  ", e)
    assert not err and not errs, "P4 has errors; see above"
    print("P4 DONE")


if __name__ == "__main__":
    main()
