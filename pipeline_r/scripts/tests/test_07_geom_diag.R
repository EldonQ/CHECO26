# R/tests/test_07_geom_diag.R -- 检查 terra::project 输出的几何是否与模板严格一致
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/00_config.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/01_common.R"), encoding = "UTF-8")

g <- GRID()
diag <- file.path(PATH_SCRATCH(), "diag_warp")
show <- function(p, lab) {
  if (!file.exists(p)) { cat(sprintf("  %-16s 缺\n", lab)); return(invisible()) }
  r <- terra::rast(p)
  cat(sprintf("  %-16s dim %d x %d | res %s | ext %s\n", lab,
              ncol(r), nrow(r),
              paste(terra::res(r), collapse = ","),
              paste(as.vector(terra::ext(r)), collapse = ", ")))
}
cat("=== 几何比对 ===\n")
cat(sprintf("  %-16s dim %d x %d | res %s | ext %s\n", "模板(GRID)",
            g$width, g$height, paste(c(g$res, g$res), collapse = ","),
            paste(c(g$xmin, g$xmax, g$ymin, g$ymax), collapse = ", ")))
show(file.path(PATH_TEMPLATE()), "template 文件")
show(file.path(diag, "r_bio01_nearest.tif"), "R nearest")
show(file.path(diag, "py_bio01_nearest.tif"), "Python nearest")

cat("\n=== 逐项比对 R 输出 vs 模板 ===\n")
r <- terra::rast(file.path(diag, "r_bio01_nearest.tif"))
cat(sprintf("  dim  相同: %s\n", ncol(r) == g$width && nrow(r) == g$height))
cat(sprintf("  res  相同: %s  (R %s)\n",
            isTRUE(all.equal(terra::res(r), c(g$res, g$res))),
            paste(terra::res(r), collapse = ",")))
cat(sprintf("  ext  相同: %s\n",
            isTRUE(all.equal(as.vector(terra::ext(r)), c(g$xmin, g$xmax, g$ymin, g$ymax)))))
cat(sprintf("  R ext   : %s\n", paste(sprintf("%.4f", as.vector(terra::ext(r))), collapse = ", ")))
cat(sprintf("  模板 ext: %s\n", paste(sprintf("%.4f", c(g$xmin, g$xmax, g$ymin, g$ymax)), collapse = ", ")))

cat("\n=== terra::project 的不同写法对照 ===\n")
src <- file.path(P("bioclim"), "cnclim1km/present/1991_2020/bio01",
                 "bioclim_cnclim1km_present_1991_2020_bio01.tif")
s <- terra::rast(src)
# 写法1：直接投影到模板 SpatRaster（当前实现）
p1 <- terra::project(s, g$rast, method = "near", align = FALSE)
cat(sprintf("  project(x, tmpl, align=FALSE): dim %d x %d  ext %s\n",
            ncol(p1), nrow(p1), paste(sprintf("%.1f", as.vector(terra::ext(p1))), collapse = ", ")))
# 写法2：align=TRUE
p2 <- terra::project(s, g$rast, method = "near", align = TRUE)
cat(sprintf("  project(x, tmpl, align=TRUE) : dim %d x %d  ext %s\n",
            ncol(p2), nrow(p2), paste(sprintf("%.1f", as.vector(terra::ext(p2))), collapse = ", ")))
# 写法3：只给 CRS，再显式给 extent/res
p3 <- terra::project(s, terra::crs(g$rast), method = "near",
                     res = g$res, extent = terra::ext(g$rast))
cat(sprintf("  project(x, crs, res, extent): dim %d x %d  ext %s\n",
            ncol(p3), nrow(p3), paste(sprintf("%.1f", as.vector(terra::ext(p3))), collapse = ", ")))
