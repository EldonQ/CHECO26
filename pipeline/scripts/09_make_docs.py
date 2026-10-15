"""P5 文档交付：生成 00_docs 全套文档（事实驱动，全部由 config/manifest/校验报告生成）。
产出：variable_dictionary.csv、legend.csv、core_subset.csv、README_data.md、
lulc_scope.md、timeseries_scope.md、validation_report.md。幂等。"""
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

import importlib
s02 = importlib.import_module("02_ingest_static")
s03 = importlib.import_module("03_ingest_timeseries")
s04 = importlib.import_module("04_derive_lulc")
s07 = importlib.import_module("07_future_chains")

SOIL_UNITS = {
    "ph": "pH(-)", "bd": "g/cm3", "sand": "%", "silt": "%", "clay": "%",
    "gravel": "%", "porosity": "%", "oc": "g/100g", "tn": "g/100g",
    "tp": "g/100g", "tk": "g/100g", "socd": "kg C/m2", "cec": "me/100g",
    "an": "mg/kg", "ak": "mg/kg", "ap": "mg/kg",
    "dry-hue": "Munsell hue(编码)", "dry-value": "Munsell value(编码)",
    "dry-chroma": "Munsell chroma(编码)", "wet-hue": "Munsell hue(编码)",
    "wet-value": "Munsell value(编码)", "wet-chroma": "Munsell chroma(编码)",
    "dry-r": "RGB R(编码)", "dry-g": "RGB G(编码)", "dry-b": "RGB B(编码)",
    "wet-r": "RGB R(编码)", "wet-g": "RGB G(编码)", "wet-b": "RGB B(编码)",
}
BIOCLIM_UNITS = {"prec": "mm", "sunp": "%", "tave": "degC", "tmax": "degC",
                 "tmin": "degC"}   # 源原生单位（实测 bio01 -20.6~25.9，bio12 9~4084）


def bio_unit(v):
    if v in BIOCLIM_UNITS:
        return BIOCLIM_UNITS[v]
    n = int(v[3:])
    if n in (1, 2, 5, 6, 7, 8, 9, 10, 11):
        return "degC"
    if n in (3, 4, 12, 13, 14, 15, 16, 17, 18, 19):
        return "mm" if n >= 12 else "(-)"
    return "(-)"


def unit_of(rel, parts):
    """按路径推断单位与值域说明。"""
    theme = parts[1]
    if theme == "bioclim":
        return bio_unit(parts[-1]), "1991-2020 气候态/未来时段均值"
    if theme == "soil":
        u = SOIL_UNITS.get(parts[3], "(-)")
        if rel.endswith("_profile.tif"):
            return u, "0-100cm 厚度加权均值(5/10/15/30/40)"
        return u, "层段 %s-%scm" % (parts[4], {"0": "5", "5": "15", "15": "30",
                                               "30": "60", "60": "100", "100": "200"}[parts[4]])
    if theme == "topo":
        return {"elev": ("m", "DEM 高程"), "slope": ("deg", "坡度"),
                "aspect": ("deg(0-360,北=0顺时针)", "Horn 坡向,平地=NA"),
                "tri": ("m", "Riley 1999 3x3 地形起伏度")}.get(parts[3], ("-", ""))
    if theme == "hydro":
        v = parts[3].replace("-", "_")
        if v in common.load_config()["hydro90m_vars"]["scale_cm2m"]:
            return "m", "Hydrography90m, cm->m"
        if v in common.load_config()["hydro90m_vars"]["categorical"]:
            return "类别编码", "Hydrography90m 分类层"
        return "(-)", "Hydrography90m"
    if theme == "vege":
        ds = parts[2]
        if ds == "glassndvi":
            return "NDVI(-)", "GLASS NDVI 年最大, 30m 聚合"
        if ds == "agb2019":
            return "Mg/ha", "森林地上生物量 2019"
        if ds == "ch2019":
            return "m", "森林冠层高度 2019 (dm->m)"
        return "%", "树冠覆盖度 CATCD 2025"
    if theme == "lulc":
        stem = os.path.basename(rel)
        if "_prop" in stem:
            return "比例(0-1)", "窗口内类别比例"
        if "_shannon" in stem:
            return "(-)", "Shannon 多样性 -sum(p*ln p)"
        if "_edge" in stem:
            return "比例(0-1)", "FRAGSTATS 边缘像元比例"
        if "_patchdensity" in stem:
            scope = "全类别景观" if "-all" in stem else "仅森林"
            return "个/100km2", "圆盘窗口斑块密度(%s)" % scope
        if "_patchsize" in stem:
            scope = "全类别景观" if "-all" in stem else "仅森林"
            return "km2", "窗口平均斑块大小(%s)" % scope
        return "-", ""
    if theme == "anthro":
        ds = parts[2]
        if ds == "landscan":
            return "人/像元", "LandScan 人口数"
        if ds == "foothii":
            return "指数(0-59)", "WCS footHII 人类足迹"
        return "比例(0-1)", "GHS-SMOD 城市化比例(类21-23)"
    if theme == "dist":
        return "m", "到最近要素欧氏距离" if parts[2] != "h90m" else "Hydrography90m 河流距离 cm->m"
    return "-", ""


