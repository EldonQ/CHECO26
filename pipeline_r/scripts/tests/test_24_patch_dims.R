# R/tests/test_24_patch_dims.R -- 判定 terra::patches 的限制是"行数"还是"总像元数"
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

p <- file.path(PATH_COV(), "glo/lulc/glu1km/2020/urban/glo_lulc_glu1km_2020_urban_prop.tif")
r <- terra::rast(p)
v <- terra::values(r, mat = FALSE); nd <- terra::NAflag(r)
if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
terra::values(r) <- v
crop_cells <- function(x, r0, c0, nrow_, ncol_) {
  x0 <- terra::xFromCol(x, c0)
  x1 <- if (c0 + ncol_ > ncol(x)) terra::xmax(x) else terra::xFromCol(x, c0 + ncol_)
  y1 <- terra::yFromRow(x, r0)
  y0 <- if (r0 + nrow_ > nrow(x)) terra::ymin(x) else terra::yFromRow(x, r0 + nrow_)
  terra::crop(x, terra::ext(x0, x1, y0, y1), snap = "out")
}
binarize <- function(sub) {
  vv <- terra::values(sub, mat = FALSE)
  vv <- ifelse(is.na(vv), 0L, as.integer(vv > 0.5))
  terra::values(sub) <- vv; sub
}

cases <- list(
  list(nr = 300, nc = 4861),   # 146 万像元，仅 300 行
  list(nr = 550, nc = 4861),   # 267 万像元，550 行
  list(nr = 600, nc = 2000),   # 120 万像元，600 行
  list(nr = 700, nc = 700)     #  49 万像元，700 行
)
for (cs in cases) {
  sub <- binarize(crop_cells(r, 2000, 1, cs$nr, cs$nc))
  cat(sprintf("\n%d 行 x %d 列 = %s 像元 (斑块像元 %d)\n", cs$nr, cs$nc,
              format(cs$nr * cs$nc, big.mark = ","),
              as.integer(terra::global(sub, "sum", na.rm = TRUE)[1, 1])))
  t0 <- Sys.time()
  tryCatch({
    lab <- terra::patches(sub, directions = 4, values = TRUE)
    nm <- as.integer(terra::global(lab, "max", na.rm = TRUE)[1, 1])
    cat(sprintf("  OK maxid=%d %.2fs\n", nm,
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }, error = function(e) cat("  ERR:", conditionMessage(e), "\n"))
}
