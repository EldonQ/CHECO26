# R/tests/test_60_hfp_series.R
# hfp 时间序列合理性：逐年均值应平滑变化；25 年应互不相同（排除路径 bug 导致重复）
# 用 terra::global 流式计算（不加载 19.7M 像元，避免满负荷时 bad_alloc）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

dir <- file.path(PATH_COV(), "glo/anthro/hfp")
years <- 2000:2024
mu <- numeric(length(years)); names(mu) <- years
sd_ <- mu
for (i in seq_along(years)) {
  p <- file.path(dir, years[i], "hfp", sprintf("glo_anthro_hfp_%d_hfp.tif", years[i]))
  if (!file.exists(p)) { mu[i] <- NA; sd_[i] <- NA; next }
  r <- terra::rast(p)
  g <- terra::global(r, c("mean", "sd"), na.rm = TRUE)
  mu[i] <- g[1, 1]; sd_[i] <- g[1, 2]
}

cat("=== hfp 逐年中国区均值 ===\n\n")
for (i in seq_along(years))
  cat(sprintf("  %d: 均值 %.4f  标准差 %.4f\n", years[i], mu[i], sd_[i]))

cat("\n=== 年际变化 ===\n")
d <- diff(mu)
cat(sprintf("  变化范围 [%+.4f, %+.4f]\n", min(d, na.rm = TRUE), max(d, na.rm = TRUE)))
cat(sprintf("  |变化| 均值 %.5f，最大 %.5f（占均值 %.2f%%）\n",
            mean(abs(d), na.rm = TRUE), max(abs(d), na.rm = TRUE),
            100 * max(abs(d), na.rm = TRUE) / mean(mu, na.rm = TRUE)))
cat(sprintf("  有无异常跳变（|d| > 5%% 均值）: %s\n",
            ifelse(any(abs(d) > 0.05 * mean(mu, na.rm = TRUE), na.rm = TRUE), "有", "无")))

cat("\n=== 唯一性：25 年是否互不相同 ===\n")
cat(sprintf("  均值唯一值个数     : %d / %d\n", length(unique(round(mu, 6))), length(years)))
cat(sprintf("  标准差唯一值个数   : %d / %d\n", length(unique(round(sd_, 6))), length(years)))
if (length(unique(round(mu, 6))) < length(years))
  cat("  ⚠ 有年份均值相同，需检查是否存在重复文件\n")

cat("\n=== 单调性（人类压力总体上应上升）===\n")
cat(sprintf("  首年 %.4f -> 末年 %.4f  变化 %+.4f\n", mu[1], mu[length(mu)],
            mu[length(mu)] - mu[1]))
cat(sprintf("  单调递增: %s\n", all(diff(mu) >= -1e-6)))
