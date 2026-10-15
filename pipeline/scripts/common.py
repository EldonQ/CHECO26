"""CHECO26 N-SDM 汇编公共工具库。
所有参数一律读取 config.yaml，代码零魔法数；原子写入；谱系留痕。"""
import csv
import datetime as dt
import hashlib
import os
import re

import numpy as np
import rasterio
import yaml
from rasterio.enums import Resampling
from rasterio.transform import from_origin
from rasterio.warp import reproject
from scipy.ndimage import convolve, uniform_filter

CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.yaml")

_RESAMP = {
    "nearest": Resampling.nearest,
    "bilinear": Resampling.bilinear,
    "average": Resampling.average,
    "mode": Resampling.mode,
    "min": Resampling.min,   # 细分辨率降尺度：窗口最小值（水体可达性/极值语义）
    "max": Resampling.max,   # 细分辨率降尺度：窗口最大值（干流/最陡/最湿语义）
}

# 文件名允许后缀：属性词（prop/shannon/edge/profile/patchdensity/patchsize）+ focal 半径 + 统计量
# focal 后缀用米数（N-SDM 2.0.1 covinfo 解析器正则 .*_f([0-9]+)\.tif$ 只认纯数字米数）
FOCAL_SUFFIX_RE = re.compile(r"^(_prop|_shannon|_edge|_profile|_patchdensity-(all|forest)|_patchsize-(all|forest))?(_f\d+)*(_mean|_sd|_min|_max)?$")


