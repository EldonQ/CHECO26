# CHECO26 数据质量审计

本文件由 `scripts/audit/audit_report.py` 从 `audit/` 下的审计表生成，文中每个数字都可在对应 CSV 中查到，没有任何一个数字是手写的。重跑 `audit_data_quality.py`、`audit_composition.py`、`audit_fidelity.py` 与 `audit_summarize.py` 即可完整复现。

## 一、范围与结论

审计对象是交付树 `data/covariates/glo/` 下的全部 GeoTIFF，逐层打开、逐层读值，不抽样、不依赖溯源表里的记录值。

| 项目 | 结果 |
|---|---|
| 应审计层数 | 21,110 |
| 实际审计层数 | **21,110** |
| 主题数 | 8 |
| 未通过任何检查的层 | **0** |
| 交付字节总数 | 169,401,430,367（169.4 GB） |
| 不同 SHA-256 | 14,047（重复组 1,167，重复层 7,063） |

**结论：21,110 层全部通过下面十项检查，没有一层失败。**

## 二、逐项检查

| 检查 | 通过层数 | 通过率 |
|---|---:|---:|
| 可打开、单波段 | 21,110 / 21,110 | 100.00% |
| 数据类型 float32 | 21,110 / 21,110 | 100.00% |
| 声明 NoData = −9999 | 21,110 / 21,110 | 100.00% |
| 网格不变量（4,861×4,062、1000 m、CRS、原点） | 21,110 / 21,110 | 100.00% |
| 存储（DEFLATE、分块 256×256） | 21,110 / 21,110 | 100.00% |
| 国界掩膜外无有效像元 | 21,110 / 21,110 | 100.00% |
| 无 Inf/NaN 混入有效值 | 21,110 / 21,110 | 100.00% |
| 数值落在文档声明范围内 | 21,110 / 21,110 | 100.00% |
| 与 variable_dictionary.csv 逐层一致 | 21,110 / 21,110 | 100.00% |
| 与 MANIFEST.csv 的 SHA-256 一致 | 21,110 / 21,110 | 100.00% |

“与字典一致”指重算的 min、max 与有效格数与 `variable_dictionary.csv` 的记录在 1×10⁻⁶ 相对误差内相等；“与清单一致”指重算的 SHA-256 与 `MANIFEST.csv` 完全相同。这两项是对文档自身的交叉验证：若文档记录与磁盘不符，这里会失败。

## 三、组成恒等式（面积占比）

分类源经 one-hot 编码并按面积加权后，同一组各类占比之和应为 1。本库有 497 个基础占比组（clcd 按年、hlu1km 按年与情景、glu1km 按情景），共 3,982 层。逐组独立累加后检查偏离 1 的程度：

| 数据集 | 组数 | max \|Σ−1\| | 中位 \|Σ−1\| | 失败组（>1e-3） |
|---|---:|---:|---:|---:|
| clcd | 26 | 5.215e-08 | 5.215e-08 | 0 |
| glu1km | 10 | 0.000e+00 | 0.000e+00 | 0 |
| hlu1km | 461 | 4.843e-08 | 4.470e-08 | 0 |

失败组共 **0 / 497**。clcd 与 hlu1km 的残差都在 float32 表示极限量级（约 5×10⁻⁸），glu1km 精确为零——因为它的源以整数百分比发布，聚合时不经过浮点除法。两个独立构建的产品收敛到同一误差量级、一个精确，说明残差来自表示层而不是程序层。

## 四、源—交付保真度

在 3,000 个随机有效中国格上，直接读原始源产品与交付层，逐点比较：

| 层 | n | r | 平均绝对差 | 平均偏差 |
|---|---:|---:|---:|---:|
| topo/elev | 2996 | 0.99987 | 15.82631 | -0.745748 |
| soil/ph_0_5 | 2996 | 0.993355 | 0.080713 | 0.00022 |
| anthro/hfp_2000 | 2993 | 0.982811 | 0.881801 | 0.026268 |
| bioclim/bio01_present | 2978 | 0.999358 | 0.153969 | -0.001509 |
| bioclim/bio12_present | 2978 | 0.999869 | 4.047402 | 0.075632 |

相关系数全部在 0.98 以上，平均偏差接近零。这说明交付层经过重投影、重采样与掩膜之后，仍然保留着源产品的数值，而不是被处理链改写。

