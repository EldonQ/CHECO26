# R/tests/test_57_hlu_focal.R -- 验证 hlu1km 焦点路径（用已完成的组合）
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
# 不设 CHECO_OUT_ROOT：基底查找与焦点写入都走正式交付树
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/07_derive_lulc_hlu1km.R", envir = .ing)

# 找一个基底已存在的组合（1960 urban）
base <- .ing$hlu_parts(1960L, NA_character_, "urban")
bp <- layer_path(base, "_prop")
cat(sprintf("基底层: %s\n", basename(bp)))
if (!file.exists(bp)) { cat("  基底层不存在，无法测试\n"); quit(save = "no") }
st <- raster_stats(bp)
cat(sprintf("  基底值域 [%.4g, %.4g]，%s 个有效像元\n", st$min, st$max, format(st$n, big.mark = ",")))

cat("\n=== 跑 4 个焦点 ===\n")
t0 <- Sys.time()
r <- .ing$hlu_focal_one(1960L, NA_character_, "urban")
el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("  状态: %s，%d 层，%.0f 秒\n", r$status, r$n %||% 0L, el))
`%||%` <- function(a, b) if (is.null(a)) b else a

cat("\n=== 焦点不变量检查 ===\n")
FS <- FOCAL_SPEC()
lo <- st$min - 1e-4; hi <- st$max + 1e-4
for (k in seq_len(nrow(FS))) {
  fp <- layer_path(base, paste0("_prop", FS$suffix[k]))
  if (!file.exists(fp)) { cat(sprintf("  %-8s 缺\n", FS$suffix[k])); next }
  fr <- terra::rast(fp); fnd <- terra::NAflag(fr)
  fv <- terra::values(fr, mat = FALSE)
  if (!is.na(fnd)) fv[!is.na(fv) & abs(fv - fnd) < 1e-6] <- NA
  fv <- fv[!is.na(fv)]
  bad <- sum(fv < lo | fv > hi)
  cat(sprintf("  %-9s (size %2d): [%.4f, %.4f] 越界 %d %s\n", FS$suffix[k], FS$size[k],
              min(fv), max(fv), bad, ifelse(bad == 0, "OK", "FAIL")))
}
