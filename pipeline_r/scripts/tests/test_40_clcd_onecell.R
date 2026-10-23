# R/tests/test_40_clcd_onecell.R -- 单像元暴力核算：GDAL average vs 精确面积加权
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/06_derive_lulc_clcd.R", envir = .ing)

g <- GRID(); codes <- as.integer(names(.ing$CLCD_LEGEND))
cnames <- unname(.ing$CLCD_LEGEND)
src_path <- .ing$clcd_src(2020)
r <- terra::rast(src_path)
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0

# 取第 1400 行、第 3000 列那个 1km 像元（与上一测试同区）
ROW <- 1400L; COL <- 3000L
xc <- g$xmin + (COL - 0.5) * g$res
yc <- g$ymax - (ROW - 0.5) * g$res
cell_ext <- terra::ext(xc - g$res / 2, xc + g$res / 2, yc - g$res / 2, yc + g$res / 2)
cat(sprintf("1km 像元: row=%d col=%d  center=(%.0f, %.0f)\n", ROW, COL, xc, yc))
cat(sprintf("  范围 x[%.0f, %.0f] y[%.0f, %.0f]\n",
            cell_ext[1], cell_ext[2], cell_ext[3], cell_ext[4]))

# 源几何
rs <- terra::res(r); es <- terra::ext(r)
cat(sprintf("  源: res %.0f m, xmin %.0f ymax %.0f\n", rs[1], es[2], es[4]))

# 读窗口（外扩 2 个源像元）
win <- cell_ext + 2 * rs[1]
sw <- terra::crop(r, win, snap = "out")
vs <- terra::values(sw, mat = FALSE)
swm <- matrix(vs, nrow(sw), ncol(sw), byrow = TRUE)
xof <- terra::xFromCol(sw, seq_len(ncol(sw)))
yof <- terra::yFromRow(sw, seq_len(nrow(sw)))

# 每个源像元的 x/y 重叠宽度
xw <- pmax(0, pmin(xof + rs[1] / 2, cell_ext[2]) - pmax(xof - rs[1] / 2, cell_ext[1]))
yw <- pmax(0, pmin(yof + rs[2] / 2, cell_ext[4]) - pmax(yof - rs[2] / 2, cell_ext[3]))
W  <- outer(yw, xw)                      # 重叠面积矩阵
ok <- !is.na(swm) & (swm %in% codes)
den <- sum(W[ok])
cat(sprintf("  窗口 %d x %d ; 有效源像元 %d ; 有效重叠面积 %.1f m2 (满 = %.0f)\n",
            nrow(swm), ncol(swm), sum(ok), den, 1000 * 1000))

cat("\n=== 精确面积加权（暴力）===\n")
exact <- sapply(codes, function(c) sum(W[ok & swm == c]) / den)
# GDAL average 的近似：源像元中心落在 1km 像元内则整权计入
ctr_in <- outer(yof > cell_ext[3] & yof < cell_ext[4],
                xof > cell_ext[1] & xof < cell_ext[2]) & ok
gdal_like <- sapply(codes, function(c) {
  d <- sum(ctr_in)
  if (d == 0) NA_real_ else sum(swm[ctr_in] == c) / d
})
res <- data.frame(class = cnames, exact = round(exact, 5), gdal_center = round(gdal_like, 5))

# 真实 GDAL average 值
R0 <- 1390L; NB <- 25L
p <- .ing$band_props(r, R0, NB, codes)
row_in <- ROW - R0 + 1L
gdal <- vapply(seq_along(codes), function(i) {
  m <- matrix(terra::values(p[[i]], mat = FALSE), nrow(p), ncol(p), byrow = TRUE)
  m[row_in, COL]
}, 0)
res$gdal_actual <- round(gdal, 5)
res$diff_exact_vs_actual <- round(res$gdal_actual - res$exact, 5)
print(res, row.names = FALSE)

cat(sprintf("\n  exact 之和 = %.6f\n", sum(res$exact)))
cat(sprintf("  gdal_actual 之和 = %.6f\n", sum(res$gdal_actual)))
cat(sprintf("  有效重叠面积 / 满格 = %.4f\n", den / 1e6))
