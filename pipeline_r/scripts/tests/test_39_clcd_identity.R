# R/tests/test_39_clcd_identity.R -- 局部行带（300 行）验证 CLCD 组成恒等式与独立比对
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/tests/_helpers.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd.R"), envir = .ing)

g <- GRID(); codes <- as.integer(names(.ing$CLCD_LEGEND))
cnames <- unname(.ing$CLCD_LEGEND)
r <- terra::rast(.ing$clcd_src(2020))
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0

R0 <- 1400L; NB <- 300L; BR <- 25L
cat(sprintf("=== CLCD 2020：行 %d..%d（%d 行），按 %d 行分带 ===\n\n", R0, R0 + NB - 1, NB, BR))

t0 <- Sys.time()
acc <- lapply(seq_along(codes), function(i) matrix(NA_real_, NB, g$width))
rr <- R0
while (rr < R0 + NB) {
  nr <- min(BR, R0 + NB - rr)
  p <- .ing$band_props(r, rr, nr, codes)
  for (i in seq_along(codes)) {
    v <- terra::values(p[[i]], mat = FALSE)
    acc[[i]][(rr - R0 + 1L):(rr - R0 + nr), ] <- matrix(v, nr, g$width, byrow = TRUE)
  }
  rr <- rr + nr
}
el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("耗时 %.0f 秒（%d 行，%.1f s/千行）\n\n", el, NB, el / NB * 1000))

# ---- 组成恒等式 ----
s <- Reduce(`+`, acc)
ok <- !is.na(s)
cat("=== 组成恒等式（九类之和 = 1）===\n")
cat(sprintf("  像元 %s ; 有效 %s ; 全 NA %s\n",
            format(length(s), big.mark = ","), format(sum(ok), big.mark = ","),
            format(sum(!ok), big.mark = ",")))
cat(sprintf("  sum 范围 [%.6f, %.6f]\n", min(s[ok]), max(s[ok])))
cat(sprintf("  |sum-1| <= 1e-5 : %.4f%%\n", 100 * mean(abs(s[ok] - 1) <= 1e-5)))
cat(sprintf("  |sum-1| <= 1e-3 : %.4f%%\n", 100 * mean(abs(s[ok] - 1) <= 1e-3)))
cat(sprintf("  max |sum-1|     : %.3e\n", max(abs(s[ok] - 1))))

cat("\n=== 各类统计 ===\n")
for (i in seq_along(codes)) {
  v <- acc[[i]]; v <- v[!is.na(v)]
  cat(sprintf("  %-11s 均值 %.4f  最大 %.4f  非零 %.1f%%\n",
              cnames[i], mean(v), max(v), 100 * mean(v > 0)))
}

# ---- 与 exactextractr 独立比对（同窗口抽 80x80）----
cat("\n=== 与 exactextractr 面积加权独立比对 ===\n")
suppressPackageStartupMessages({ library(sf); library(exactextractr) })
sub <- .ing$band_template(R0, NB)
x0 <- terra::xFromCol(sub, 3000); x1 <- terra::xFromCol(sub, 3080)
y1 <- terra::yFromRow(sub, 1);    y0 <- terra::yFromRow(sub, 81)
polys <- terra::as.polygons(terra::crop(sub, terra::ext(x0, x1, y0, y1)), dissolve = FALSE)
sfp <- sf::st_as_sf(polys); sfp$id <- seq_len(nrow(sfp))
win <- terra::ext(sub) + 2 * g$res
crop_src <- terra::crop(r, win, snap = "out")
vv <- terra::values(crop_src, mat = FALSE); vv[is.na(vv) | !(vv %in% codes)] <- NA
terra::values(crop_src) <- vv
for (ci in c(1L, 2L, 5L, 8L)) {
  ind <- terra::ifel(crop_src == codes[ci], 1L, 0L)
  ref <- exactextractr::exact_extract(ind, sfp, fun = "mean", progress = FALSE)
  got <- as.vector(t(acc[[ci]][1:80, 3000:3079]))
  d <- abs(got - ref); d <- d[is.finite(d)]
  cat(sprintf("  %-11s n=%d  max|d| %.3e  mean|d| %.3e  >1e-6 的 %d\n",
              cnames[ci], length(d), max(d), mean(d), sum(d > 1e-6)))
}
