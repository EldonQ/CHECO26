"""P3 地形派生 + 土壤剖面均值：
aspect（Horn 法，度 0-360，平地=NA）、TRI（Riley et al. 1999 3x3 邻域高差 RMS）、
CSDLv2 28 属性剖面厚度加权均值（层界 0/5/15/30/60/100cm，厚度 5/10/15/30/40）。幂等。"""
import multiprocessing as mp
import os
import sys
import traceback

import numpy as np
import rasterio

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

SCRIPT = "06_derive_topo_vege.py"

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
PROFILE_DEPTHS = ["0", "5", "15", "30", "60"]      # 0-100cm 五个层段顶界
PROFILE_WEIGHTS = [5.0, 10.0, 15.0, 30.0, 40.0]   # 对应层厚 cm


def horn_aspect(elev, res, valid):
    """Horn (1981) 坡向，度 0-360（北=0 顺时针）；无效/平地=NA。"""
    z = np.where(valid, elev, np.nan)
    zp = np.pad(z, 1, mode="edge")
    a, b, c = zp[:-2, :-2], zp[:-2, 1:-1], zp[:-2, 2:]
    d, f = zp[1:-1, :-2], zp[1:-1, 2:]
    g, h, i = zp[2:, :-2], zp[2:, 1:-1], zp[2:, 2:]
    dzdx = ((c + 2 * f + i) - (a + 2 * d + g)) / (8 * res)
    dzdy = ((g + 2 * h + i) - (a + 2 * b + c)) / (8 * res)
    asp = np.degrees(np.arctan2(dzdy, -dzdx))
    out = np.where(asp < 0, 90.0 - asp, 450.0 - asp) % 360.0
    flat = (dzdx == 0) & (dzdy == 0)
    out[flat | ~valid] = np.nan
    return out.astype(np.float32)


def riley_tri(elev, valid):
    """Riley et al. 1999：中心像元与 8 邻域高差平方和的均值的平方根。"""
    z = np.where(valid, elev, np.nan)
    zp = np.pad(z, 1, mode="edge")
    acc = np.zeros(elev.shape, dtype=np.float64)
    for r in (0, 1, 2):
        for c in (0, 1, 2):
            if r == 1 and c == 1:
                continue
            diff = zp[r:r + elev.shape[0], c:c + elev.shape[1]] - z
            acc += np.nan_to_num(diff, nan=0.0) ** 2
    out = np.sqrt(acc / 8.0).astype(np.float32)
    out[~valid] = np.nan
    return out


def do_topo(cfg):
    # 注意：必须基于 02 掩膜后的 elev 层计算（境外高程不参与坡向/TRI 邻域）
    elev_path = common.layer_path(cfg, ["glo", "topo", "chinadem", "elev"])
    with rasterio.open(elev_path) as ds:
        elev = ds.read(1).astype(np.float64)
    valid = ~np.isnan(elev)
    res = float(cfg["grid"]["resolution"])
    nod = cfg["nodata"]["float"]
    outs = []
    asp = horn_aspect(elev, res, valid)
    dst = common.layer_path(cfg, ["glo", "topo", "chinadem", "aspect"])
    common.atomic_write_raster(dst, np.where(np.isnan(asp), nod, asp), cfg,
                               dtype="float32", nodata=nod)
    outs.append((dst, elev_path, "Horn aspect deg"))
    tri = riley_tri(elev, valid)
    dst = common.layer_path(cfg, ["glo", "topo", "chinadem", "tri"])
    common.atomic_write_raster(dst, np.where(np.isnan(tri), nod, tri), cfg,
                               dtype="float32", nodata=nod)
    outs.append((dst, elev_path, "Riley TRI"))
    return outs


def soil_profile_worker(adir):
    cfg = common.load_config()
    nod = cfg["nodata"]["float"]
    try:
        dst = common.layer_path(cfg, ["glo", "soil", "csdlv2", adir], "_profile")
        if os.path.exists(dst) and not common.force_rerun() \
                and common.check_alignment(dst, cfg):
            return dict(status="skip", dst=dst, adir=adir)
        num = None
        den = None
        for dep, wt in zip(PROFILE_DEPTHS, PROFILE_WEIGHTS):
            p = common.layer_path(cfg, ["glo", "soil", "csdlv2", adir, dep])
            with rasterio.open(p) as ds:
                a = ds.read(1).astype(np.float64)
            m = ~np.isnan(a)
            if num is None:
                num = np.zeros(a.shape, dtype=np.float64)
                den = np.zeros(a.shape, dtype=np.float64)
            num += np.where(m, a * wt, 0.0)
            den += np.where(m, wt, 0.0)
        out = np.full(num.shape, np.nan, dtype=np.float32)
        ok = den > 0
        out[ok] = (num[ok] / den[ok]).astype(np.float32)
        common.atomic_write_raster(dst, np.where(np.isnan(out), nod, out), cfg,
                                   dtype="float32", nodata=nod)
        assert common.check_alignment(dst, cfg)
        return dict(status="ok", dst=dst, adir=adir)
    except Exception as e:
        return dict(status="error", dst=dst, adir=adir,
                    note="%s\n%s" % (e, traceback.format_exc()))


def main():
    cfg = common.load_config()
    # ---- topo ----
    topo_outs = do_topo(cfg)
    for dst, src, note in topo_outs:
        print("OK", common.relpath(cfg, dst), "|", note)
    # ---- soil profile ----
    results = []
    adirs = sorted(set(SOIL_ATTR_DIR.values()))
    with mp.Pool(int(cfg["runtime"]["workers"])) as pool:
        for r in pool.imap_unordered(soil_profile_worker, adirs):
            print(r["status"].upper(), common.relpath(cfg, r["dst"]))
            if r["status"] == "error":
                print("   ERROR:", r["note"].splitlines()[0])
            results.append(r)

    err = [r for r in results if r["status"] == "error"]
    common.lineage(cfg,
                   [dict(relpath=common.relpath(cfg, dst), source=src,
                         script=SCRIPT, note=note) for dst, src, note in topo_outs] +
                   [dict(relpath=common.relpath(cfg, r["dst"]),
                         source="soil/csdlv2/%s/{0,5,15,30,60}" % r["adir"],
                         script=SCRIPT,
                         note="thickness-weighted 0-100cm w=5/10/15/30/40")
                    for r in results if r["status"] == "ok"])
    errs = common.validate_naming(cfg)
    print("naming validator errors:", len(errs))
    for e in errs[:10]:
        print("  ", e)
    assert not err and not errs
    print("06 DONE")


if __name__ == "__main__":
    main()
