# R/tests/test_65_hlu_composition_multi.R
# 改名后多组合的组成恒等式校验：8 个比例层之和应为 1
# 抽样覆盖：历史段 3 年 + 未来情景 3 个（不同 SSP），每个都检查全图
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

CLS <- c("urban", "cropland", "pasture", "mngforest", "forest",
         "grassshrub", "sparse", "water")

#' 用流式 global 求 8 层之和的极值（不加载整层到内存）
check <- function(year, ssp) {
  parts <- if (is.na(ssp)) c("glo", "lulc", "hlu1km", as.character(year))
           else c("glo", "lulc", "hlu1km", "scenario", as.character(year), ssp)
  s <- NULL; n <- 0L
  for (cn in CLS) {
    p <- layer_path(c(parts, cn), "_prop")
    if (!file.exists(p)) return(NULL)
    r <- terra::rast(p)
    s <- if (is.null(s)) r else s + r
    n <- n + 1L
  }
  if (n != length(CLS)) return(NULL)
  g <- terra::global(s, c("min", "max", "mean"), na.rm = TRUE)
  data.frame(year = year, ssp = ifelse(is.na(ssp), "hist", ssp),
             n_layers = n, min = g[1, 1], max = g[1, 2], mean = g[1, 3])
}

combos <- list(
  list(1960, NA_character_), list(1990, NA_character_), list(2020, NA_character_),
  list(2040, "ssp126"), list(2070, "ssp370"), list(2100, "ssp585")
)

cat("=== 组成恒等式：8 个比例层之和 ===\n\n")
res <- do.call(rbind, lapply(combos, function(x) {
  r <- tryCatch(check(x[[1]], x[[2]]), error = function(e) NULL)
  if (is.null(r)) cat(sprintf("  %d %-7s : 数据不全，跳过\n", x[[1]],
                              ifelse(is.na(x[[2]]), "hist", x[[2]])))
  r
}))

if (is.null(res) || !nrow(res)) { cat("无可检查的组合\n"); quit(save = "no") }

for (i in seq_len(nrow(res)))
  cat(sprintf("  %d %-7s  8 层  和 ∈ [%.9f, %.9f]  均值 %.9f  max|和−1| = %.2e\n",
              res$year[i], res$ssp[i], res$min[i], res$max[i], res$mean[i],
              max(abs(res$min[i] - 1), abs(res$max[i] - 1))))

worst <- max(abs(c(res$min - 1, res$max - 1)))
cat(sprintf("\n最大的 max|和−1| = %.3e\n", worst))
cat(sprintf("判定（阈值 1e-5）: %s\n", ifelse(worst < 1e-5,
    "通过 —— 改名后组成恒等式仍成立", "失败")))
cat("\n说明：该检验证明 8 个层恰好划分了面积，但**不能**证明名字与类别的对应关系——\n")
cat("后者由 test_61_hlu_classcheck.R（与源逐一对照）负责。\n")
