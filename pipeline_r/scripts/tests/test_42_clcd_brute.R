# R/tests/test_42_clcd_brute.R
# 直接检验：GDAL average 是否等于精确面积加权。不经 exactextract。
# 取 20x20 个 1km 像元，逐个从 30m 源暴力算精确比例，与 band_props 结果比对。
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd.R"), envir = .ing)

g <- GRID(); codes <- as.integer(names(.ing$CLCD_LEGEND))
cnames <- unname(.ing$CLCD_LEGEND)
r <- terra::rast(.ing$clcd_src(2020))
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0

R0 <- 1400L; NB <- 20L; C0 <- 3000L; NC <- 20L
cat(sprintf("=== 块 %d..%d x %d..%d (%dx%d 像元) ===\n", R0, R0 + NB - 1, C0, C0 + NC - 1, NB, NC))

t0 <- Sys.time()
p <- .ing$band_props(r, R0, NB, codes)
cat(sprintf("band_props 耗时 %.0f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))

# GDAL 结果
gdal <- lapply(seq_along(codes), function(i)
  matrix(terra::values(p[[i]], mat = FALSE), nrow(p), ncol(p), byrow = TRUE))

# ---- 一次性读取覆盖整块的 30m 源，做向量化精确面积加权 ----
rs <- terra::res(r)
x_lo <- g$xmin + (C0 - 1) * g$res; x_hi <- g$xmin + (C0 - 1 + NC) * g$res
y_hi <- g$ymax - (R0 - 1) * g$res; y_lo <- g$ymax - (R0 - 1 + NB) * g$res
blk_ext <- terra::ext(x_lo, x_hi, y_lo, y_hi)

# 输出像元的边界坐标
xb <- x_lo + (0:NC) * g$res     # 长度 NC+1
yb <- y_lo + (0:NB) * g$res

sw <- terra::crop(r, blk_ext + 2 * rs[1], snap = "out")
swm <- matrix(terra::values(sw, mat = FALSE), nrow(sw), ncol(sw), byrow = TRUE)
xof <- terra::xFromCol(sw, seq_len(ncol(sw)))
yof <- terra::yFromRow(sw, seq_len(nrow(sw)))
cat(sprintf("源窗口 %d x %d\n", nrow(swm), ncol(swm)))

exact <- array(NA_real_, dim = c(NB, NC, length(codes)))
for (i in seq_len(NB)) {
  for (j in seq_len(NC)) {
    # x 重叠
    xw <- pmax(0, pmin(xof + rs[1] / 2, xb[j + 1]) - pmax(xof - rs[1] / 2, xb[j]))
    yw <- pmax(0, pmin(yof + rs[2] / 2, yb[i + 1]) - pmax(yof - rs[2] / 2, yb[i]))
    if (sum(xw) == 0 || sum(yw) == 0) next
    W <- outer(yw, xw)
    okv <- !is.na(swm) & (swm %in% codes)
    den <- sum(W[okv])
    if (den == 0) next
    for (k in seq_along(codes))
      exact[i, j, k] <- sum(W[okv & swm == codes[k]]) / den
  }
}

cat("\n=== GDAL average vs 精确面积加权（20x20 = 400 像元）===\n")
for (k in seq_along(codes)) {
  a <- gdal[[k]][, C0:(C0 + NC - 1)]; b <- exact[, , k]
  ok <- !is.na(a) & !is.na(b)
  d <- abs(a[ok] - b[ok])
  cat(sprintf("  %-11s n=%4d  max|d| %.3e  mean|d| %.3e  >1e-6 的 %d\n",
              cnames[k], sum(ok), max(d), mean(d), sum(d > 1e-6)))
}
