# R/tools/check_h90m_accum.R
# 【结论：候选方案已试并被否决，脚本保留作为证据】
# 本脚本对 Hydrography90m 累积流的 5 层候选数据做了 19 项断言，
# 当时 PASS 19 / FAIL 0，但它只能证明“内部自洽”，证不了“与旧版等价”。
# 后续发现峰值被压低 6.2 倍（见 15_ingest_h90m_accumulation.R 头部），
# 因此数据已回滚。脚本保留作为“检查通过但方案仍被否”的记录。
#
# Hydrography90m 累积流候选层的质量检查
#
# 逐项断言，每项都打印比较次数，避免"跑完但什么都没查"。
#
# 用法：Rscript R/tools/check_h90m_accum.R
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
suppressMessages(library(terra))

OUT <- file.path(PATH_SCRATCH(), "h90m_accum_candidate")
TPL <- rast(PATH_TEMPLATE())
MSK <- rast(PATH_MASK())

ok <- 0L; bad <- 0L; fails <- character(0)
say <- function(label, cond, detail = "") {
  if (isTRUE(cond)) { ok <<- ok + 1L; cat(sprintf("  PASS  %-46s %s\n", label, detail)) }
  else { bad <<- bad + 1L; fails <<- c(fails, label)
         cat(sprintf("  FAIL  %-46s %s\n", label, detail)) }
}

stems <- c("glo_hydro_h90m_accumulation",
           sprintf("glo_hydro_h90m_accumulation_f%d", c(1000L, 5000L, 10000L, 20000L)))
files <- file.path(OUT, paste0(stems, ".tif"))
stopifnot(all(file.exists(files)))

cat("================================================================\n")
cat(" Hydrography90m \u7d2f\u79ef\u6d41\u5019\u9009\u5c42\u8d28\u91cf\u68c0\u67e5\n")
cat("================================================================\n\n")

# ---- 1) 网格不变量 ----
cat("1) \u7f51\u683c\u4e0d\u53d8\u91cf\uff08\u4e0e\u6a21\u677f\u9010\u9879\u6bd4\u5bf9\uff09\n")
n_cmp <- 0L
for (i in seq_along(files)) {
  r <- rast(files[i])
  same <- ncol(r) == ncol(TPL) && nrow(r) == nrow(TPL) &&
          isTRUE(all.equal(as.vector(ext(r)), as.vector(ext(TPL)))) &&
          isTRUE(all.equal(res(r), res(TPL))) &&
          crs(r) == crs(TPL)
  n_cmp <- n_cmp + 1L
  say(paste0("  \u7b2c ", i, " \u5c42\u7f51\u683c\u4e0e\u6a21\u677f\u4e00\u81f4"), same,
      sprintf("%d x %d, %.0f m", ncol(r), nrow(r), res(r)[1]))
}
say("\u7f51\u683c\u6bd4\u8f83\u603b\u6570 = 5", n_cmp == 5L, sprintf("\u5b9e\u9645 %d", n_cmp))

# ---- 2) nodata 声明与无负值 ----
cat("\n2) nodata \u58f0\u660e\u4e0e\u975e\u8d1f\u6027\n")
for (i in seq_along(files)) {
  # 从 GDAL \u5143\u6570\u636e\u8bfb\u58f0\u660e\u7684 nodata\uff08NAflag() \u5bf9\u6d6e\u70b9\u4e0d\u53ef\u9760\uff09
  d <- terra::describe(files[i], print = FALSE)
  nd <- sub(".*NoData Value=([^ ]+).*", "\\1", grep("NoData Value=", d, value = TRUE)[1])
  v <- values(rast(files[i]), mat = FALSE)
  nn <- sum(!is.na(v)); nneg <- sum(v < 0, na.rm = TRUE)
  say(sprintf("  \u7b2c %d \u5c42\u65e0\u8d1f\u503c", i), nneg == 0L,
      sprintf("\u8d1f\u503c %d / %s ; \u58f0\u660e nodata %s", nneg,
              format(nn, big.mark = ","), nd))
}

# ---- 3) \u8986\u76d6\u5ea6 ----
cat("\n3) \u8986\u76d6\u5ea6\n")
mv <- values(MSK, mat = FALSE); n_mask <- sum(mv == 1, na.rm = TRUE)
b  <- rast(files[1]); bv <- values(b, mat = FALSE)
n_b <- sum(!is.na(bv))
say("\u57fa\u5e95\u6709\u6548\u683c >= 99.5% \u63a9\u819c", n_b / n_mask >= 0.995,
    sprintf("%s / %s = %.2f%%", format(n_b, big.mark = ","),
            format(n_mask, big.mark = ","), 100 * n_b / n_mask))
# \u57fa\u5e95\u5e94\u4e3a\u63a9\u819c\u7684\u5b50\u96c6
out_of_mask <- sum(!is.na(bv) & mv == 0, na.rm = TRUE)
say("\u9707\u819c\u5916\u65e0\u6709\u6548\u503c", out_of_mask == 0L,
    sprintf("\u9707\u819c\u5916\u6709\u6548 %d\uff08\u6bd4\u8f83 %s \u683c\uff09",
            out_of_mask, format(length(mv), big.mark = ",")))

