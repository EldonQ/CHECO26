# R/tests/test_44_hlu.R -- hlu1km 单组合验证 + 波段号 + 历史段一致性
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
OUT <- "E:/CHECO26/N-SDM/scratch/r_hlu_test"
Sys.setenv(CHECO_OUT_ROOT = OUT)
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/07_derive_lulc_hlu1km.R", envir = .ing)

cat("=== 源属性与波段描述 ===\n")
src <- .ing$hlu_file("SSP1_RCP26")
cat(sprintf("  文件: %s\n", basename(src)))
r <- terra::rast(src)
cat(sprintf("  %d 波段 | %d x %d | res %.4f | crs %s\n",
            terra::nlyr(r), ncol(r), nrow(r), terra::res(r)[1], terra::crs(r, proj = TRUE)))
cat(sprintf("  数据类型: %s | NAflag: %s\n", terra::datatype(r), as.character(terra::NAflag(r))))

# 波段描述 = 年份字符串；抽查
desc <- tryCatch(terra::describe(src, print = FALSE), error = function(e) character())
bd <- grep("Band [0-9]+ Block|Description", desc, value = TRUE)
cat(sprintf("  描述行数: %d；前 6 条:\n", length(bd)))
for (s in head(bd, 6)) cat("   ", trimws(substr(s, 1, 110)), "\n")

# 关键：验证 band 号 -> 年份
cat("\n=== 波段号映射验证（year - 1959）===\n")
nl <- terra::nlyr(r)
cat(sprintf("  总波段 %d（应为 141，对应 1960-2100）\n", nl))
for (y in c(1960L, 1990L, 2020L, 2100L)) {
  k <- .ing$hlu_band(y)
  b <- terra::rast(src)[[k]]
  v <- terra::values(b, mat = FALSE)
  cat(sprintf("  year %d -> band %3d : 值域 [%s, %s] 唯一值 %d\n",
              y, k,
              format(min(v, na.rm = TRUE)), format(max(v, na.rm = TRUE)),
              length(unique(v[!is.na(v)]))))
}

cat("\n=== 单组合 2020（历史）===\n")
t0 <- Sys.time()
res <- .ing$hlu_combo(2020L, NA_character_, overwrite = TRUE)
cat(sprintf("  %s : %d 层, %.0f 秒\n", res$status, res$n %||% 0L,
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
`%||%` <- function(a, b) if (is.null(a)) b else a

cnames <- .ing$hlu_cnames()
s <- 0
for (i in seq_along(cnames)) {
  p <- res$files[grepl(paste0("_", cnames[i], "_prop\\.tif$"), res$files)][1]
  if (is.na(p) || !file.exists(p)) { cat("  缺:", cnames[i], "\n"); next }
  v <- terra::values(read_clean(p), mat = FALSE)
  s <- s + ifelse(is.na(v), 0, v)
  vv <- v[!is.na(v)]
  cat(sprintf("  %-11s 均值 %.4f  最大 %.4f  非零 %.1f%%\n",
              cnames[i], mean(vv), max(vv), 100 * mean(vv > 0)))
}
any_na <- is.na(terra::values(read_clean(res$files[1]), mat = FALSE))
cat(sprintf("\n  组成恒等式：有效 %s ; sum 范围 [%.6f, %.6f] ; max|sum-1| %.3e\n",
            format(sum(!any_na), big.mark = ","),
            min(s[!any_na]), max(s[!any_na]), max(abs(s[!any_na] - 1))))
cat(sprintf("  |sum-1| <= 1e-5 : %.4f%%\n", 100 * mean(abs(s[!any_na] - 1) <= 1e-5)))
