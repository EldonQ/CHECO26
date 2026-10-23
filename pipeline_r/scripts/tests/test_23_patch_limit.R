# R/tests/test_23_patch_limit.R -- 定位 terra::patches 的崩溃阈值
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

p <- file.path(PATH_COV(), "glo/lulc/glu1km/2020/urban/glo_lulc_glu1km_2020_urban_prop.tif")
r <- terra::rast(p)
v <- terra::values(r, mat = FALSE); nd <- terra::NAflag(r)
if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
terra::values(r) <- v
crop_cells <- function(x, r0, c0, n) {
  x0 <- terra::xFromCol(x, c0); x1 <- terra::xFromCol(x, c0 + n)
  y1 <- terra::yFromRow(x, r0); y0 <- terra::yFromRow(x, r0 + n)
  terra::crop(x, terra::ext(x0, x1, y0, y1), snap = "out")
}
binarize <- function(sub) {
  vv <- terra::values(sub, mat = FALSE)
  vv <- ifelse(is.na(vv), 0L, as.integer(vv > 0.5))
  terra::values(sub) <- vv; sub
}

for (n in c(350, 400, 450, 500, 550)) {
  sub <- binarize(crop_cells(r, 2000, 2500, n))
  t0 <- Sys.time()
  ok <- tryCatch({
    lab <- terra::patches(sub, directions = 4, values = TRUE)
    nm <- as.integer(terra::global(lab, "max", na.rm = TRUE)[1, 1])
    cat(sprintf("  n=%4d dir=4: OK  maxid=%d %.2fs\n", n, nm,
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    TRUE
  }, error = function(e) { cat(sprintf("  n=%4d dir=4: ERR %s\n", n, conditionMessage(e))); FALSE })
  if (!ok) break
}
