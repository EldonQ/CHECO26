# R/tests/test_64_rename_pairing.R
# 验证改名后「基底层」与「焦点层」仍配对正确：
# 焦点层 X_prop_f1000 应当确实是 X_prop 的 3x3 均值
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

root <- file.path(PATH_COV(), "glo/lulc/hlu1km")
FS <- FOCAL_SPEC()

#' 抽一个基底，复算 3x3 焦点并与磁盘上的 f1000 比对
check_pair <- function(base_path) {
  f1 <- sub("_prop\\.tif$", "_prop_f1000.tif", base_path)
  if (!file.exists(f1)) return(NULL)
  b <- terra::rast(base_path)
  on_disk <- terra::rast(f1)
  # 用与生成流程相同的 focal_mean 复算
  mine <- tryCatch(focal_mean(b, 1), error = function(e) NULL)
  if (is.null(mine)) return(NULL)
  # 用 terra::global 做流式比较，避免大内存
  d <- mine - on_disk
  g <- terra::global(abs(d), c("max", "mean"), na.rm = TRUE)
  data.frame(base = basename(base_path), f1 = basename(f1),
             maxabs = g[1, 1], meanabs = g[1, 2])
}

# 抽 8 个基底（覆盖 8 个类，取最早的年份）
bases <- list.files(root, pattern = "_prop\\.tif$", recursive = TRUE, full.names = TRUE)
bases <- bases[grepl("/1960/", bases) | grepl("_1960_", bases)]
cat(sprintf("1960 年基底层: %d 个\n", length(bases)))
stopifnot(length(bases) > 0)

res <- do.call(rbind, lapply(bases, function(p) tryCatch(check_pair(p), error = function(e) NULL)))
if (is.null(res)) { cat("无可比对的对\n"); quit(save = "no") }

cat("\n=== 复算 3x3 焦点 vs 磁盘上的 _prop_f1000 ===\n")
for (i in seq_len(nrow(res)))
  cat(sprintf("  %-46s max|d| %.3e  mean|d| %.3e\n",
              sub("glo_lulc_hlu1km_1960_", "", res$base), res$maxabs, res$meanabs))
cat(sprintf("\n最大 max|d| = %.3e（应接近 0，float32 舍入量级）\n", max(res$maxabs)))
cat(sprintf("结论: %s\n", ifelse(max(res$maxabs) < 1e-6,
    "通过 —— 改名后基底与焦点仍配对正确", "失败 —— 配对错位")))
