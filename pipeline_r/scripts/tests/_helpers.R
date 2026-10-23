# R/tests/_helpers.R -- 测试共用：层比对判据
#
# 判据来源（2026-10-19 实测，见 test_13_diff_tail.R）：
#   R(terra/GDAL 3.10.1) 与 Python(rasterio/GDAL 3.10.3) 的 warp 在亚像元采样上
#   存在不可消除的差异（PROJ 相同，GDAL 补丁版不同）。实测结构：
#     * 有效性不一致 ≤0.011%，且 bilinear 层 100% 贴着无效域边界（GDAL 边界判定差异）
#     * 无系统偏差（|mean(d)/span| 最大 1.1e-05）
#     * bilinear 层 0 个像元超过 0.05 span；average/mode 层 ≤28 个像元超过 0.1 span
#
# 合格条件（同时满足）：
#   C1 有效性不一致 ≤ 0.02% 共有效像元
#   C2 |mean(d)| / span < 1e-3
#   C3 mean|d|   / span < 5e-3
#   C4 |d|/span > 0.1 的像元 ≤ 0.001%（≈94 个/9.4M）

read_clean <- function(path) {
  r <- terra::rast(path)
  nd <- terra::NAflag(r)
  v <- terra::values(r, mat = FALSE)
  if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
  v[is.nan(v)] <- NA
  terra::values(r) <- v
  r
}

compare_layers <- function(a, b, tol = list(mism = 2e-4, bias = 1e-3,
                                            mean = 5e-3, tail = 1e-5)) {
  av <- terra::values(a, mat = FALSE)
  bv <- terra::values(b, mat = FALSE)
  com <- !is.na(av) & !is.na(bv)
  n_com <- sum(com)
  if (n_com < 1000) return(list(pass = FALSE, note = "有效像元不足"))
  only_a <- sum(!is.na(av) & is.na(bv))
  only_b <- sum(is.na(av) & !is.na(bv))
  n_mis  <- only_a + only_b

  d    <- av[com] - bv[com]
  span <- diff(range(bv[com]))
  ms   <- mean(d) / span
  ma   <- mean(abs(d)) / span
  dd   <- abs(d) / span
  mx   <- max(dd)
  n_tail <- sum(dd > 0.1)

  c1 <- n_mis / (n_com + n_mis) <= tol$mism
  c2 <- abs(ms) < tol$bias
  c3 <- ma < tol$mean
  c4 <- n_tail / n_com <= tol$tail

  list(pass = c1 && c2 && c3 && c4,
       n_com = n_com, only_a = only_a, only_b = only_b,
       mism_pct = 100 * n_mis / (n_com + n_mis),
       bias = ms, mean_abs = ma, max_abs = mx, n_tail = n_tail,
       span = span, c = c(c1, c2, c3, c4))
}

fmt_cmp <- function(r) {
  if (!is.null(r$note)) return(sprintf("[%s]", r$note))
  sprintf("com %s | mis %d(%.4f%%) | bias %+.1e | mean|d| %.1e | max|d| %.1e | tail %d",
          format(r$n_com, big.mark = ","), r$only_a + r$only_b, r$mism_pct,
          r$bias, r$mean_abs, r$max_abs, r$n_tail)
}

# ---- 分类/指标层判据 -------------------------------------------------------
#' 对 0/1 指标层或类别层，幅度判据无意义（差 1 就是 100% span）。
#' 改用**一致率**：相同像元占比 ≥ 99.9%。
#' 依据：nearest 重采样在近简并像元上会因 GDAL 补丁版不同而翻到相邻源像元，
#' 实测 GLULC history_2020 的类指派一致率 99.947%，bio01 nearest 为 95.1%
#' （后者是 1.1km->1km 的真重投影，本库的 GLULC 源已近 1km，故一致率高得多）。
compare_categorical <- function(a, b, min_agree = 0.999) {
  av <- terra::values(a, mat = FALSE)
  bv <- terra::values(b, mat = FALSE)
  com <- !is.na(av) & !is.na(bv)
  n_com <- sum(com)
  if (n_com < 1000) return(list(pass = FALSE, note = "有效像元不足"))
  agree <- mean(av[com] == bv[com])
  n_mis <- sum(!is.na(av) & is.na(bv)) + sum(is.na(av) & !is.na(bv))
  list(pass = agree >= min_agree, n_com = n_com, agree = agree,
       n_disagree = sum(av[com] != bv[com]), n_mismask = n_mis)
}

fmt_cat <- function(r) {
  if (!is.null(r$note)) return(sprintf("[%s]", r$note))
  sprintf("com %s | 一致率 %.4f%% | 不一致 %d | 掩膜差异 %d",
          format(r$n_com, big.mark = ","), 100 * r$agree, r$n_disagree, r$n_mismask)
}