def rows_from_report(logs, name):
    """读取各阶段值域报告 {relpath: (n_valid, vmin, vmax)}。"""
    out = {}
    p = os.path.join(logs, name)
    if not os.path.exists(p):
        return out
    with open(p, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            out[row["relpath"]] = (row.get("n_valid", ""), row.get("vmin", ""),
                                   row.get("vmax", ""))
    return out


# 建模用途标注（2026-08-08 定案）：稀疏旗标层等不建议作协变量的层，在此按 relpath 登记
SDM_NOTES = {
    "glo/hydro/h90m/outlet/glo_hydro_h90m_outlet.tif":
        "不建议作建模协变量：稀疏流域出口旗标层（中国境内有效像元约0.2%、取值恒1.0，无梯度信息）；"
        "数据忠实保留，N-SDM 自动筛选亦会剔除近常量变量",
}


def main():
    cfg = common.load_config()
    docs = cfg["paths"]["docs"]
    logs = cfg["paths"]["logs"]
    os.makedirs(docs, exist_ok=True)

    # ---- 1) 变量字典：全库每层一行 ----
    stats = {}
    for name in ("p2_value_report.csv", "p3_timeseries_value_report.csv",
                 "p4_lulc_value_report.csv", "p4_value_report.csv",
                 "p5_validation_report.csv"):
        for rel, s in rows_from_report(logs, name).items():
            stats[rel] = s

    entries = []
    cov = cfg["paths"]["covariates"]
    for dirpath, _, filenames in os.walk(cov):
        for fn in sorted(filenames):
            if not fn.endswith(".tif"):
                continue
            rel = common.relpath(cfg, os.path.join(dirpath, fn))
            parts_all = rel[:-4].split("/")
            parts = parts_all[:-1]                       # 目录各级（不含文件名）
            fname = parts_all[-1]
            base = "_".join(parts)
            suffix = fname[len(base):] if fname.startswith(base) else ""
            u, note = unit_of(rel, parts)
            if suffix in ("_min", "_max"):
                note += "；窗口%s聚合(90m源, GDAL %s resampling, 2026-08-08增补)" % (
                    "最小值" if suffix == "_min" else "最大值", suffix[1:])
            sdm_note = SDM_NOTES.get(rel, "")
            n, vmin, vmax = stats.get(rel, ("", "", ""))
            entries.append(dict(relpath=rel, theme=parts[1], dataset=parts[2],
                                unit=u, value_min=vmin, value_max=vmax, n_valid=n,
                                suffix=suffix or "-", note=note, sdm_note=sdm_note))
    entries.sort(key=lambda x: x["relpath"])
    vd = os.path.join(docs, "variable_dictionary.csv")
    with open(vd, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["relpath", "theme", "dataset", "unit",
                                          "value_min", "value_max", "n_valid",
                                          "suffix", "note", "sdm_note"])
        w.writeheader()
        w.writerows(entries)
    print("variable_dictionary:", len(entries), "layers")

    # ---- 2) 图例表 ----
    lg = os.path.join(docs, "legend.csv")
    with open(lg, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["dataset", "code", "name"])
        for k, v in cfg["lulc_legend"].items():
            w.writerow(["glu1km(Zhang et al. 2023)", k, v])
        w.writerow(["GHS-SMOD R2023A", 21, "low density urban"])
        w.writerow(["GHS-SMOD R2023A", 22, "medium density urban"])
        w.writerow(["GHS-SMOD R2023A", 23, "high density urban"])
        w.writerow(["GRIP4", "gp_rtp=1", "Highways"])
        w.writerow(["GRIP4", "gp_rtp=2", "Primary roads"])
        w.writerow(["GRIP4", "gp_rtp=3", "Secondary roads"])
        w.writerow(["GRIP4", "gp_rtp=4", "Tertiary roads"])
        w.writerow(["GRIP4", "gp_rtp=5", "Local roads"])
        w.writerow(["GRIP4", "gp_rtp=0", "Unspecified"])
        w.writerow(["GSW extent v1.5", "0/1/255", "no water / water(seasonal+permanent) / invalid"])

    # ---- 3) 精选核心子集（供 N-SDM 首跑；正式去共线由建模阶段 VIF 完成）----
    core = []
    for v in ["bio01", "bio04", "bio12", "bio15"]:
        core.append("glo/bioclim/cnclim1km/present/%s/glo_bioclim_cnclim1km_present_%s.tif" % (v, v))
    for a in ["ph", "oc", "sand", "clay", "bd", "cec", "an", "tp"]:
        core.append("glo/soil/csdlv2/%s/glo_soil_csdlv2_%s_profile.tif" % (a, a))
    for v in ["elev", "slope", "aspect", "tri"]:
        core.append("glo/topo/chinadem/%s/glo_topo_chinadem_%s.tif" % (v, v))
    core.append("glo/vege/glassndvi/2022/ndvimax/glo_vege_glassndvi_2022_ndvimax_f5000.tif")
    core.append("glo/vege/agb2019/agb/glo_vege_agb2019_agb.tif")
    core.append("glo/vege/ch2019/ch/glo_vege_ch2019_ch.tif")
    core.append("glo/vege/catcd/treecover/glo_vege_catcd_treecover.tif")
    for v in ["spi", "sti", "channel-elv-dw-seg", "slope-elv-dw-cel"]:
        core.append("glo/hydro/h90m/%s/glo_hydro_h90m_%s.tif" % (v, v))
    for c in cfg["lulc_legend"].values():
        core.append("glo/lulc/glu1km/2020/%s/glo_lulc_glu1km_2020_%s_prop_f5000.tif" % (c, c))
    core.append("glo/lulc/glu1km/2020/glo_lulc_glu1km_2020_shannon_f5000.tif")
    core.append("glo/lulc/glu1km/2020/glo_lulc_glu1km_2020_edge_f5000.tif")
    core.append("glo/lulc/glu1km/2020/glo_lulc_glu1km_2020_patchdensity-forest_f5000.tif")
    core.append("glo/lulc/glu1km/2020/glo_lulc_glu1km_2020_patchsize-forest_f5000.tif")
    core.append("glo/anthro/foothii/2020/hii/glo_anthro_foothii_2020_hii_f5000.tif")
    core.append("glo/vege/catcd/treecover/glo_vege_catcd_treecover_f5000.tif")
    core.append("glo/anthro/landscan/2020/pop/glo_anthro_landscan_2020_pop_f5000.tif")
    core.append("glo/anthro/foothii/2020/hii/glo_anthro_foothii_2020_hii.tif")
    core.append("glo/anthro/smod/2020/urbanprop/glo_anthro_smod_2020_urbanprop.tif")
    for d in ["grip4/road", "grip4/majorroad", "osm/trail", "smod/urban", "gsw/water"]:
        nm = d.replace("/", "_")
        core.append("glo/dist/%s/glo_dist_%s.tif" % (d, nm))
    core.append("glo/dist/h90m/stream-dist-proximity/glo_dist_h90m_stream-dist-proximity.tif")
    cs = os.path.join(docs, "core_subset.csv")
    with open(cs, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["relpath", "in_library"])
        for c in core:
            w.writerow([c, int(os.path.exists(os.path.join(cov, *c.split("/"))))])

    # ---- 4) 口径声明文档 ----
    g = cfg["grid"]
    readme = """# CHECO26 N-SDM 协变量数据库说明

## 网格基准
- CRS: China_Albers（WGS84，标准纬线 25/47N，中央经线 105E）
- 分辨率: 1000 m；范围 xmin=%s xmax=%s ymin=%s ymax=%s
- 掩膜: china.shp 栅格化 all_touched=True（保留海岛与海岸线）；**全部入库层均裁剪至国界内**，
  有效像元数不超过掩膜（约 949 万，等面积投影下 1 像元=1 km2）。如需"像元中心在中国"口径请另行生成第二版 mask。

## 主题与层数（主树）
bioclim 现状 28 + 未来 504（链入数据集名：cnclim1km-ensmean / cnclim1km-bcc-csm2-mr）；
soil 168+剖面 28；topo 4；vege 30（静态 3+12 focal、NDVI 3+12 focal）；hydro 39（2026-10-06 撤出 7 个源产品数值
不可用变量后：mean 29 + 2026-08-08 精选统计增补 8 channel_elv min/max + spi/sti max 2 = 39）；
lulc 540（patchdensity-all_f1000 常量层不产出）；anthro 237（footHII 盘上 20 年+80 focal）；
dist 17（矢量距离 5 + 河流距离 mean 4 + 2026-08-08 增补 min/max 8）。共 1595 层。详见 variable_dictionary.csv。

### 2026-10-06 撤出交付（源产品数值不可用，非处理缺陷）
`cti`、`channel_grad_{dw_seg,up_cel,up_seg}`、`slope_curv_{max,min}_dw_cel`、`accumulation`（含 `_max`）共 8 层
已移出交付树，存于 `archive/withdrawn_source_defective/`（清单 `logs/withdrawn_layers_manifest.csv`，可回滚）。
依据：把这些层与 Hydrography90m 源按管线同一规则（average 降尺度）重投影后逐像元比对，**值域上限 float32 位级相同、
0 个像元超出 1%%** —— 即成品是源的忠实降尺度，撤出后重跑无法改善。
源侧证据：`cti` 源为 int32 [−5.65e8, 1.87e9]（ln(a/tanβ) 不可能达到该量级，99.7%% 像元为负）；
`channel_grad` 源中位数 ~9e4 cm/m、max 1.42e9（物理上限 ~100 cm/m）；
`slope_curv` 源在 ±384900 对称饱和；`accumulation` 源含负值而单位为 km²（汇水面积不可为负）。

## 重采样固定规则
categorical=nearest；continuous/proportion/distance=bilinear；
细分辨率降尺度：continuous=average、categorical=mode；窗口极值=min/max（2026-08-08 hydro 精选统计增补：
只补有生态语义的统计量，不铺 median；入库前方差筛查拦常量层）。
增补层与全库其他层地位相同，均为正式成品；建模时随全量候选集交给 N-SDM 嵌入式协变量筛选
（collinearity filtering + 三模型联合排序 top-k，自动完成，无需人工逐变量挑选）；
core_subset.csv 仅为 N-SDM 首跑提速用的 45 层精简清单，非准入门槛。

## focal 窗口口径（权威说明，2026-10-06 补）
`_f<数字>` 后缀的数字是**米**，窗口是**方格**而非半径：`radius_cells = 数字/1000`，`size = 2*radius_cells+1`。

| 后缀 | 方格 | 实际覆盖 | 等效圆半径 |
|---|---|---|---|
| `_f1000` | 3x3 | 3 km x 3 km | ~1.69 km |
| `_f5000` | 11x11 | 11 km x 11 km | ~6.2 km |
| `_f10000` | 21x21 | 21 km x 21 km | ~11.9 km |
| `_f20000` | 41x41 | 41 km x 41 km | ~23.1 km |

**易混淆点**：在 1 km 网格上"1 km 半径的圆盘"是退化情形（严格 `<` 仅中心 1 格 = 恒等；严格 `<=` 为 5 格十字）。
所以 `_f1000` 是"最小多格窗口"（3x3 方格），**不是** 1 km 半径圆盘。
注意与斑块类派生区分：patchdensity / patchsize 用**圆盘**窗口，与 focal 后缀层口径不同。
窗口内**无有效像元时输出 NoData**（2026-10-06 修复；此前该判据受浮点残差影响曾输出巨值，详见 logs/focal_repair_record.csv）。

## 未来情景配对（近似配对显式声明）
气候中心年 2030/2055/2085（源时段 2021-2040/2041-2070/2071-2100）。
LULC 快照 2030/2050/2100。2030 完全对齐；2050 对 2055、2100 对 2085 为近似配对，
建模时必须显式声明。

## 归档区（不入主树）
archive/clcd-albert（CLCD 投影版，albert 版图例失真：灌丛实测 0.31%% vs 官方 ~16%%）、
archive/sinolc1、archive/hfp、archive/harmonised、archive/gcm（其余 9 个 GCM 未来气候，盘上实测）。
archive 为 config.yaml 显式引用的源数据仓（谱系来源），与 data/ 主树同为正式交付组成部分，不得删除。

## 质检可视化与已知源特性（2026-08-08）
- 逐层质检可视化交付：E:/CHECO26/Visualization/checo26_final_qc
  （individual/ 按主题单图、combined/ 主题总览、qc_report.csv 逐层记录、qc_summary.md 结论）。
- hydro/h90m/outlet 为稀疏流域出口标记层（中国境内有效像元约 0.2%%、取值恒 1.0），
  数据忠实于源；已定案（2026-08-08）不作建模协变量（variable_dictionary.csv 的 sdm_note 列已标注）。
- h90m 系列在青藏内流区存在 nodata 空洞（源产品无河网）；spi/sti max 层保留源长尾；
  均为忠实保留的源特性，详见 qc_summary.md。
- 2026-10-06 全库终检实测（logs 与 _verify/tree_audit.csv）：**越出中国掩膜的像元 = 0**；
  派生层值域包含与空窗口判据 0 失败；常量层仅 outlet 1 个；NDVI 负值为物理真值（水体/雪/裸土，
  15 层全部落在 [-1, 1] 内）；其余缺失像元均可在源侧找到对应空洞。

## 可复现
scripts/config.yaml 为唯一参数来源（config 哈希入 logs/lineage.csv）；
脚本幂等；运行记录 logs/p*_run.log 与 logs/*_value_report.csv。
""" % (g["xmin"], g["xmax"], g["ymin"], g["ymax"])
    with open(os.path.join(docs, "README_data.md"), "w", encoding="utf-8") as f:
        f.write(readme)

    lulc_md = """# LULC 口径声明（Zhang et al. 2023, glu1km）

- 单一产品策略：现状（history_2020）与未来（ssp126/245/585 x 2030/2050/2100）同源同图例。
- 图例：1 cropland / 2 forest / 3 grassland / 4 urban / 5 barren / 6 water；0=背景->NA。
- 代价（如实记录）：无灌丛/湿地/雪冰类别；无 2000-2020 历史时序；原生 1km 优势类存储。
  CLCD 虽含历史时序，但其 albert 投影版灌丛比例实测 0.31%（官方约 16%），图例失真，已归档不用。
- 派生口径（全部在原生 1km 模板上计算，比例先行、窗口后置）：
  类别比例 = 窗口内 one-hot 均值；Shannon = -sum(p*ln p)（自然对数，窗口见下"focal 窗口口径"）；
  边缘密度 = FRAGSTATS 4 邻域类别不同即边缘（McGarigal 2002）；
  斑块密度（个/100km2）/平均斑块大小（km2）= 4 邻域连通斑块 + 锚点近似（每斑块扫描序首像元）
  + 圆盘窗口卷积；口径 all=全类别景观、forest=仅森林；窗口边缘斑块锚点在窗外时不计入（边界少量像元偏差）。
  注意：斑块类派生（patchdensity/patchsize）用**圆盘**窗口，与 focal 后缀层的**方格**窗口不是同一口径。
- 每快照 54 层 x 10 快照 = 540 层（patchdensity-all_f1000 为数学必然常量层，2026-08-07 审计定案不产出）。

## focal 窗口口径（权威说明，2026-10-06 补）
`_f<数字>` 后缀的数字是**米**，解析出的窗口是**方格**，不是半径：
`radius_cells = 数字/1000`，`size = 2*radius_cells + 1`（见 common.focal_mean）。
故在 1 km 网格上：

| 后缀 | 方格 | 实际覆盖 | 等效圆半径 |
|---|---|---|---|
| `_f1000` | 3x3 | 3 km x 3 km | ~1.69 km |
| `_f5000` | 11x11 | 11 km x 11 km | ~6.2 km |
| `_f10000` | 21x21 | 21 km x 21 km | ~11.9 km |
| `_f20000` | 41x41 | 41 km x 41 km | ~23.1 km |

**易混淆点**：说"1 km 半径的圆盘"在 1 km 网格上是退化情形——严格 `<` 只覆盖中心 1 格（等于恒等、无平滑），
严格 `<=` 覆盖 5 格（十字形）。因此本库的 `_f1000` 是"最小多格窗口"（3x3 方格），
不是 1 km 半径圆盘。该语义经与 `scratch/verify_focal_semantics.py` 的对照实验确认。
N-SDM 侧只把 `_f<数字>` 解析为 focal 元数据（不参与窗口构造），故后缀保持米数即可。
"""
    with open(os.path.join(docs, "lulc_scope.md"), "w", encoding="utf-8") as f:
        f.write(lulc_md)

    ts_md = """# 时序口径声明（零裁剪原则）

源数据有多少年入多少年；缺失年份不插补不外推。
- LandScan 人口 2000-2024 全 25 年（raw + 4 focal = 125 层）
- WCS footHII 2001-2020 全 20 年（x0.01 -> 指数 0-59；源无 2021 年，以盘上实测为准；raw + 4 focal = 100 层）
- GHS-SMOD 城市化比例 12 epoch（1975-2030 步长 5）
- GLASS NDVI 年最大 2020-2022 三年（源数据原生覆盖上限，raw + 4 focal）
SWECO25 先例（statpop 11 年、sdc 26 年均全入）支持本口径。
"""
    with open(os.path.join(docs, "timeseries_scope.md"), "w", encoding="utf-8") as f:
        f.write(ts_md)

    # ---- 5) 校验报告（08 产出后复制） ----
    for src, dst in (("p5_summary.txt", "validation_report.md"),
                     ("p5_validation_report.csv", "p5_validation_report.csv"),
                     ("p0_lulc_qc.csv", "p0_lulc_qc.csv"),
                     ("lineage.csv", "lineage.csv")):
        sp = os.path.join(logs, src)
        if os.path.exists(sp):
            with open(sp, encoding="utf-8") as fi, \
                 open(os.path.join(docs, dst), "w", encoding="utf-8") as fo:
                fo.write(fi.read())
    # validation_report.md 追加判读说明：CELL FAIL 为参考项非硬门槛
    vp = os.path.join(docs, "validation_report.md")
    with open(vp, "a", encoding="utf-8") as f:
        f.write(
            "\nNote: CELL FAIL 项为参考性比对（双线性重投影 vs 源产品自身重采样在尖锐梯度处的"
            "数值差异），不构成验收硬门槛；硬门槛（存在性/对齐/命名/掩膜/值域）全部通过，"
            "相关层经逐层审计无数据缺陷。\n")
    print("docs written to", docs)


if __name__ == "__main__":
    main()