def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def config_hash():
    with open(CONFIG_PATH, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()[:12]


def grid_spec(cfg):
    """模板网格规格：crs/transform/width/height/res。所有层必须与之一致。"""
    g = cfg["grid"]
    res = float(g["resolution"])
    width = int(round((g["xmax"] - g["xmin"]) / res))
    height = int(round((g["ymax"] - g["ymin"]) / res))
    transform = from_origin(g["xmin"], g["ymax"], res, res)
    return {
        "crs": g["crs_wkt"],
        "transform": transform,
        "width": width,
        "height": height,
        "res": res,
    }


_CHINA_MASK_CACHE = {}


def china_mask(cfg):
    """中国国界掩膜布尔数组（mask_china.tif==1，china.shp all_touched 栅格化）。
    所有入库层必须限定在此掩膜内；进程内缓存，避免重复读盘。"""
    key = cfg["paths"]["root"]
    if key not in _CHINA_MASK_CACHE:
        mask_path = os.path.join(cfg["paths"]["root"], "data", "mask_china.tif")
        with rasterio.open(mask_path) as ds:
            m = ds.read(1)
            assert check_alignment(mask_path, cfg), "mask_china.tif not aligned with template"
        _CHINA_MASK_CACHE[key] = (m == 1)
    return _CHINA_MASK_CACHE[key]


def apply_china_mask(arr, cfg, fill):
    """将国界外像元置为 fill（float 用 NaN、整型用 nodata）。返回修改后的数组。"""
    m = china_mask(cfg)
    arr[~m] = fill
    return arr


def force_rerun():
    """CHECO26_FORCE=1 时禁用幂等跳过，强制重生成（掩膜口径变更等修复场景）。"""
    return os.environ.get("CHECO26_FORCE", "") == "1"


def layer_path(cfg, parts, suffix=""):
    """DATAPREP 命名：目录=各级文件夹，文件名=各级名下划线拼接(+后缀)。
    parts 形如 ['glo','topo','chinadem','elev']；suffix 形如 '_f5000'。"""
    d = os.path.join(cfg["paths"]["covariates"], *parts)
    return os.path.join(d, "_".join(parts) + suffix + ".tif")


def atomic_write_raster(dst_path, arr, cfg, dtype="float32", nodata=None):
    """先写 .tmp 再 os.replace，中断不留半截文件。"""
    spec = grid_spec(cfg)
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    tmp = dst_path + ".tmp"
    profile = {
        "driver": "GTiff",
        "width": spec["width"],
        "height": spec["height"],
        "count": 1,
        "dtype": dtype,
        "crs": spec["crs"],
        "transform": spec["transform"],
        "nodata": nodata,
        "compress": "deflate",
        "tiled": True,
        "blockxsize": 256,
        "blockysize": 256,
        "BIGTIFF": "IF_SAFER",
    }
    with rasterio.open(tmp, "w", **profile) as dst:
        dst.write(arr.astype(dtype), 1)
    os.replace(tmp, dst_path)


def warp_to_template(src_path, dst_path, cfg, resampling, dtype="float32",
                     src_nodata=None, scale=None, offset=None, apply_mask=True):
    """将任意源栅格重投影/对齐到统一模板。resampling 取 config 规则键名。"""
    spec = grid_spec(cfg)
    nd = cfg["nodata"]["float"] if np.issubdtype(np.dtype(dtype), np.floating) \
        else cfg["nodata"]["uint8_categorical"]
    fill = np.nan if np.issubdtype(np.dtype(dtype), np.floating) else nd
    out_dtype = np.dtype(dtype)
    # 中间缓冲：整型升 float64（容纳 NaN/大值），浮点同精度
    buf_dtype = np.float64 if np.issubdtype(out_dtype, np.integer) else out_dtype
    dst = np.full((spec["height"], spec["width"]), fill, dtype=buf_dtype)
    with rasterio.Env(GDAL_NUM_THREADS=str(cfg["runtime"]["gdal_threads"])):
        with rasterio.open(src_path) as src_ds:
            # src_nodata=None -> 采用源文件自带 nodata（不同源 dtype/nodata 各异）
            eff_src_nodata = src_nodata if src_nodata is not None else src_ds.nodata
            reproject(
                source=rasterio.band(src_ds, 1),
                destination=dst,
                dst_crs=spec["crs"],
                dst_transform=spec["transform"],
                dst_nodata=fill,
                src_nodata=eff_src_nodata,
                resampling=_RESAMP[resampling],
            )
    out = dst.astype(dtype)
    if scale is not None or offset is not None:
        valid = ~(out == nd) if np.issubdtype(np.dtype(dtype), np.integer) else ~np.isnan(out.astype(float))
        sc = 1.0 if scale is None else float(scale)
        off = 0.0 if offset is None else float(offset)
        if np.issubdtype(np.dtype(dtype), np.floating):
            out[valid] = out[valid] * sc + off
    # 国界掩膜：入库层一律限定在中国区内（计划硬性要求；派生源如需境外上下文，调用方显式传 apply_mask=False）
    if apply_mask:
        apply_china_mask(out, cfg, fill)
    atomic_write_raster(dst_path, out, cfg, dtype=dtype, nodata=nd)
    return dst_path


def focal_count(valid, size):
    """窗口内有效像元的**精确整数**计数（float64 卷积，远小于 2^53 无舍入）。

    仅用于审计/复算等需要精确计数的场合。生产路径不需要它：`uniform_filter` 对
    布尔掩膜求均值得到 c = cnt/size^2，用 c 作分母即得等权均值（与精确计数等价），
    而 c 比卷积快 45 倍（radius 20：0.46 s vs 20.5 s）。
    """
    return convolve(valid.astype(np.float64), np.ones((size, size), dtype=np.float64),
                    mode="constant", cval=0.0)


def focal_mean(arr, radius_cells, invalid=None):
    """等权均值窗口（terra focal 的 scipy 等价实现），边缘 NA 自适应。
    radius_cells=1 -> 3x3 方格；5 -> 11x11；10 -> 21x21；20 -> 41x41。
    注意：窗口为正方形，半径以格计；_f1000 在 1km 网格上即 3x3 格（3km x 3km）。

    历史实现的缺陷：分母 c 是布尔掩膜的均值，全无效窗口上是系数的浮点舍入残差
    （~1e-17）而非精确 0，于是 `c > 0` 恒真，输出 = 分子/1e-17 的任意巨值
    （实测 −16608、4384、105 等）。

    正确判据是"窗口内至少 1 个有效像元"。用浮点掩膜计算时 c = cnt/size^2，而
    cnt=1 时 c = 1/size^2 可能舍入到略小于该值，故阈值取 0.5/size^2——恰好把
    cnt=1 判为有效（c ≈ 1/size^2 >> 0.5/size^2），把 cnt=0 判为空（c ≈ 1e-17 或 0）。
    实测四种窗口下该判据与精确整数计数**完全一致**（0 处差异）。
    含 ≥1 个有效像元的窗口，其输出与旧实现逐位一致（_f20000 全库 max|diff| = 0）。
    """
    if invalid is None:
        invalid = np.isnan(arr)
    valid = ~invalid
    a = np.where(valid, arr, 0.0).astype(np.float64)
    size = 2 * int(radius_cells) + 1
    s = uniform_filter(a, size=size, mode="constant", cval=0.0)
    c = uniform_filter(valid.astype(np.float32), size=size, mode="constant", cval=0.0)
    out = np.full(arr.shape, np.nan, dtype=np.float32)
    ok = c >= 0.5 / float(size * size)
    out[ok] = (s[ok] / c[ok]).astype(np.float32)
    return out


def focal_suffix(radius_km):
    # N-SDM 2.0.1 解析器只认纯数字米数后缀（_f5000 = 5 km）
    return "_f%d" % (int(radius_km) * 1000)


def check_alignment(path, cfg):
    """模板四查：CRS/分辨率/extent/网格偏移必须与模板完全一致。"""
    spec = grid_spec(cfg)
    with rasterio.open(path) as ds:
        ok_crs = rasterio.crs.CRS.from_user_input(ds.crs) == \
            rasterio.crs.CRS.from_user_input(spec["crs"])
        return bool(
            ok_crs
            and ds.width == spec["width"]
            and ds.height == spec["height"]
            and ds.res == (spec["res"], spec["res"])
            and ds.transform.almost_equals(spec["transform"], 1e-6)
        )


def lineage(cfg, rows):
    """rows: list of dict(relpath, source, script, note)。追加写入 logs/lineage.csv。"""
    log_dir = cfg["paths"]["logs"]
    os.makedirs(log_dir, exist_ok=True)
    path = os.path.join(log_dir, "lineage.csv")
    new = not os.path.exists(path)
    fields = ["timestamp", "relpath", "source", "script", "config_hash", "note"]
    with open(path, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        if new:
            w.writeheader()
        ch = config_hash()
        ts = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        for r in rows:
            w.writerow({
                "timestamp": ts,
                "relpath": r.get("relpath", ""),
                "source": r.get("source", ""),
                "script": r.get("script", ""),
                "config_hash": ch,
                "note": r.get("note", ""),
            })


def relpath(cfg, path):
    return os.path.relpath(path, cfg["paths"]["covariates"]).replace(os.sep, "/")


def validate_naming(cfg, verbose=False):
    """命名校验器：遍历 covariates 树，检查
    1) 文件夹名不含下划线；2) 文件名=各级文件夹名下划线拼接(+允许后缀)；
    3) 深度 4-7；4) 文件名全局唯一。返回错误列表。"""
    cov = cfg["paths"]["covariates"]
    errors, seen = [], set()
    for dirpath, dirnames, filenames in os.walk(cov):
        for d in dirnames:
            if "_" in d:
                errors.append("folder has underscore: %s" % os.path.join(dirpath, d))
        for fn in filenames:
            if not fn.endswith(".tif"):
                continue
            full = os.path.join(dirpath, fn)
            parts = os.path.relpath(dirpath, cov).split(os.sep)
            # 深度 4-7：情景子树连接词（scenario）不计入层级。
            # glo/lulc/glu1km/scenario/2050/ssp126/forest 与
            # glo/bioclim/cnclim1km-ensmean/scenario/2055/ssp245/bio01 均为合法 7 级语义结构
            depth = len([p for p in parts if p not in ("scenario",)]) + 1
            if not (4 <= depth <= 7):
                errors.append("depth %d out of 4-7: %s" % (depth, full))
            stem = fn[:-4]
            prefix = "_".join(parts)
            if not stem.startswith(prefix):
                errors.append("filename not prefix-joined: %s" % full)
            else:
                suffix = stem[len(prefix):]
                if not FOCAL_SUFFIX_RE.match(suffix):
                    errors.append("illegal suffix '%s': %s" % (suffix, full))
            if fn in seen:
                errors.append("duplicate filename: %s" % fn)
            seen.add(fn)
            if verbose:
                print(full)
    return errors
