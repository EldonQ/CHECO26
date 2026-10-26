# 审计的审计：检查脚本自身的可靠性（2026-10-26）

## 一、为什么先查脚本

一个"全部通过"的审计结果，只有在它的检查**真的会在数据出错时报错**的前提下才有意义。
检查脚本的典型失效方式不是崩溃，而是**空跑通过**：

- 某个统计量没算出来（空字符串），汇总时被当作 0 → "0 个缺陷" → 通过；
- 某个分组没有可检查的像元，偏差被填 0 → "完美闭合" → 通过；
- 文档和实际**两边都没取到值**，`identical(NA, NA)` 为真 → 通过；
- 比较函数在取不到值时不报错，脚本正常退出 → 外部只看退出码就会当成通过。

这些都不会留下痕迹。所以这一轮先造一个"必然出错"的环境，看检查抓不抓。

## 二、方法：变异测试

`scripts/audit/test_audit_scripts.py` 在临时目录里搭一棵**迷你交付树**（复制真实的
`mask_china.tif` 与 `template_albers1km.tif`，使网格检查有真实基准），然后：

1. 每个用例只注入**一个**已知缺陷，其余元数据（MANIFEST、字典、溯源表）都按该文件的实际
   统计写正确——这样若某层报错，只可能是被注入的那个缺陷；
2. 用 `CHECO_ROOT` 把**真脚本**指向这棵树跑（不是复制逻辑，不是重写判定）；
3. 断言用例的失败项里出现预期关键字，对照组必须通过。

`R/tools/test_checkers.R` 用另一种方式做同一件事：`parse()` 真实脚本、只求值到辅助函数
定义为止，然后把 `chk()` / `say()` 拿出来喂三种输入（不相等、两边 NA、相等），
要求得到 FAIL / FAIL / PASS。

## 三、发现并修复的缺陷

变异测试 + 定向静态扫描（找 `except: pass`、`num(x, 0)`、空集合直接返回）共查出 6 处。

### 1. 值域检查可被"缺范围"绕过（严重，变异测试抓到）

`audit_data_quality.py` 只在 `expected_range` 能解析时才填 `n_below` / `n_above`；
解析失败时这两列留空，`audit_summarize.py` 用 `num(x, 0)` 读成 0 → **没有记录值域的层
被判为"值域内"**。

修复：新增 `range_ok` 列（`True` / `no_range` / `no_valid_cells`），汇总要求它等于 `True`；
`no_range` 与"整层无有效像元"分别报 `range_unverifiable=no_range` / `=no_valid_cells`。

### 2. 计数列留空仍算通过（中等）

`n_nonfinite` / `n_outside_mask` / `n_below` / `n_above` 四列同样用 `num(x, 0)` 读。
修复：改为"读不到就报 `xxx=unreadable` 失败"，计数只认可读的 0。

### 3. 零格占比组算完美闭合（严重）

`audit_composition.py` 里 `d = np.abs(dev[inside]) if n_cells else np.array([0.0])`：
一个**没有任何可检查像元**的组会报 `max|sum-1| = 0`，看起来是最完美的一组。
修复：`n_cells == 0` 时返回空值并记 `error = no_cells_inspected`，该组进入失败列表；
同时删除一个永远返回 `None` 的死函数 `audit_group()`。

### 4. 报告把空偏差当 0（轻微）

`audit_report.py` 的 `float(x) if x else 0.0`：空值参与"最大偏差"统计会拉低结果。
修复：空值不参与最大值，改由失败列表体现。

### 5. 气候比较"什么都没比到"也算成功（中等）

`compare_climate_chelsa.py` 在 `rows` 为空时 `print("nothing compared"); return`——
脚本正常退出、不写输出文件。修复：改为 `SystemExit`，让"没比较"变成失败。

### 6. R 检查器的 NA 路径（中等）

- `check_docs_consistency.R::chk()` 用 `identical(as.character(claimed), as.character(actual))`，
  两边同时取不到值（都是 `NA`）时返回 TRUE → **通过**。修复：任一为 `NA` 或长度不为 1 直接判失败。
- `check_trends.R::say()` 用 `abs(as.numeric(claimed) - as.numeric(actual)) <= tol`，
  遇到 `NA` 会触发 `if (NA)` 报错崩掉。修复：非有限值按失败处理并给出说明。

## 四、变异测试的当前结果

| 类别 | 用例 | 结果 |
|---|---|---|
| 逐层审计 | 14（对照 1 + 缺陷 13） | 14 / 14 抓到 |
| 组成恒等式 | 3（好组、坏组、零格组） | 3 / 3 正确区分 |
| 焦点不越基底 | 3（范围内、低于、高于） | 3 / 3 正确判定 |
| R 检查器辅助函数 | 6 | 6 / 6 |

逐层用例覆盖：非有限值、掩膜外有效值、超上界、dtype、错误 nodata、网格错位、无压缩、
尺寸不符、文件损坏、SHA 不符、字典不符、**缺值域**、**整层无有效值**。

复跑命令：

```
python scripts/audit/test_audit_scripts.py     # 20 项，退出码 0 表示全部符合预期
Rscript R/tools/test_checkers.R                # 6 项
```

## 五、这次自测抓到的"我自己的回退"

给 `audit_summarize.py` 加四列严格判定时，我把 `range_ok` 那段一起替换掉了，导致
#1 的修复失效。变异测试立刻从 20/20 掉到 18/20，两项报 `below_range=unreadable` 而不是
`range_unverifiable`——一眼可辨。没有这个测试台，这个回退会静默留在脚本里。

## 六、仍然存在的已知边界

1. **`valid` 的判定用硬编码的 -9999**（`audit_one`），不是文件声明的 nodata。
   一个把 nodata 声明成别的值、同时用该值填充的文件，会先被 `nodata` 检查判失败，
   所以不会漏过；但此时它报出的 min/max 是按"只有 -9999 才算缺失"算的，数字不可信。
   这属于"报错时附带数字不准确"，不影响判定。
2. **无有效像元的层**现在会失败（`no_valid_cells`）。这是有意的：空层没有交付价值。
3. **`scripts/audit/` 里的历史一次性脚本**（`audit_table.py`、`final_audit.py`、
   `verdict_scan.py`、`check_review_points.py`、`check_unit_scale.py`、`check_time_variance.py`、
   `scan_all_layers.py`、`audit_manifest.py`、`verify_provenance.py`）**已于 2026-10-26 删除**：
   它们不在当前证据链里，结果不进入任何交付结论。清单见 `../audit/deleted_20261026.csv`。
   注意 `USAGE_NOTES_AND_LIMITATIONS.md` 附录里依赖这些脚本的复现说明因此降级为历史记录。
4. **`verify_independent.R` 的抽样层数固定**（60 层网格、10 层统计、8 层 SHA），
   抽样不能替代全量；全量结论来自 `audit_data_quality.py` 的 21,110 层。
