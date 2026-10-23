# R/tests/test_69_legend_order.R
# 回归测试：把"segregate 按码升序出波段"这个坑编码成断言
#
# 背景（缺陷 33）：terra::segregate() 的输出波段按**类别码升序**排列，
# 与传入 classes 的顺序无关。hlu1km 的图例语义序是
#   urban(11) cropland(22) pasture(33) managed forest(441) unmanaged forest(442)
#   unmanaged grass/shrub(55) sparse(66) water(77)
# 数值序却是 11,22,33,55,66,77,441,442 —— 441/442 排到了 55 之前，
# 于是 5 个类别的层名与内容错位，影响 18,440 层。
#
# 本测试对每个使用 segregate 的数据集断言：
#   ① 图例的 code 向量必须单调递增；或
#   ② 代码在配对前已显式按 code 排序（hlu1km 采用这种方式）。
# 只要有一条成立，配对就是安全的。
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

ok <- 0L; bad <- 0L
chk <- function(label, cond, detail = "") {
  if (isTRUE(cond)) { cat(sprintf("  PASS  %s\n", label)); ok <<- ok + 1L }
  else { cat(sprintf("  FAIL  %s  %s\n", label, detail)); bad <<- bad + 1L }
}

cat("=== 1. clcd：图例 code 必须单调递增（天然安全的前提）===\n")
.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/06_derive_lulc_clcd.R", envir = .ing)
cd_codes <- as.integer(names(.ing$CLCD_LEGEND))
cd_names <- unname(.ing$CLCD_LEGEND)
cat(sprintf("  codes = %s\n", paste(cd_codes, collapse = ", ")))
cat(sprintf("  names = %s\n", paste(cd_names, collapse = ", ")))
chk("clcd 的 code 严格递增", all(diff(cd_codes) > 0),
    sprintf("实际 %s", paste(cd_codes, collapse = ",")))
chk("clcd 无重复 code", !anyDuplicated(cd_codes))
chk("clcd 类别数为 9", length(cd_codes) == 9L, sprintf("实际 %d", length(cd_codes)))
chk("clcd code 与 provenance 目录名一一对应",
    setequal(cd_names, c("cropland","forest","shrub","grassland","water",
                         "snowice","barren","impervious","wetland")))

cat("\n=== 2. hlu1km：代码必须显式按 code 排序后再配对（修复后的方式）===\n")
.h <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/07_derive_lulc_hlu1km.R", envir = .h)
h_codes <- .h$hlu_codes_sorted()
h_names <- .h$hlu_cnames()
cat(sprintf("  codes(sorted) = %s\n", paste(h_codes, collapse = ", ")))
cat(sprintf("  names         = %s\n", paste(h_names, collapse = ", ")))
chk("hlu1km 的 code 已按升序返回", !is.unsorted(h_codes),
    sprintf("实际 %s", paste(h_codes, collapse = ",")))
chk("hlu1km code 与 name 长度一致", length(h_codes) == length(h_names))
chk("hlu1km 类别数为 8", length(h_codes) == 8L, sprintf("实际 %d", length(h_codes)))

# 关键断言：未排序的图例确实是"危险"的，用以证明必须排序
raw_codes <- as.integer(names(.h$HLU_LEGEND))
cat(sprintf("  原始图例顺序 codes = %s（若此为升序则无需排序）\n",
            paste(raw_codes, collapse = ", ")))
chk("hlu1km 原始图例不是升序（说明排序步骤不可或缺）", is.unsorted(raw_codes),
    "原始图例竟已升序——排序步骤的前提不再成立，需复查")

cat("\n=== 3. 经验证：segregate 输出波段确实按码升序 ===\n")
# 用一个小构造样本直接验证 terra 的行为，防止 terra 版本升级后语义变化
m <- matrix(c(3, 1, 2, 1, 3, 2, 2, 2, 1), nrow = 3, byrow = TRUE)
rr <- terra::rast(m, crs = "EPSG:4326")
# 故意用**非升序**的 classes 传入
cls <- c(3L, 1L, 2L)
sg <- terra::segregate(rr, classes = cls, keep = FALSE, other = 0)
counts <- vapply(seq_len(terra::nlyr(sg)), function(k) sum(terra::values(sg[[k]], mat = FALSE) == 1, na.rm = TRUE), 0)
cat(sprintf("  传入 classes = %s -> 输出 %d 层，各层 1 的个数 = %s\n",
            paste(cls, collapse = ","), terra::nlyr(sg), paste(counts, collapse = ", ")))
# 预期值**从矩阵现算**，不手数——第一次写这个测试时我把 2 的个数数错了（写成 3，实为 4），
# 结果测试报了"失败"，而实际是 segregate 行为正确、我的期望值错误。
# 教训：断言里的常量应当由输入推导，不要手工填写。
expect <- vapply(sort(cls), function(k) sum(m == k), 0L)
cat(sprintf("  按码升序的预期 1 的个数 = %s（由矩阵现算）\n", paste(expect, collapse = ",")))
chk("segregate 输出按码升序（不是按传入顺序）",
    identical(as.integer(counts), as.integer(expect)),
    sprintf("实际 %s vs 预期 %s；若与传入顺序 cls=%s 一致则说明语义变了",
            paste(counts, collapse = ","), paste(expect, collapse = ","),
            paste(cls, collapse = ",")))

cat(sprintf("\n=== 汇总: PASS %d / FAIL %d ===\n", ok, bad))
if (bad > 0L) quit(save = "no", status = 1L)