## 五、不构成失败、但必须记录的数据特征

以下现象在审计中不是失败项，但用户必须知道，否则会误用。

### 5.1 有效格明显少于掩膜的层

掩膜内有 9,490,310 个有效格。21 层的有效格少于掩膜的一半，最少的是：

| 层 | 有效格 | 占掩膜 |
|---|---:|---:|
| `glo/hydro/h90m/outlet/glo_hydro_h90m_outlet.tif` | 18,551 | 0.20% |
| `glo/lulc/glu1km/scenario/2100/ssp585/glo_lulc_glu1km_scenario_2100_ssp585_patchdensity-forest_f1000.tif` | 2,685,053 | 28.29% |
| `glo/lulc/glu1km/scenario/2100/ssp585/glo_lulc_glu1km_scenario_2100_ssp585_patchsize-forest_f1000.tif` | 2,685,053 | 28.29% |
| `glo/lulc/glu1km/scenario/2050/ssp585/glo_lulc_glu1km_scenario_2050_ssp585_patchdensity-forest_f1000.tif` | 2,740,179 | 28.87% |
| `glo/lulc/glu1km/scenario/2050/ssp585/glo_lulc_glu1km_scenario_2050_ssp585_patchsize-forest_f1000.tif` | 2,740,179 | 28.87% |

最少的那一层是水文网络的出口标记，本身是稀疏标记层；其余多为 `glu1km` 的森林斑块指标——斑块统计只在森林存在的格上有定义，所以有效格随森林面积变化。这不是缺失，是定义域。

### 5.2 常量层

有 1 层在所有有效格上取同一个值：

- `glo/hydro/h90m/outlet/glo_hydro_h90m_outlet.tif`，恒为 1.0，18,551 个有效格

这一层作为栅格是退化的（方差为零），不应当作连续协变量使用；它的信息在“某格是否为出口”这个二值事实里，而不在数值上。

### 5.3 字节重复

7,063 层共享 14,047 个不同的哈希，即只有 14,047 层是逐字节不同的（66.5%）。重复集中在投影类土地利用：城市范围在五个 SSP-RCP 情景中被冻结，因此同一城市基底在多个情景文件里逐字节相同。这是源产品的性质，不是重复导出。

### 5.4 气候产品中非 WorldClim 口径的变量

`cnclim1km` 的 bio02、bio03、bio05、bio06、bio07 不是 WorldClim 的“月均日最高/最低温”口径，而是由月极值导出。实测：bio02 均值 35.1 °C、bio06 最低 −61.1 °C、bio07 最大 87.8 °C——按标准定义这些值不可能出现。交付层与源文件逐点一致（见第四节 bio01、bio12 的检验），因此这不是处理错误，而是源产品的定义选择。`provenance_table.csv` 的 `variable_definition` 字段已对每一层标注 `NON-STANDARD` 并说明原因。bio15 是变异系数（无量纲），不是百分比。

### 5.5 编号类图层

`hydro/h90m` 下的 `basin`、`direction`、`segment`、`sub-catchment`、`outlet` 是网络标识，不是连续预测变量；`segment` 的最大值达 7.2×10⁸。把它们当连续变量送入模型会产生无意义的梯度。

## 六、这次审计不能证明什么

1. **不能证明源数据本身的正确性。** 审计核对的是“交付层是否忠实于源、是否符合本库声明的格式与定义”，不是“源的观测是否准确”。
2. **不能证明数值对任何具体用途都适用。** 1 km 格内的异质性（变异系数 77–277%）依然存在，格值是对邻域的平均。
3. **不覆盖 8 个已撤下的图层。** 它们在溯源表中标为 `withdrawn`，不在交付树内，因此不在本次审计范围内。

## 七、复现

```bash
export CHECO_ROOT=/path/to/delivery
python scripts/audit/audit_data_quality.py --workers 8   # 逐层格式与数值
python scripts/audit/audit_summarize.py                   # 汇总与失败清单
python scripts/audit/audit_composition.py --workers 4     # 组成恒等式
python scripts/audit/audit_fidelity.py                    # 源—交付保真度
python scripts/audit/audit_report.py                      # 生成本文件
```

审计表位于 `audit/`：`layer_audit.csv`（逐层 21110 行 × 36 列）、`audit_summary.json`、`audit_failures.csv`、`theme_summary.csv`、`composition_identity.csv`、`source_fidelity.csv`。