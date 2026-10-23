# R/tests/test_02_crs.R -- 判定 config 的 WKT 与模板 CRS 是否语义等价
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/00_config.R", encoding = "UTF-8")

tpl <- terra::rast(PATH_TEMPLATE())
g <- GRID()

cat("=== proj4 字符串比对 ===\n")
p_tpl <- terra::crs(tpl, proj = TRUE)
p_cfg <- terra::crs(g$rast, proj = TRUE)
cat("  template:", p_tpl, "\n")
cat("  config  :", p_cfg, "\n")
cat("  相同    :", identical(p_tpl, p_cfg), "\n\n")

cat("=== WKT 原文 ===\n")
cat("  template:\n", terra::crs(tpl), "\n\n")
cat("  config:\n", terra::crs(g$rast), "\n\n")

cat("=== 用同一几何建模板后，proj4 是否与模板一致 ===\n")
t2 <- terra::rast(xmin = g$xmin, xmax = g$xmax, ymin = g$ymin, ymax = g$ymax,
                  resolution = g$res, crs = p_tpl)
cat("  proj4 相同:", identical(terra::crs(t2, proj = TRUE), p_tpl), "\n")
cat("  ext  相同:", isTRUE(all.equal(as.vector(terra::ext(t2)),
                                      as.vector(terra::ext(tpl)))), "\n")
