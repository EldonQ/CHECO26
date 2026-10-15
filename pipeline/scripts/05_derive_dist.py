"""P3 距离派生（dist 主题 5 层，河流邻近 4 层已在 02 入 dist/h90m）：
到道路全路网（GRIP4）、到主干道（GRIP4 Highways+Primary+Secondary）、到步道（OSM path/footway）、
到城市（GHS-SMOD E2020 类 21-23）、到水体（GSW extent 季节+永久）。
方法：要素矢量栅格化到 Albers 1km 模板(all_touched) -> scipy 欧氏距离(m)。幂等。"""
import glob
import multiprocessing as mp
import os
import sys
import traceback

import numpy as np
import pyogrio
import rasterio
from rasterio.features import rasterize
from rasterio.windows import from_bounds
from scipy.ndimage import distance_transform_edt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

SCRIPT = "05_derive_dist.py"

# 中国区要素读取范围（含缓冲，度）；仅 GRIP4（region6 全亚洲）需要 bbox 裁剪
FEAT_BBOX = (72.5, 17.0, 136.5, 55.5)
SMOD_EPOCH = 2020                                                # 城市距离基准 epoch
SMOD_WINDOW = (72.5, 17.0, 136.5, 55.5)


def rasterize_vectors(cfg, geometries, out_shape, transform):
    """要素栅格化为 0/1 特征层（all_touched）。几何必须已投影到模板 CRS。"""
    return rasterize(
        geometries, out_shape=out_shape, transform=transform,
        fill=0, default_value=1, all_touched=True, dtype=np.uint8)


def dist_from_feature(feat, cfg):
    """特征层 -> 欧氏距离(m)：到最近特征像元的距离；特征像元=0。"""
    res = float(cfg["grid"]["resolution"])
    d = distance_transform_edt(feat == 0) * res
    return d.astype(np.float32)


def _rasterize_geoms(cfg, geoms):
    spec = common.grid_spec(cfg)
    return rasterize_vectors(cfg, geoms, (spec["height"], spec["width"]), spec["transform"])


def feat_grip4(cfg, major_only):
    src = os.path.join(cfg["paths"]["grip4_root"], "GRIP4_region6.shp")
    field = cfg["grip4_field"]
    kw = dict(bbox=FEAT_BBOX)
    desc = "gp_rtp=all"
    if major_only:
        codes = cfg["grip4_major_codes"]
        kw["where"] = "%s IN (%s)" % (field, ",".join(str(c) for c in codes))
        desc = "gp_rtp IN %s (Highways/Primary/Secondary)" % codes
    gdf = pyogrio.read_dataframe(src, **kw)
    spec = common.grid_spec(cfg)
    gdf = gdf.to_crs(spec["crs"])          # 4326 -> China_Albers，再栅格化
    geoms = [g for g in gdf.geometry if g is not None and not g.is_empty]
    return _rasterize_geoms(cfg, geoms), "GRIP4_region6.shp %s" % desc


def feat_osm_trail(cfg):
    # pbf 即中国区抽取（total_bounds 73.4-134.8E），无需 bbox；where 下推 OGR
    gdf = pyogrio.read_dataframe(cfg["paths"]["osm_pbf"], layer="lines",
                                 where=cfg["osm_trail_where"])
    spec = common.grid_spec(cfg)
    gdf = gdf.to_crs(spec["crs"])
    geoms = [g for g in gdf.geometry if g is not None and not g.is_empty]
    return _rasterize_geoms(cfg, geoms), "china osm.pbf lines %s" % cfg["osm_trail_where"]


def feat_smod_urban(cfg):
    d = "GHS_SMOD_E%d_GLOBE_R2023A_4326_30ss_V2_0" % SMOD_EPOCH
    src = os.path.join(cfg["paths"]["smod_ghs"], d, d + ".tif")
    urban = set(cfg["smmod_urban_classes"])
    with rasterio.open(src) as ds:
        w = from_bounds(*SMOD_WINDOW, transform=ds.transform)
        a = ds.read(1, window=w)
        nod = ds.nodata
        win_transform = ds.window_transform(w)
    feat_src = np.zeros(a.shape, dtype=np.uint8)
    valid = a != nod
    feat_src[valid] = np.isin(a[valid], list(urban)).astype(np.uint8)
    # 源特征栅格 -> 模板（nearest 聚合 30s->1km: 任一源像元为城市则该目标像元=1）
    spec = common.grid_spec(cfg)
    dst = np.zeros((spec["height"], spec["width"]), dtype=np.uint8)
    from rasterio.warp import reproject
    from rasterio.enums import Resampling
    reproject(source=feat_src, destination=dst,
              src_transform=win_transform, src_crs="EPSG:4326", src_nodata=None,
              dst_crs=spec["crs"], dst_transform=spec["transform"], dst_nodata=None,
              resampling=Resampling.max)
    return dst, "GHS-SMOD E%d classes 21-23" % SMOD_EPOCH