# ---- 4) \u7126\u70b9\u4e0d\u53d8\u91cf ----
cat("\n4) \u7126\u70b9\u4e0d\u53d8\u91cf\n")
mx <- numeric(0); mn <- numeric(0)
for (f in files) {
  r <- rast(f); g <- terra::global(r, c("min", "max", "mean"), na.rm = TRUE)
  mx <- c(mx, g[1, "max"]); mn <- c(mn, g[1, "min"])
}
mono <- all(diff(mx) < 0)
say("max \u968f\u7a97\u53e3\u5355\u8c03\u9012\u51cf", mono,
    paste(sprintf("%.4g", mx), collapse = " > "))
means <- numeric(0)
for (f in files) means <- c(means, terra::global(rast(f), "mean", na.rm = TRUE)[1, 1])
spread <- diff(range(means))
rel <- spread / abs(means[1])
# 2026-10-21 修正判据：“均值守恒”从来不是精确成立的。
# 它的相对幅度取决于变量偏态，用交付树现有族标定：
#   clcd cropland 0.017% | hfp 0.201% | hlu1km urban 0.712%
#   clcd impervious 0.895% | hydrosheds accumulation 1.536%
# 原用绝对阈值 1e-6，等于只对均匀型变量成立。
# 改为相对阈值 2%（宽于现有最大的 1.536%）。
say("五尺度均值相对极差 < 2%", rel < 0.02,
    sprintf("绝对 %.3g ; 相对 %.3f%% ; 均值 %.4g", spread, 100 * rel, means[1]))
# \u7126\u70b9\u503c\u4e0d\u5e94\u8d85\u51fa\u57fa\u5e95\u8303\u56f4
say("\u7126\u70b9 max \u4e0d\u8d85\u8fc7\u57fa\u5e95 max", all(mx[2:5] <= mx[1] + 1e-9),
    sprintf("\u57fa\u5e95 %.4g\uff1b\u7126\u70b9\u6700\u5927 %.4g", mx[1], max(mx[2:5])))

# ---- 5) \u4e0e HydroSHEDS \u4ea4\u53c9\u9a8c\u8bc1\uff08\u6b63\u503c\u683c\uff09----
cat("\n5) \u4e0e HydroSHEDS \u4ea4\u53c9\u9a8c\u8bc1\n")
hs <- rast(file.path(PATH_COV(), "glo/hydro/hydrosheds/accumulation/glo_hydro_hydrosheds_accumulation.tif"))
hv <- values(hs, mat = FALSE)
both <- !is.na(bv) & !is.na(hv)
cat(sprintf("        \u5171\u6709\u6709\u6548\u683c\uff1a%s\n", format(sum(both), big.mark = ",")))
hs_area <- hv * 0.00774
ratio <- bv[both] / pmax(hs_area[both], 1e-9)
say("h90m/HS \u6bd4\u503c\u4e2d\u4f4d\u6570\u5728 [0.8, 1.5]", median(ratio) >= 0.8 && median(ratio) <= 1.5,
    sprintf("%.3f", median(ratio)))
sp <- cor(bv[both], hs_area[both], method = "spearman")
say("Spearman \u76f8\u5173 > 0.5", sp > 0.5, sprintf("%.3f", sp))

# ---- 6) \u4e0e\u6cb3\u6d41\u7b49\u7ea7\u7684\u5355\u8c03\u5173\u7cfb ----
cat("\n6) \u4e0e order-strahler \u7684\u5355\u8c03\u5173\u7cfb\uff08\u5168\u56fd\uff09\n")
str <- rast(file.path(PATH_COV(), "glo/hydro/h90m/order-strahler/glo_hydro_h90m_order-strahler.tif"))
sv <- values(str, mat = FALSE)
med <- numeric(0); ords <- integer(0)
for (k in 1:8) {
  sel <- both & !is.na(sv) & sv == k
  if (sum(sel) < 50) next
  ords <- c(ords, k); med <- c(med, median(bv[sel]))
}
cat(sprintf("        \u7b49\u7ea7-\u4e2d\u4f4d\u6570\u5bf9\uff1a%s\n",
            paste(sprintf("%d:%.3g", ords, med), collapse = "  ")))
say("\u4e2d\u4f4d\u6570\u968f\u7b49\u7ea7\u4e25\u683c\u9012\u589e", all(diff(med) > 0),
    sprintf("%d \u4e2a\u7b49\u7ea7", length(med)))

cat("\n================================================================\n")
cat(sprintf(" \u6c47\u603b: PASS %d / FAIL %d\n", ok, bad))
if (bad) cat(" \u5931\u8d25\u9879:\n", paste0("   - ", fails, collapse = "\n"), "\n")
cat("================================================================\n")
invisible(bad)
