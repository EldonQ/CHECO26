# R/tests/test_45_clcd_smoke.R -- CLCD 全流程冒烟（100 行）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd.R"), envir = .ing)

cat("=== CLCD 2020 冒烟：前 100 行 ===\n")
t0 <- Sys.time()
r <- .ing$clcd_year_base(2020L, band_rows = 25L, overwrite = TRUE, max_rows = 100L)
cat(sprintf("结果: %s, %d 层, %.0f 秒\n", r$status, r$n,
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

s <- 0
for (f in r$files) {
  x <- terra::rast(f)
  v <- terra::values(x, mat = FALSE)
  s <- s + ifelse(is.na(v), 0, v)
  cat(sprintf("  %-44s %d x %d, 非NA %d, [%.4f, %.4f]\n", basename(f),
              ncol(x), nrow(x), sum(!is.na(v)),
              min(v, na.rm = TRUE), max(v, na.rm = TRUE)))
}
na0 <- is.na(terra::values(terra::rast(r$files[1]), mat = FALSE))
cat(sprintf("\n  组成恒等式: 有效 %d, sum 范围 [%.6f, %.6f], max|sum-1| %.3e\n",
            sum(!na0), min(s[!na0]), max(s[!na0]), max(abs(s[!na0] - 1))))
