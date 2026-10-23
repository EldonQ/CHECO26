# R/tests/test_36_clcd_profile.R -- 分段计时，定位 CLCD 聚合的性能瓶颈
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

g <- GRID()
src <- file.path(PATH_ARCHIVE(), "clcd-albert", "CLCD_v01_2020_albert.tif")
r <- terra::rast(src)
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0
codes <- 1:9

tm <- function(expr) {
  t0 <- Sys.time(); v <- force(expr)
  as.numeric(difftime(Sys.time(), t0, units = "secs"))
}

for (nb in c(10L, 40L)) {
  cat(sprintf("\n=== 行带 %d 行 ===\n", nb))
  y1 <- g$ymax - 1500 * g$res
  y0 <- y1 - nb * g$res
  sub <- terra::rast(xmin = g$xmin, xmax = g$xmax, ymin = y0, ymax = y1,
                     resolution = g$res, crs = g$crs)

  e <- tm({ crop_src <- terra::crop(r, terra::ext(sub) + 2 * g$res, snap = "out") })
  npx <- terra::ncell(crop_src)
  cat(sprintf("  读取窗口: %d px (%.1f M)  %.1f s\n", npx, npx / 1e6, e))

  e <- tm({
    v <- terra::values(crop_src, mat = FALSE)
    v[is.na(v) | !(v %in% codes)] <- NA
    terra::values(crop_src) <- v
  })
  cat(sprintf("  向量化清理: %.1f s\n", e))

  e <- tm({ lay <- lapply(codes, function(c) terra::ifel(crop_src == c, 1L, 0L)) })
  cat(sprintf("  9 x ifel  : %.1f s\n", e))

  e <- tm({ onehot <- terra::rast(lay) })
  cat(sprintf("  组装 9 层 : %.1f s\n", e))

  e <- tm({ out <- terra::project(onehot, sub, method = "average", align = FALSE) })
  cat(sprintf("  project   : %.1f s  (%.2f M px/s)\n", e, npx / 1e6 / max(e, 1e-6)))

  e <- tm({ seg <- terra::segregate(crop_src, value = codes) })
  cat(sprintf("  segregate : %.1f s  (替代 9x ifel)\n", e))
  rm(lay, onehot, out, seg); gc(verbose = FALSE)
}
