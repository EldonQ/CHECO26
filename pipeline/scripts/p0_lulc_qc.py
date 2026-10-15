"""P0 质检：glu1km history_2020 中国区分类别面积（对照量级用），输出 logs/p0_lulc_qc.csv。"""
import os
import sys

import numpy as np
import rasterio

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common


def main():
    cfg = common.load_config()
    spec = common.grid_spec(cfg)
    src = os.path.join(cfg["paths"]["lulc_raw"], "history_2020.tif")

    # warp 到模板（分类层 nearest；源值 0=背景，落盘置 255）
    qc_dir = os.path.join(cfg["paths"]["scratch"])
    os.makedirs(qc_dir, exist_ok=True)
    tmp = os.path.join(qc_dir, "p0_history2020_albers.tif")
    common.warp_to_template(src, tmp, cfg,
                            resampling=cfg["resampling"]["categorical"],
                            dtype="uint8", src_nodata=0)

    with rasterio.open(tmp) as ds:
        a = ds.read(1)
    with rasterio.open(os.path.join(cfg["paths"]["root"], "data", "mask_china.tif")) as ds:
        m = ds.read(1) == 1

    a = np.where(m, a, 0)
    legend = {int(k): v for k, v in cfg["lulc_legend"].items()}
    total = int((a > 0).sum())
    rows = []
    for code in sorted(legend):
        n = int((a == code).sum())
        rows.append({
            "code": code, "class": legend[code], "cells": n,
            "km2": n,  # 1km 像元
            "pct_of_valid": round(n / total * 100, 3) if total else 0.0,
        })
    print("valid cells in China mask:", total, "(%.1f 万 km2)" % (total / 1e4))
    for r in rows:
        print("%(code)d %(class)-10s %(km2)10d km2  %(pct_of_valid)6.2f%%" % r)

    out = os.path.join(cfg["paths"]["logs"], "p0_lulc_qc.csv")
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = list(rows[0].keys())
        import csv
        cw = csv.DictWriter(f, fieldnames=w)
        cw.writeheader()
        cw.writerows(rows)
    print("written:", out)
    os.remove(tmp)


if __name__ == "__main__":
    main()
