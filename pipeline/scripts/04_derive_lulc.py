"""P3 LULC 派生：glu1km 每快照 54 层 = 6 类比例 x(1+4 focal) + Shannon 4 focal
+ 边缘密度 x(1+4 focal) + 斑块密度/平均斑块大小 x 2 口径(all/forest) x 4 focal
（例外：patchdensity-all_f1000 为数学必然常量层——全国陆地 4 邻域几乎全连通，
1km 窗口内恒 1 斑块，零信息量，建模会零方差除零，不产出；2026-08-07 审计定案）。
快照 = history_2020 + ssp126/245/585 x 2030/2050/2100，共 10 快照 x 54 = 540 层。
口径：比例先行、窗口后置（SWECO25 同款）；Shannon=-sum(p*ln p) 自然对数；
边缘密度=FRAGSTATS 4 邻域类别不同即边缘；斑块指标=锚点近似+圆盘窗口（定义见 config derivations）。
幂等可重跑。"""
import csv
import multiprocessing as mp
import os
import sys
import traceback

import numpy as np
import rasterio
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

SCRIPT = "04_derive_lulc.py"

SNAPSHOTS = [("2020", None, None, "history_2020.tif")]   # (目录年, ssp, 文件年, 源文件)
for ssp_dir, ssp_file in [("ssp126", "ssp1_26"), ("ssp245", "ssp2_45"), ("ssp585", "ssp5_85")]:
    for y in (2030, 2050, 2100):
        SNAPSHOTS.append((str(y), ssp_dir, y, "%s_%d.tif" % (ssp_file, y)))


def snapshot_parts(cfg, snap, extra):
    year, ssp, _, _ = snap
    if ssp is None:
        return ["glo", "lulc", "glu1km", year] + extra
    # N-SDM 2.0.1 covinfo 硬编码 scenario=倒数第2级、year=倒数第3级：scenario/<year>/<ssp>
    return ["glo", "lulc", "glu1km", "scenario", year, ssp] + extra


def edge_indicator(cls, valid):
    """FRAGSTATS 口径：与 4 邻域任一有效像元类别不同即为边缘。"""
    e = np.zeros(cls.shape, dtype=bool)
    for sh in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
        nb = np.roll(cls, sh, axis=(0, 1))
        nv = np.roll(valid, sh, axis=(0, 1))
        e |= (nv & (nb != cls))
    e &= valid
    return e


def patch_metric(binary, radius_cells):
    """圆盘窗口斑块密度（个/100km2）与平均斑块大小（km2）。
    口径：窗口与斑块相交即计入。锚点近似+自属补丁：
    1) 每斑块取扫描序首像元为唯一锚点，窗口内锚点数经圆盘卷积得到；
    2) 像元若在本斑块内但其锚点在窗外（超大斑块内部场景），补计 1 个斑块
       与其面积（向量化：逐像元比对自属锚点坐标）；
    3) 残余近似：窗外相交且锚点在窗外的其它斑块不计（仅窗口边界少量像元）。
    等面积 Albers 1km 网格：斑块像元数即 km2。
    卷积取整消除 FFT 舍入噪声（超大斑块下 FFT 会产生 ~1e-9 负噪声）。"""
    if not binary.any():
        nan = np.full(binary.shape, np.nan, dtype=np.float32)
        return nan, nan
    four = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], dtype=np.int32)
    labels, n = ndi.label(binary, structure=four)   # 4 邻域连通
    areas = np.bincount(labels.ravel())             # areas[0]=背景
    patch_area = areas[labels].astype(np.int64)
    ys, xs = np.nonzero(labels)
    lab_ids, first_idx = np.unique(labels[ys, xs], return_index=True)
    # 逐斑块唯一锚点 = 扫描序首像元
    anc_y = np.zeros(n + 1, dtype=np.int32)
    anc_x = np.zeros(n + 1, dtype=np.int32)
    anc_y[lab_ids] = ys[first_idx]
    anc_x[lab_ids] = xs[first_idx]
    anchor_i = np.zeros(binary.shape, dtype=np.int64)
    anchor_i[ys[first_idx], xs[first_idx]] = 1
    d = 2 * radius_cells + 1
    yy, xx = np.mgrid[:d, :d] - radius_cells
    kernel = ((xx ** 2 + yy ** 2) <= radius_cells ** 2).astype(np.int64)
    area_km2 = float(np.pi * radius_cells ** 2)   # 1 像元 = 1 km2
    # 窗口内锚点数/面积和（结果必为非负整数，取整消除 FFT 噪声）
    cnt = np.rint(ndi.convolve(anchor_i, kernel, mode="constant", cval=0)).astype(np.int64)
    asum = np.rint(ndi.convolve(anchor_i * patch_area, kernel,
                                mode="constant", cval=0)).astype(np.int64)
    # 自属补丁：像元在本斑块内但自属锚点在窗外 -> 补计本斑块
    inside = labels > 0
    if inside.any():
        h, w = binary.shape
        yidx = np.arange(h, dtype=np.int32)[:, None]
        xidx = np.arange(w, dtype=np.int32)[None, :]
        dy = yidx - anc_y[labels]
        dx = xidx - anc_x[labels]
        own_out = inside & ((dy * dy + dx * dx) > radius_cells ** 2)
        cnt = cnt + own_out.astype(np.int64)
        asum = asum + own_out * patch_area
    density = np.full(binary.shape, np.nan, dtype=np.float32)
    msize = np.full(binary.shape, np.nan, dtype=np.float32)
    m = cnt >= 1
    density[m] = (cnt[m] / area_km2 * 100.0).astype(np.float32)   # 个/100km2
    msize[m] = (asum[m] / cnt[m]).astype(np.float32)              # km2
    return density, msize