def feat_gsw_water(cfg):
    """42 片 GSW extent 逐片 warp nearest 到模板后取并集（extent>0 且非无效值 = 水体）。"""
    spec = common.grid_spec(cfg)
    invalid = int(cfg["gsw_invalid_value"])
    tiles = sorted(glob.glob(os.path.join(cfg["paths"]["gsw_extent"], "extent_*.tif")))
    assert len(tiles) == 42, "GSW extent tiles != 42: %d" % len(tiles)
    union = np.zeros((spec["height"], spec["width"]), dtype=np.uint8)
    for t in tiles:
        dst = np.zeros((spec["height"], spec["width"]), dtype=np.uint8)
        with rasterio.Env(GDAL_NUM_THREADS=str(cfg["runtime"]["gdal_threads"])):
            with rasterio.open(t) as src_ds:
                from rasterio.warp import reproject
                from rasterio.enums import Resampling
                reproject(source=rasterio.band(src_ds, 1), destination=dst,
                          dst_crs=spec["crs"], dst_transform=spec["transform"],
                          dst_nodata=invalid, src_nodata=invalid,
                          resampling=Resampling.nearest)
        union = np.maximum(union, ((dst > 0) & (dst != invalid)).astype(np.uint8))
    return union, "GSW extent v1.5 42 tiles (seasonal+permanent, excl 255)"


TASKS = [
    (["glo", "dist", "grip4", "road"], feat_grip4, dict(major_only=False)),
    (["glo", "dist", "grip4", "majorroad"], feat_grip4, dict(major_only=True)),
    (["glo", "dist", "osm", "trail"], feat_osm_trail, dict()),
    (["glo", "dist", "smod", "urban"], feat_smod_urban, dict()),
    (["glo", "dist", "gsw", "water"], feat_gsw_water, dict()),
]


def worker(item):
    parts, fn, kw = item
    cfg = common.load_config()
    dst = common.layer_path(cfg, parts)
    try:
        if os.path.exists(dst) and not common.force_rerun() \
                and common.check_alignment(dst, cfg):
            return dict(status="skip", dst=dst)
        feat, src_desc = fn(cfg, **kw)
        nfeat = int((feat > 0).sum())
        assert nfeat > 0, "feature raster is empty, source filter/bbox mismatch"
        # 距离在全网格计算（保留境外要素上下文，边界处距离才正确），落盘前掩膜限回中国区内
        d = dist_from_feature(feat, cfg)
        common.apply_china_mask(d, cfg, np.nan)
        common.atomic_write_raster(dst, d, cfg, dtype="float32",
                                   nodata=cfg["nodata"]["float"])
        assert common.check_alignment(dst, cfg)
        with rasterio.open(dst) as ds:
            a = ds.read(1)
        v = a[~np.isnan(a)]
        return dict(status="ok", dst=dst, src=src_desc, nfeat=nfeat,
                    vmin=float(v.min()), vmax=float(v.max()))
    except Exception as e:
        return dict(status="error", dst=dst,
                    note="%s\n%s" % (e, traceback.format_exc()))


def main():
    cfg = common.load_config()
    results = []
    with mp.Pool(len(TASKS)) as pool:
        for r in pool.imap_unordered(worker, TASKS):
            print(r["status"].upper(), common.relpath(cfg, r["dst"]),
                  r.get("src", ""), r.get("nfeat", ""),
                  ("vmin=%.1f vmax=%.1f" % (r["vmin"], r["vmax"])) if r["status"] == "ok" else "")
            if r["status"] == "error":
                print("   ERROR:", r["note"].splitlines()[0])
            results.append(r)

    err = [r for r in results if r["status"] == "error"]
    common.lineage(cfg, [
        dict(relpath=common.relpath(cfg, r["dst"]), source=r.get("src", ""),
             script=SCRIPT, note="euclidean distance to feature, m")
        for r in results if r["status"] == "ok"
    ])
    errs = common.validate_naming(cfg)
    print("naming validator errors:", len(errs))
    for e in errs[:10]:
        print("  ", e)
    assert not err and not errs
    print("05 DONE")


if __name__ == "__main__":
    main()
