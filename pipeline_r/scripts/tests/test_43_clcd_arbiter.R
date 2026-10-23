# R/tests/test_43_clcd_arbiter.R
# 用 exactextractr 对「单像元」仲裁：GDAL average、暴力面积加权、exactextractr 三者谁一致
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
suppressPackageStartupMessages({ library(sf); library(exactextractr) })

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd.R"), envir = .ing)

g <- GRID(); codes <- as.integer(names(.ing$CLCD_LEGEND))
cnames <- unname(.ing$CLCD_LEGEND)
r <- terra::rast(.ing$clcd_src(2020))
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0
rs <- terra::res(r)

R0 <- 1400L; NB <- 20L; C0 <- 3000L; NC <- 20L
p <- .ing$band_props(r, R0, NB, codes)
gdal <- lapply(seq_along(codes), function(i)
  matrix(terra::values(p[[i]], mat = FALSE), nrow(p), ncol(p), byrow = TRUE)[, C0:(C0 + NC - 1)])

# 覆盖整块的源（一次性读，用于暴力与 exactextract）
x_lo <- g$xmin + (C0 - 1) * g$res; x_hi <- g$xmin + (C0 - 1 + NC) * g$res
y_hi <- g$ymax - (R0 - 1) * g$res; y_lo <- g$ymax - (R0 - 1 + NB) * g$res
blk_ext <- terra::ext(x_lo, x_hi, y_lo, y_hi)
sw <- terra::crop(r, blk_ext + 2 * rs[1], snap = "out")
swm <- matrix(terra::values(sw, mat = FALSE), nrow(sw), ncol(sw), byrow = TRUE)
swm[!(swm %in% codes)] <- NA
xof <- terra::xFromCol(sw, seq_len(ncol(sw))); yof <- terra::yFromRow(sw, seq_len(nrow(sw)))
xb <- x_lo + (0:NC) * g$res; yb <- y_lo + (0:NB) * g$res

brute <- function(i, j, k) {
  xw <- pmax(0, pmin(xof + rs[1]/2, xb[j+1]) - pmax(xof - rs[1]/2, xb[j]))
  yw <- pmax(0, pmin(yof + rs[2]/2, yb[i+1]) - pmax(yof - rs[2]/2, yb[i]))
  W <- outer(yw, xw); okv <- !is.na(swm)
  den <- sum(W[okv]); if (den == 0) return(NA_real_)
  sum(W[okv & swm == codes[k]]) / den
}

# 取 cropland 差异最大的像元
dmax <- 0; bi <- 1; bj <- 1
for (i in 1:NB) for (j in 1:NC) {
  b <- brute(i, j, 1L)
  if (!is.na(b) && !is.na(gdal[[1]][i, j])) {
    dd <- abs(gdal[[1]][i, j] - b)
    if (dd > dmax) { dmax <- dd; bi <- i; bj <- j }
  }
}
cat(sprintf("cropland 最大差异像元: 块内 (%d, %d) -> 全局 row=%d col=%d, |GDAL-brute|=%.4f\n\n",
            bi, bj, R0 + bi - 1, C0 + bj - 1, dmax))

# 该像元的多边形（显式构造，避免空值栅格问题）
xc <- x_lo + (bj - 0.5) * g$res; yc <- y_lo + (NB - bi + 0.5) * g$res
poly1 <- sf::st_sfc(sf::st_polygon(list(matrix(
  c(xc - 500, yc - 500, xc + 500, yc - 500, xc + 500, yc + 500, xc - 500, yc + 500, xc - 500, yc - 500),
  ncol = 2, byrow = TRUE))), crs = 32650)
sf1 <- sf::st_sf(id = 1, geometry = poly1)
# 用模板的 CRS
sf::st_crs(sf1) <- terra::crs(g$rast)

cat(sprintf("%-12s %12s %12s %14s\n", "类", "GDAL", "暴力面积加权", "exactextractr"))
for (k in seq_along(codes)) {
  ind <- terra::ifel(sw == codes[k], 1L, 0L)
  ex <- exactextractr::exact_extract(ind, sf1, fun = "mean", progress = FALSE)[1]
  cat(sprintf("%-12s %12.6f %12.6f %14.6f\n",
              cnames[k], gdal[[k]][bi, bj], brute(bi, bj, k), ex))
}