def derive_snapshot(snap):
    cfg = common.load_config()
    year, ssp, _, src_file = snap
    src = os.path.join(cfg["paths"]["lulc_raw"], src_file)
    radii = cfg["focal"]["radii_km"]
    legend = {int(k): v for k, v in cfg["lulc_legend"].items()}
    nod = cfg["nodata"]["float"]
    written = []

    # 1) 分类层 warp 到模板（nearest, 0=背景 -> 255）
    cls_tmp = os.path.join(cfg["paths"]["scratch"], "glu1km-cls-%s%s.tif" % (
        ssp or "hist", year))
    common.warp_to_template(src, cls_tmp, cfg,
                            resampling=cfg["resampling"]["categorical"],
                            dtype="uint8", src_nodata=0)
    with rasterio.open(cls_tmp) as ds:
        cls = ds.read(1)
    # 国界掩膜：先于一切派生计算，境外背景不参与比例归一/Shannon/边缘判定
    cls = np.where(common.china_mask(cfg), cls, 255).astype(np.uint8)
    valid = (cls >= 1) & (cls <= 6)
    cls = np.where(valid, cls, 255).astype(np.uint8)

    def write(parts, suffix, arr):
        dst = common.layer_path(cfg, parts, suffix)
        # focal 窗口会把边界有效值扩散到境外 nodata 区，统一出口再掩膜限回中国区内
        arr = common.apply_china_mask(arr, cfg, np.nan)
        out = np.where(np.isnan(arr), nod, arr).astype(np.float32)
        common.atomic_write_raster(dst, out, cfg, dtype="float32", nodata=nod)
        written.append(dst)

    # 2) 六类比例：原生 one-hot + 4 focal
    focal_props = {}
    for code, cname in legend.items():
        onehot = (cls == code).astype(np.float32)
        onehot[~valid] = np.nan
        write(snapshot_parts(cfg, snap, [cname]), "_prop", onehot)
        for r in radii:
            rc = int(round(r * 1000.0 / cfg["grid"]["resolution"]))
            fp = common.focal_mean(onehot, rc, invalid=~valid)
            write(snapshot_parts(cfg, snap, [cname]), "_prop_f%d" % (r * 1000), fp)
            focal_props.setdefault(r, {})[code] = fp

    # 3) 窗口 Shannon：由各类 focal 比例计算 -sum(p ln p)
    for r in radii:
        sh = np.zeros(cls.shape, dtype=np.float64)
        anyp = np.zeros(cls.shape, dtype=bool)
        for code in legend:
            p = focal_props[r][code]
            mask = ~np.isnan(p)
            anyp |= mask
            with np.errstate(divide="ignore", invalid="ignore"):
                term = np.where((p > 0) & mask, p * np.log(np.where(p > 0, p, 1.0)), 0.0)
            sh += term
        out = np.full(cls.shape, np.nan, dtype=np.float32)
        out[anyp] = (-sh[anyp]).astype(np.float32)
        write(snapshot_parts(cfg, snap, []), "_shannon_f%d" % (r * 1000), out)

    # 4) 边缘密度：原生 + 4 focal
    e = edge_indicator(cls, valid).astype(np.float32)
    e[~valid] = np.nan
    write(snapshot_parts(cfg, snap, []), "_edge", e)
    for r in radii:
        rc = int(round(r * 1000.0 / cfg["grid"]["resolution"]))
        fe = common.focal_mean(e, rc, invalid=~valid)
        write(snapshot_parts(cfg, snap, []), "_edge_f%d" % (r * 1000), fe)

    # 5) 斑块密度/平均斑块大小：all（全类别景观）+ forest（森林栖息地）x 4 半径
    #    patchdensity-all_f1000 为常量层（见文件头），跳过不产出
    for scope, binary in (("all", valid), ("forest", cls == 2)):
        for r in radii:
            rc = int(round(r * 1000.0 / cfg["grid"]["resolution"]))
            pd, mps = patch_metric(binary, rc)
            if not (scope == "all" and r == radii[0]):
                write(snapshot_parts(cfg, snap, []), "_patchdensity-%s_f%d" % (scope, r * 1000), pd)
            write(snapshot_parts(cfg, snap, []), "_patchsize-%s_f%d" % (scope, r * 1000), mps)

    os.remove(cls_tmp)
    return dict(snap="%s/%s" % (ssp or "history", year), n=len(written), files=written)


