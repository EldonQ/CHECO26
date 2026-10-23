# R/tests/test_62_segregate_order.R
# 最小复现：证明 terra::segregate() 输出的波段按类别码**升序**，与 classes 向量顺序无关
# 这是 2026-10-19 发现的 hlu1km 图层名错位 bug 的依据
suppressPackageStartupMessages(library(terra))

vals  <- c(442, 11, 55, 441, 22, 77, 33, 66)
r <- rast(nrows = 1, ncols = 8, xmin = 0, xmax = 8, ymin = 0, ymax = 1)
values(r) <- vals
codes <- c(11, 22, 33, 441, 442, 55, 66, 77)   # 故意用未排序顺序传入

oh <- segregate(r, classes = codes, keep = FALSE, other = 0)
got <- integer(nlyr(oh))
for (k in seq_len(nlyr(oh))) {
  hit <- which(as.integer(values(oh[[k]])) == 1)
  got[k] <- vals[hit]
}

expected_sorted <- sort(codes)
cat("传入 codes      :", paste(codes, collapse = " "), "\n")
cat("每波段实际类别   :", paste(got, collapse = " "), "\n")
cat("按码升序应为     :", paste(expected_sorted, collapse = " "), "\n")
stopifnot(identical(got, expected_sorted))
cat("\n通过：segregate 确实按码升序排列，与传入顺序无关。\n")
cat("故 `cnames` 必须与 `sort(codes)` 对齐，不能沿用未排序图例。\n")
