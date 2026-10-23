# R/tests/test_35_clcd.R -- CLCD 单带 / 单年验证
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
OUT <- file.path(Sys.getenv("CHECO_ROOT", getwd()), "scratch/r_clcd_test")
Sys.setenv(CHECO_OUT_ROOT = OUT)
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/tests/_helpers.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd.R"), envir = .ing)

g <- GRID(); codes <- as.integer(names(.ing$CLCD_LEGEND))
cnames <- unname(.ing$CLCD_LEGEND)
cat(sprintf("CLCD: %d 年 (%d-%d) x %d 类 x 5 = %d 层\n\n",
            length(.ing$CLCD_YEARS), min(.ing$CLCD_YEARS), max(.ing$CLCD_YEARS),
            length(codes), length(.ing$CLCD_YEARS) * length(codes) * 5))

src <- .ing$clcd_src(2020)
r <- terra::rast(src)

# ---- 1) 单行带正确性 ----
cat("=== 1) 单行带（10 行，第 1500 行起）===\n")
t0 <- Sys.time()
p <- .ing$band_props(r, 1500L, 10L, codes)
cat(sprintf("  输出: %d 层 %d x %d, 耗时 %.1fs\n", terra::nlyr(p), ncol(p), nrow(p),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

val <- terra::values(p, mat = FALSE)
m <- matrix(val, ncell(p), terra::nlyr(p))
s <- rowSums(m, na.rm = TRUE)
ok <- is.finite(s)
cat(sprintf("  像元 %d，其中 sum 有限 %d\n", length(s), sum(ok)))
cat(sprintf("  sum 范围 [%.6f, %.6f]；|sum-1|>1e-5 的 %d\n",
            min(s[ok]), max(s[ok]), sum(abs(s[ok] - 1) > 1e-5)))
cat(sprintf("  各类均值: %s\n",
            paste(sprintf("%s=%.4f", cnames, colMeans(m, na.rm = TRUE)), collapse = " ")))

# ---- 2) 与 exactextractr 面积加权独立比对 ----
cat("\n=== 2) 与 exactextractr 独立比对（抽样 60 列）===\n")
suppressPackageStartupMessages({ library(sf); library(exactextractr) })
sub <- .ing$band_template(1500L, 10L)
x0  <- terra::xFromCol(sub, 2400); x1 <- terra::xFromCol(sub, 2460)
y1  <- terra::yFromRow(sub, 1);    y0 <- terra::yFromRow(sub, 11)
polys <- terra::as.polygons(terra::crop(sub, terra::ext(x0, x1, y0, y1)), dissolve = FALSE)
sfp <- sf::st_as_sf(polys); sfp$id <- seq_len(nrow(sfp))

win <- terra::ext(sub) + 2 * g$res
crop_src <- terra::crop(r, win, snap = "out")
vv <- terra::values(crop_src, mat = FALSE); vv[is.na(vv) | !(vv %in% codes)] <- 0
terra::values(crop_src) <- vv

for (ci in c(1L, 2L, 5L, 8L)) {
  ind <- terra::ifel(crop_src == codes[ci], 1L, 0L)
  ref <- exactextractr::exact_extract(ind, sfp, fun = "mean", progress = FALSE)
  gm <- matrix(terra::values(p[[ci]], mat = FALSE), nrow(p), ncol(p), byrow = TRUE)
  got <- as.vector(t(gm[, 2400:2459]))
  d <- abs(got - ref)
  cat(sprintf("  %-11s n=%d  max|d| %.3e  mean|d| %.3e  >1e-6 的 %d\n",
              cnames[ci], length(d), max(d), mean(d), sum(d > 1e-6)))
}
