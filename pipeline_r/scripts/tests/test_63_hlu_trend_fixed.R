# R/tests/test_63_hlu_trend_fixed.R
# 用**修正后**的类别名重算 harmonised 历史趋势，检验 B19 的结论是否仍成立
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

frac <- function(year, cls) {
  p <- layer_path(c("glo", "lulc", "hlu1km", as.character(year), cls), "_prop")
  if (!file.exists(p)) return(NA_real_)
  as.numeric(terra::global(terra::rast(p), "mean", na.rm = TRUE)[1, 1])
}

years <- c(1960, 1970, 1980, 1990, 2000, 2010, 2020)
classes <- c("forest", "mngforest", "urban", "cropland", "pasture", "sparse")

cat("=== 修正类别名后的 harmonised 历史趋势（中国区面积占比，%）===\n\n")
tab <- matrix(NA_real_, length(years), length(classes),
              dimnames = list(years, classes))
for (i in seq_along(years))
  for (j in seq_along(classes)) tab[i, j] <- frac(years[i], classes[j])

print(round(tab * 100, 3))

cat("\n=== 森林两类 ===\n")
tot <- tab[, "forest"] + tab[, "mngforest"]
for (i in seq_along(years))
  cat(sprintf("  %d  未经营林 %6.3f%%  经营林 %6.3f%%  合计 %6.3f%%\n",
              years[i], tab[i, "forest"]*100, tab[i, "mngforest"]*100, tot[i]*100))
cat(sprintf("\n  合计变化: %+.3f 个百分点（1960 -> 2020）\n", (tot[length(tot)]-tot[1])*100))
cat(sprintf("  未经营林变化: %+.3f 个百分点\n", (tab[length(years),"forest"]-tab[1,"forest"])*100))
cat(sprintf("  经营林变化:   %+.3f 个百分点\n", (tab[length(years),"mngforest"]-tab[1,"mngforest"])*100))
cat(sprintf("  合计单调递增: %s ; 单调递减: %s\n",
            all(diff(tot) >= -1e-6), all(diff(tot) <= 1e-6)))

cat("\n=== 城市 ===\n")
cat(sprintf("  %.3f%% (1960) -> %.3f%% (2020)  变化 %+.3f 个百分点  单调递增: %s\n",
            tab[1,"urban"]*100, tab[length(years),"urban"]*100,
            (tab[length(years),"urban"]-tab[1,"urban"])*100,
            all(diff(tab[, "urban"]) >= -1e-6)))
