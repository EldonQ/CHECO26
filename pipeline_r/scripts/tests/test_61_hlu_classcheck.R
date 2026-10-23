# R/tests/test_61_hlu_classcheck.R
# 决定性核查：交付层的每个类别占中国面积的比例，是否等于源文件在**中国掩膜内**的对应比例
# 若不等，说明 07_derive_lulc_hlu1km.R 的类别映射有错
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

DIR <- file.path(PATH_ARCHIVE(), "harmonised", "Harmonised-1960-2100")
SRC <- file.path(DIR, "SSP1_RCP26_country-f.tif")
YEAR <- 2020L

LAB <- c(urban="Urban", cropland="Cropland", pasture="Pasture/rangeland",
         mngforest="Managed forest", forest="Unmanaged forest",
         grassshrub="Unmanaged grass/shrubland", sparse="Sparse/no vegetation",
         water="Water")

# ---- 1) 源：先按中国掩膜筛，再统计各类比例 ----
cat("读中国掩膜...\n")
mask <- terra::rast(file.path(PATH_DATA(), "mask_china.tif"))
cat("  掩膜:", terra::sources(mask), " 有效像元:", sum(terra::values(mask, mat=FALSE) > 0, na.rm=TRUE), "\n")

cat("读源 2020 波段并重投影到模板网格...\n")
src <- terra::rast(SRC)[[YEAR - 1959L]]
tmpl <- terra::rast(PATH_TEMPLATE())
src_al <- terra::project(src, tmpl, method = "near")
m <- terra::values(mask, mat = FALSE) > 0
v <- terra::values(src_al, mat = FALSE)
cat("  重投影后有值的像元:", sum(!is.na(v)), "\n")
cat("  在掩膜内的像元:", sum(m & !is.na(v)), " / 掩膜总数", sum(m), "\n")

# 用类别表把整数码翻成标签
lv <- terra::levels(src)
code2lab <- if (!is.null(lv)) setNames(lv[[1]]$Land_cover, lv[[1]]$id) else NULL
cat("  类别数:", length(code2lab), "\n\n")

src_frac <- sapply(names(LAB), function(k) {
  code <- names(code2lab)[code2lab == LAB[[k]]]
  mean(v[m & !is.na(v)] == as.numeric(code))
})

# ---- 2) 交付层：取同一网格上的均值 ----
cat("读交付层...\n")
del_frac <- sapply(names(LAB), function(k) {
  p <- layer_path(c("glo", "lulc", "hlu1km", as.character(YEAR), k), "_prop")
  if (!file.exists(p)) return(NA_real_)
  as.numeric(terra::global(terra::rast(p), "mean", na.rm = TRUE)[1, 1])
})

# ---- 3) 对比 ----
cmp <- data.frame(class = names(LAB),
                  source_china_pct = round(src_frac * 100, 4),
                  delivered_pct    = round(del_frac * 100, 4),
                  diff_pp          = round((del_frac - src_frac) * 100, 4),
                  row.names = NULL)
cat("=== 2020 年：源（中国掩膜内）vs 交付层 ===\n")
print(cmp)
cat(sprintf("\n源合计:      %.4f%%\n", sum(src_frac) * 100))
cat(sprintf("交付合计:    %.4f%%\n", sum(del_frac, na.rm = TRUE) * 100))
cat(sprintf("最大偏差:    %.4f 个百分点 (%s)\n",
            max(abs(cmp$diff_pp)), cmp$class[which.max(abs(cmp$diff_pp))]))
