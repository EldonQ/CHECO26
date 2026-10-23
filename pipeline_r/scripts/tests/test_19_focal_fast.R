# R/tests/test_19_focal_fast.R
# 验证可分离实现的 focal 均值与「完整卷积」版本逐像元等价，并测速。
# 原理：方形窗的 2D 盒滤波 = 行方向 1D 盒滤波 再 列方向 1D 盒滤波（O(k) 而非 O(k^2)）。
# 分母（有效像元数）同样可分离。
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

#' 可分离实现的等权焦点均值（与 focal_mean 语义一致）
focal_mean_fast <- function(x, radius_cells) {
  rc <- as.integer(radius_cells)
  size <- 2L * rc + 1L
  if (size == 1L) return(x)
  wh <- matrix(1, nrow = 1, ncol = size)   # 行方向
  wv <- matrix(1, nrow = size, ncol = 1)   # 列方向
  xv <- terra::ifel(is.na(x), 0, x)
  vv <- terra::ifel(is.na(x), 0, 1)
  s <- terra::focal(terra::focal(xv, wh, fun = "sum", na.policy = "all", na.rm = TRUE),
                    wv, fun = "sum", na.policy = "all", na.rm = TRUE)
  c <- terra::focal(terra::focal(vv, wh, fun = "sum", na.policy = "all", na.rm = TRUE),
                    wv, fun = "sum", na.policy = "all", na.rm = TRUE)
  out <- terra::ifel(c >= 0.5, s / c, NA)
  out
}

probe <- file.path(PATH_COV(),
  "glo/lulc/glu1km/2020/cropland/glo_lulc_glu1km_2020_cropland_prop.tif")
x <- terra::rast(probe)
nd <- terra::NAflag(x); v <- terra::values(x, mat = FALSE)
if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
v[is.nan(v)] <- NA
terra::values(x) <- v
cat(sprintf("测试层: %d x %d, 有效 %s\n\n", ncol(x), nrow(x),
            format(sum(!is.na(v)), big.mark = ",")))

for (rc in c(1L, 5L, 10L, 20L)) {
  t1 <- Sys.time(); a <- focal_mean(x, rc);      e1 <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
  t2 <- Sys.time(); b <- focal_mean_fast(x, rc); e2 <- as.numeric(difftime(Sys.time(), t2, units = "secs"))
  av <- terra::values(a, mat = FALSE); bv <- terra::values(b, mat = FALSE)
  ok <- !is.na(av) & !is.na(bv)
  d <- abs(av[ok] - bv[ok])
  cat(sprintf("r=%2dkm (size %2d): 卷积 %6.1fs | 可分离 %6.1fs | 加速 %4.1fx | 掩膜差异 %d | max|d| %.3e\n",
              rc, 2 * rc + 1, e1, e2, e1 / max(e2, 1e-6),
              sum(!is.na(av) & is.na(bv)) + sum(is.na(av) & !is.na(bv)), max(d)))
}
