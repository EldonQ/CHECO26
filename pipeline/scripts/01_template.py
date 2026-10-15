"""P1 基准：生成 template_albers1km.tif（值=1）与 mask_china.tif，并自检。
产出位于 N-SDM/data/（不入 covariates 命名树）。"""
import os
import sys

import numpy as np
import pyogrio
import rasterio
from rasterio.features import rasterize

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common


def main():
    cfg = common.load_config()
    spec = common.grid_spec(cfg)
    data_dir = os.path.join(cfg["paths"]["root"], "data")
    os.makedirs(data_dir, exist_ok=True)

    print("grid: %d cols x %d rows @ %.0f m" % (spec["width"], spec["height"], spec["res"]))

    # ---- template（值=1）----
    tpl = os.path.join(data_dir, "template_albers1km.tif")
    arr = np.ones((spec["height"], spec["width"]), dtype=np.uint8)
    common.atomic_write_raster(tpl, arr, cfg, dtype="uint8", nodata=None)
    print("written:", tpl)

    # ---- mask（china.shp 栅格化, all_touched 取 config）----
    gdf = pyogrio.read_dataframe(cfg["paths"]["china_shp"])
    gdf = gdf.to_crs(spec["crs"])
    geoms = [g for g in gdf.geometry if g is not None and not g.is_empty]
    mask = rasterize(
        geoms,
        out_shape=(spec["height"], spec["width"]),
        transform=spec["transform"],
        fill=0,
        default_value=1,
        all_touched=bool(cfg["mask"]["all_touched"]),
        dtype=np.uint8,
    )
    msk = os.path.join(data_dir, "mask_china.tif")
    common.atomic_write_raster(msk, mask, cfg, dtype="uint8", nodata=None)
    n_valid = int((mask == 1).sum())
    print("written:", msk, "| valid cells:", n_valid,
          "(%.1f km2)" % (n_valid * spec["res"] ** 2 / 1e6))

    # ---- 自检：模板四查 + 覆盖完整性 ----
    assert common.check_alignment(tpl, cfg), "template alignment check failed"
    assert common.check_alignment(msk, cfg), "mask alignment check failed"
    b = gdf.total_bounds
    xmin, ymin, xmax, ymax = cfg["grid"]["xmin"], cfg["grid"]["ymin"], cfg["grid"]["xmax"], cfg["grid"]["ymax"]
    assert b[0] >= xmin and b[1] >= ymin and b[2] <= xmax and b[3] <= ymax, \
        "china.shp bounds exceed template!"
    print("alignment & coverage checks: PASS")

    # ---- 命名校验器自检（空树应 0 错误）----
    errs = common.validate_naming(cfg)
    print("naming validator errors:", len(errs))
    for e in errs[:10]:
        print("  ", e)
    assert not errs

    common.lineage(cfg, [
        {"relpath": "../data/template_albers1km.tif", "source": cfg["paths"]["china_shp"],
         "script": "01_template.py", "note": "template value=1"},
        {"relpath": "../data/mask_china.tif", "source": cfg["paths"]["china_shp"],
         "script": "01_template.py",
         "note": "all_touched=%s, valid=%d" % (cfg["mask"]["all_touched"], n_valid)},
    ])
    print("P1 DONE")


if __name__ == "__main__":
    main()
