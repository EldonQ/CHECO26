# R/tests/test_58_hlu_trend.R
# 生态合理性检验：hlu1km 历史段的城市/耕地比例趋势
# 中国区等面积网格上，比例层像元值的算术平均 = 该类占中国陆地面积的比例
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

get_frac <- function(year, cls) {
  p <- layer_path(c("glo", "lulc", "hlu1km", as.character(year), cls), "_prop")
  if (!file.exists(p)) return(NA_real_)
  r <- terra::rast(p); nd <- terra::NAflag(r)
  a <- terra::global(r, "mean", na.rm = TRUE)[1, 1]
  as.numeric(a)
}

years <- c(1960, 1970, 1980, 1990, 2000, 2010, 2020)
cls_list <- c("urban", "cropland", "pasture", "forest", "sparse")

cat("=== hlu1km 历史段趋势（中国区面积占比，等面积网格上的均值）===\n\n")
tab <- matrix(NA_real_, nrow = length(years), ncol = length(cls_list),
              dimnames = list(years, cls_list))
for (y in years) for (c in cls_list) tab[as.character(y), c] <- get_frac(y, c)
print(round(tab * 100, 3))

cat("\n=== 单调性检验 ===\n")
for (c in cls_list) {
  v <- tab[, c]
  if (all(is.na(v))) { cat(sprintf("  %-10s 数据不足\n", c)); next }
  dv <- diff(v[!is.na(v)])
  cat(sprintf("  %-10s 首 %.3f%% -> 末 %.3f%%  (%+.3f 个百分点)  单调递增: %s  单调递减: %s\n",
              c, v[1] * 100, v[length(v)] * 100, (v[length(v)] - v[1]) * 100,
              all(dv >= -1e-6), all(dv <= 1e-6)))
}

cat("\n=== 说明 ===\n")
cat("  urban 在 1960-2020 应持续上升（中国城镇化）；\n")
cat("  cropland 应有波动但总量大体稳定；\n")
cat("  pasture/forest/sparse 的变化取决于 HILDA+ 的重建，不强制单调。\n")
