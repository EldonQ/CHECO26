# R/tests/test_38_clcd_year.R -- 完整一年（2020）的 CLCD 基底比例 + 恒等式校验
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
OUT <- file.path(Sys.getenv("CHECO_ROOT", getwd()), "scratch/r_clcd_year")
Sys.setenv(CHECO_OUT_ROOT = OUT)
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/tests/_helpers.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd.R"), envir = .ing)

cnames <- unname(.ing$CLCD_LEGEND)
cat("=== 单年 2020，9 类基底比例 ===\n")
t0 <- Sys.time()
r <- .ing$clcd_year_base(2020L, band_rows = 40L, overwrite = TRUE)
el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("  %s : %d 层, %.0f 秒 (%.1f 分钟)\n", r$status, r$n %||% 0L, el, el / 60))
`%||%` <- function(a, b) if (is.null(a)) b else a

cat("\n=== 组成恒等式（九类比例之和 = 1）===\n")
arr <- array(NA_real_, dim = c(4062, 4861, length(cnames)))
for (i in seq_along(cnames)) {
  p <- r$files[grepl(paste0("_", cnames[i], "_prop\\.tif$"), r$files)][1]
  r0 <- read_clean(p)
  arr[, , i] <- terra::as.matrix(r0, wide = TRUE)
}
s <- apply(arr, c(1, 2), sum)
cat(sprintf("  有效像元 %s\n", format(sum(!is.na(s)), big.mark = ",")))
cat(sprintf("  全 NA 像元 %s\n", format(sum(is.na(s)), big.mark = ",")))
ok <- !is.na(s)
cat(sprintf("  sum 范围 [%.6f, %.6f]\n", min(s[ok]), max(s[ok])))
cat(sprintf("  |sum-1| <= 1e-5 : %s (%.4f%%)\n",
            format(sum(abs(s[ok] - 1) <= 1e-5), big.mark = ","),
            100 * mean(abs(s[ok] - 1) <= 1e-5)))
cat(sprintf("  |sum-1| <= 1e-3 : %.4f%%\n", 100 * mean(abs(s[ok] - 1) <= 1e-3)))
cat(sprintf("  max |sum-1|     : %.3e\n", max(abs(s[ok] - 1))))

cat("\n=== 各类覆盖 ===\n")
for (i in seq_along(cnames)) {
  v <- arr[, , i]; v <- v[!is.na(v)]
  cat(sprintf("  %-11s 均值 %.4f  最大 %.4f  非零占比 %.1f%%\n",
              cnames[i], mean(v), max(v), 100 * mean(v > 0)))
}