def worker(snap):
    try:
        return derive_snapshot(snap)
    except Exception as ex:
        return dict(snap=str(snap), error="%s\n%s" % (ex, traceback.format_exc()))


def main():
    cfg = common.load_config()
    print("snapshots:", len(SNAPSHOTS), "-> expected layers:", len(SNAPSHOTS) * 54)
    results = []
    # 斑块卷积内存占用大（每快照 ~1.5GB），限制并发防 OOM
    with mp.Pool(min(len(SNAPSHOTS), int(cfg["runtime"]["workers"]), 4)) as pool:
        for r in pool.imap_unordered(worker, SNAPSHOTS):
            if "error" in r:
                print("ERROR snapshot", r["snap"], ":", r["error"].splitlines()[0])
            else:
                print("done snapshot %s : %d layers" % (r["snap"], r["n"]))
            results.append(r)

    errs = [r for r in results if "error" in r]
    ok = [r for r in results if "error" not in r]
    total = sum(r["n"] for r in ok)
    print("=" * 60)
    print("snapshots ok=%d error=%d, layers=%d" % (len(ok), len(errs), total))

    # 值域报告
    rpt = os.path.join(cfg["paths"]["logs"], "p4_lulc_value_report.csv")
    with open(rpt, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["relpath", "n_valid", "vmin", "vmax"])
        for r in ok:
            for dst in r["files"]:
                with rasterio.open(dst) as ds:
                    a = ds.read(1)
                    nod = ds.nodata
                v = a[~np.isnan(a)] if a.dtype.kind == "f" else a.ravel()
                if nod is not None:
                    v = v[v != nod]
                w.writerow([common.relpath(cfg, dst), v.size,
                            float(v.min()) if v.size else "",
                            float(v.max()) if v.size else ""])
    print("value report:", rpt)

    common.lineage(cfg, [
        dict(relpath=common.relpath(cfg, dst),
             source=os.path.join(cfg["paths"]["lulc_raw"],
                                 next(s[3] for s in SNAPSHOTS
                                      if ("%s/%s" % (s[1] or "history", s[0])) == r["snap"])),
             script=SCRIPT, note="snapshot=%s" % r["snap"])
        for r in ok for dst in r["files"][:1]
    ])

    errs_naming = common.validate_naming(cfg)
    print("naming validator errors:", len(errs_naming))
    for e in errs_naming[:10]:
        print("  ", e)

    assert not errs and not errs_naming and total == len(SNAPSHOTS) * 54
    print("04 DONE")


if __name__ == "__main__":
    main()
