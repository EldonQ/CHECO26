# R/tests/test_41_clcd_worst.R -- 找差异最大的像元，暴力核算判定谁对
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
suppressPackageStartupMessages({ library(sf); library(exactextractr) })

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd.R"), envir = .ing)

g <- GRID(); codes <- as.integer(names(.ing$CLCD_LEGEND))
cnames <- unname(.ing$CLCD_LEGEND)
r <- terra::rast(.ing$clcd_src(2020))
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0

R0 <- 1400L; NB <- 80L
p <- .ing$band_props(r, R0, NB, codes)

# 构造 80x80 的多边形（用有值的模板栅格，避免空模板的 as.polygons 异常）
sub <- .ing$band_template(R0, NB)
x0 <- terra::xFromCol(sub, 3000); x1 <- terra::xFromCol(sub, 3080)
y1 <- terra::yFromRow(sub, 1);    y0 <- terra::yFromRow(sub, 81)
blk <- terra::crop(sub, terra::ext(x0, x1, y0, y1))
terra::values(blk) <- 1L                              # 关键：给值，否则 as.polygons 会丢格
polys <- terra::as.polygons(blk, dissolve = FALSE, na.rm = FALSE)
sfp <- sf::st_as_sf(polys)
cat(sprintf("多边形数: %d（应为 6400）\n", nrow(sfp)))
sfp$id <- seq_len(nrow(sfp))

win <- terra::ext(sub) + 2 * g$res
crop_src <- terra::crop(r, win, snap = "out")
vv <- terra::values(crop_src, mat = FALSE); vv[is.na(vv) | !(vv %in% codes)] <- NA
terra::values(crop_src) <- vv

CI <- 1L   # cropland
ind <- terra::ifel(crop_src == codes[CI], 1L, 0L)
ref <- exactextractr::exact_extract(ind, sfp, fun = "mean", progress = FALSE)
got <- as.vector(t(matrix(terra::values(p[[CI]], mat = FALSE), nrow(p), ncol(p), byrow = TRUE)[1:80, 3000:3079]))
d <- abs(got - ref)
cat(sprintf("cropland: mean|d| %.4e, max|d| %.4e, >1e-6 的 %d\n\n", mean(d, na.rm = TRUE),
            max(d, na.rm = TRUE), sum(d > 1e-6, na.rm = TRUE)))

k <- which.max(replace(d, is.na(d), -1))
rr <- ((k - 1) %/% 80) + 1; cc <- ((k - 1) %% 80) + 1
cat(sprintf("最大差异像元: 块内 row=%d col=%d (全局 row=%d col=%d)\n", rr, cc, R0 + rr - 1, 3000 + cc - 1))
cat(sprintf("  GDAL actual = %.6f ; exactextractr = %.6f\n", got[k], ref[k]))

# ---- 暴力精确值 ----
ROW <- R0 + rr - 1; COL <- 3000 + cc - 1
xc <- g$xmin + (COL - 0.5) * g$res; yc <- g$ymax - (ROW - 0.5) * g$res
ce <- terra::ext(xc - g$res / 2, xc + g$res / 2, yc - g$res / 2, yc + g$res / 2)
rs <- terra::res(r)
sw <- terra::crop(r, ce + 2 * rs[1], snap = "out")
swm <- matrix(terra::values(sw, mat = FALSE), nrow(sw), ncol(sw), byrow = TRUE)
xof <- terra::xFromCol(sw, seq_len(ncol(sw))); yof <- terra::yFromRow(sw, seq_len(nrow(sw)))
xw <- pmax(0, pmin(xof + rs[1] / 2, ce[2]) - pmax(xof - rs[1] / 2, ce[1]))
yw <- pmax(0, pmin(yof + rs[2] / 2, ce[4]) - pmax(yof - rs[2] / 2, ce[3]))
W <- outer(yw, xw); okv <- !is.na(swm) & (swm %in% codes)
exact <- sum(W[okv & swm == codes[CI]]) / sum(W[okv])
cat(sprintf("  暴力精确面积加权 = %.6f\n", exact))
cat(sprintf("  有效覆盖面积 %.0f m2 (满 1e6)\n", sum(W[okv])))
cat(sprintf("\n  判定: |GDAL-exact| = %.3e ; |exactextract-exact| = %.3e\n",
            abs(got[k] - exact), abs(ref[k] - exact)))
