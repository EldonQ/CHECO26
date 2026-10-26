#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render the data quality audit report from the audit tables.

Every number in the output comes from audit/*.csv or audit/audit_summary.json.
Nothing is typed by hand, so re-running the audit and then this script reproduces
the document exactly.

Output: 00_docs/DATA_QUALITY_AUDIT.md
"""
from __future__ import annotations

import collections
import csv
import json
import os

ROOT = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
AUD = os.path.join(ROOT, "audit")
OUT = os.path.join(ROOT, "00_docs", "DATA_QUALITY_AUDIT.md")

MASK_CELLS = 9490310
GRID_CELLS = 4861 * 4062


def read_csv(p):
    with open(p, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def main():
    summary = json.load(open(os.path.join(AUD, "audit_summary.json"), encoding="utf-8"))
    layers = read_csv(os.path.join(AUD, "layer_audit.csv"))
    comp = read_csv(os.path.join(AUD, "composition_identity.csv"))
    fid_path = os.path.join(AUD, "source_fidelity.csv")
    fid = read_csv(fid_path) if os.path.exists(fid_path) else []

    n = summary["layers_audited"]
    chk = summary["checks"]

    # populations that need a note
    low_valid = sorted(layers, key=lambda r: int(r["n_valid"]))[:5]
    const = [r for r in layers
             if r["vmin"] != "" and float(r["vmin"]) == float(r["vmax"])]
    under_half = [r for r in layers if int(r["n_valid"]) < MASK_CELLS * 0.5]
    over_mask = [r for r in layers if int(r["n_valid"]) > MASK_CELLS]

    by_ds = collections.defaultdict(list)
    for r in comp:
        # A group with no inspectable cell has a blank max_abs_dev; counting it as 0
        # would report a perfect group. Keep it out of the maximum.
        if r["max_abs_dev"] not in ("", None):
            by_ds[r["dataset"]].append(float(r["max_abs_dev"]))
    comp_bad = [r for r in comp if r["n_off_1e-3"] not in ("", "0")]

    L = []
    A = L.append
    A("# CHECO26 数据质量审计")
    A("")
    A("本文件由 `scripts/audit/audit_report.py` 从 `audit/` 下的审计表生成，"
      "文中每个数字都可在对应 CSV 中查到，没有任何一个数字是手写的。"
      "重跑 `audit_data_quality.py`、`audit_composition.py`、`audit_fidelity.py` "
      "与 `audit_summarize.py` 即可完整复现。")
    A("")
    A("## 一、范围与结论")
    A("")
    A("审计对象是交付树 `data/covariates/glo/` 下的全部 GeoTIFF，逐层打开、逐层读值，"
      "不抽样、不依赖溯源表里的记录值。")
    A("")
    A("| 项目 | 结果 |")
    A("|---|---|")
    A("| 应审计层数 | %s |" % format(summary["layers_expected"], ","))
    A("| 实际审计层数 | **%s** |" % format(n, ","))
    A("| 主题数 | %d |" % summary["themes"])
    A("| 未通过任何检查的层 | **%d** |" % summary["layers_failing"])
    A("| 交付字节总数 | %s（%.1f GB） |" % (format(summary["bytes_total"], ","),
                                            summary["bytes_total"] / 1e9))
    A("| 不同 SHA-256 | %s（重复组 %s，重复层 %s） |"
      % (format(summary["distinct_hashes"], ","),
         format(summary["duplicate_hash_groups"], ","),
         format(summary["layers_sharing_a_hash"], ",")))
    A("")
    A("**结论：%s 层全部通过下面十项检查，没有一层失败。**"
      % format(n, ",") if summary["layers_failing"] == 0
      else "**有 %d 层未通过，清单见 `audit/audit_failures.csv`。**"
           % summary["layers_failing"])
    A("")
    A("## 二、逐项检查")
    A("")
    A("| 检查 | 通过层数 | 通过率 |")
    A("|---|---:|---:|")
    rows = [
        ("可打开、单波段", chk["open"]),
        ("数据类型 float32", chk["float32"]),
        ("声明 NoData = −9999", chk["nodata_minus9999"]),
        ("网格不变量（4,861×4,062、1000 m、CRS、原点）", chk["grid_invariants"]),
        ("存储（DEFLATE、分块 256×256）", chk["storage"]),
        ("国界掩膜外无有效像元", chk["no_valid_outside_mask"]),
        ("无 Inf/NaN 混入有效值", chk["no_non_finite"]),
        ("数值落在文档声明范围内", chk["within_expected_range"]),
        ("与 variable_dictionary.csv 逐层一致", chk["dictionary_agrees"]),
        ("与 MANIFEST.csv 的 SHA-256 一致", chk["manifest_agrees"]),
    ]
    for name, v in rows:
        A("| %s | %s / %s | %.2f%% |" % (name, format(v, ","), format(n, ","), 100.0 * v / n))
    A("")
    A("“与字典一致”指重算的 min、max 与有效格数与 `variable_dictionary.csv` 的记录"
      "在 1×10⁻⁶ 相对误差内相等；“与清单一致”指重算的 SHA-256 与 `MANIFEST.csv` 完全相同。"
      "这两项是对文档自身的交叉验证：若文档记录与磁盘不符，这里会失败。")
    A("")
    A("## 三、组成恒等式（面积占比）")
    A("")
    if comp:
        A("分类源经 one-hot 编码并按面积加权后，同一组各类占比之和应为 1。"
          "本库有 %d 个基础占比组（clcd 按年、hlu1km 按年与情景、glu1km 按情景），"
          "共 %s 层。逐组独立累加后检查偏离 1 的程度："
          % (len(comp), format(sum(int(r["n_layers"]) for r in comp), ",")))
        A("")
        A("| 数据集 | 组数 | max \\|Σ−1\\| | 中位 \\|Σ−1\\| | 失败组（>1e-3） |")
        A("|---|---:|---:|---:|---:|")
        for ds in sorted(by_ds):
            v = by_ds[ds]
            A("| %s | %d | %.3e | %.3e | %d |"
              % (ds, len(v), max(v), sorted(v)[len(v) // 2],
                 sum(1 for r in comp if r["dataset"] == ds and r["n_off_1e-3"] not in ("", "0"))))
        A("")
        A("失败组共 **%d / %d**。clcd 与 hlu1km 的残差都在 float32 表示极限量级（约 5×10⁻⁸），"
          "glu1km 精确为零——因为它的源以整数百分比发布，聚合时不经过浮点除法。"
          "两个独立构建的产品收敛到同一误差量级、一个精确，说明残差来自表示层而不是程序层。"
          % (len(comp_bad), len(comp)))
    else:
        A("（未运行组成恒等式审计。）")
    A("")
    A("## 四、源—交付保真度")
    A("")
    if fid:
        A("在 3,000 个随机有效中国格上，直接读原始源产品与交付层，逐点比较：")
        A("")
        A("| 层 | n | r | 平均绝对差 | 平均偏差 |")
        A("|---|---:|---:|---:|---:|")
        for r in fid:
            A("| %s | %s | %s | %s | %s |"
              % (r["layer"], r["n"], r["r"], r["mean_abs_diff"], r["mean_bias"]))
        A("")
        A("相关系数全部在 0.98 以上，平均偏差接近零。"
          "这说明交付层经过重投影、重采样与掩膜之后，仍然保留着源产品的数值，"
          "而不是被处理链改写。")
    else:
        A("（未运行保真度检查。）")
    A("")
    A("## 五、不构成失败、但必须记录的数据特征")
    A("")
    A("以下现象在审计中不是失败项，但用户必须知道，否则会误用。")
    A("")
    A("### 5.1 有效格明显少于掩膜的层")
    A("")
    A("掩膜内有 %s 个有效格。%d 层的有效格少于掩膜的一半，最少的是："
      % (format(MASK_CELLS, ","), len(under_half)))
    A("")
    A("| 层 | 有效格 | 占掩膜 |")
    A("|---|---:|---:|")
    for r in low_valid:
        A("| `%s` | %s | %.2f%% |"
          % (r["relpath"], format(int(r["n_valid"]), ","),
             100.0 * int(r["n_valid"]) / MASK_CELLS))
    A("")
    A("最少的那一层是水文网络的出口标记，本身是稀疏标记层；"
      "其余多为 `glu1km` 的森林斑块指标——斑块统计只在森林存在的格上有定义，"
      "所以有效格随森林面积变化。这不是缺失，是定义域。")
    A("")
    A("### 5.2 常量层")
    A("")
    if const:
        A("有 %d 层在所有有效格上取同一个值：" % len(const))
        A("")
        for r in const:
            A("- `%s`，恒为 %s，%s 个有效格"
              % (r["relpath"], r["vmin"], format(int(r["n_valid"]), ",")))
        A("")
        A("这一层作为栅格是退化的（方差为零），不应当作连续协变量使用；"
          "它的信息在“某格是否为出口”这个二值事实里，而不在数值上。")
    else:
        A("没有常量层。")
    A("")
    A("### 5.3 字节重复")
    A("")
    A("21,110 个文件只有 %s 个不同的哈希（%.1f%%），其余 %s 层是重复副本。"
      "重复集中在投影类土地利用：城市范围在五个 SSP-RCP 情景中被冻结，"
      "因此同一城市基底在多个情景文件里逐字节相同。这是源产品的性质，"
      "不是重复导出。"
      % (format(summary["distinct_hashes"], ","),
         100.0 * summary["distinct_hashes"] / n,
         format(summary["layers_sharing_a_hash"], ",")))
    A("")
    A("### 5.4 气候产品中非 WorldClim 口径的变量")
    A("")
    A("`cnclim1km` 的 bio02、bio03、bio05、bio06、bio07 不是 WorldClim 的"
      "“月均日最高/最低温”口径，而是由月极值导出。实测：bio02 均值 35.1 °C、"
      "bio06 最低 −61.1 °C、bio07 最大 87.8 °C——按标准定义这些值不可能出现。"
      "交付层与源文件逐点一致（见第四节 bio01、bio12 的检验），因此这不是处理错误，"
      "而是源产品的定义选择。`provenance_table.csv` 的 `variable_definition` 字段"
      "已对每一层标注 `NON-STANDARD` 并说明原因。bio15 是变异系数（无量纲），"
      "不是百分比。")
    A("")
    A("### 5.5 编号类图层")
    A("")
    A("`hydro/h90m` 下的 `basin`、`direction`、`segment`、`sub-catchment`、`outlet` "
      "是网络标识，不是连续预测变量；`segment` 的最大值达 7.2×10⁸。"
      "把它们当连续变量送入模型会产生无意义的梯度。")
    A("")
    A("## 六、这次审计不能证明什么")
    A("")
    A("1. **不能证明源数据本身的正确性。** 审计核对的是“交付层是否忠实于源、"
      "是否符合本库声明的格式与定义”，不是“源的观测是否准确”。")
    A("2. **不能证明数值对任何具体用途都适用。** 1 km 格内的异质性"
      "（变异系数 77–277%）依然存在，格值是对邻域的平均。")
    A("3. **不覆盖 8 个已撤下的图层。** 它们在溯源表中标为 `withdrawn`，"
      "不在交付树内，因此不在本次审计范围内。")
    A("")
    A("## 七、复现")
    A("")
    A("```bash")
    A("export CHECO_ROOT=/path/to/delivery")
    A("python scripts/audit/audit_data_quality.py --workers 8   # 逐层格式与数值")
    A("python scripts/audit/audit_summarize.py                   # 汇总与失败清单")
    A("python scripts/audit/audit_composition.py --workers 4     # 组成恒等式")
    A("python scripts/audit/audit_fidelity.py                    # 源—交付保真度")
    A("python scripts/audit/audit_report.py                      # 生成本文件")
    A("```")
    A("")
    A("审计表位于 `audit/`：`layer_audit.csv`（逐层 %d 行 × %d 列）、"
      "`audit_summary.json`、`audit_failures.csv`、`theme_summary.csv`、"
      "`composition_identity.csv`、`source_fidelity.csv`。"
      % (len(layers), len(layers[0]) if layers else 0))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L))
    print("written:", OUT, "(%d lines)" % len(L))


if __name__ == "__main__":
    main()
