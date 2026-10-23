# R/tests/test_34_naflag.R -- 最小复现：terra 写盘时 NAflag 如何落到文件头
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
out <- file.path(PATH_SCRATCH(), "naflag_test"); ensure_dir(out)

mk <- function() {
  m <- matrix(c(1, 2, NA, 4), 2, 2)
  terra::rast(m, extent = terra::ext(0, 2, 0, 2), crs = "EPSG:4326")
}

probe <- function(tag, expr, f) {
  ok <- tryCatch({force(expr); TRUE}, error = function(e) {cat("  ERR:", conditionMessage(e), "\n"); FALSE})
  if (!ok || !file.exists(f)) return(invisible())
  r <- terra::rast(f)
  v <- terra::values(r, mat = FALSE)
  cat(sprintf("  %-42s NAflag=%-10s datatype=%-6s 值=%s\n",
              tag, as.character(terra::NAflag(r)), terra::datatype(r),
              paste(format(v), collapse = ",")))
}

f1 <- file.path(out, "a.tif")
probe("1) 默认写（不设 NAflag）", {
  terra::writeRaster(mk(), f1, overwrite = TRUE, datatype = "FLT4S")
}, f1)

f2 <- file.path(out, "b.tif")
probe("2) NAflag(x)<- -9999 后写", {
  r <- mk(); terra::NAflag(r) <- -9999
  terra::writeRaster(r, f2, overwrite = TRUE, datatype = "FLT4S")
}, f2)

f3 <- file.path(out, "c.tif")
probe("3) ifel 替换后写 + NAflag 参数", {
  r <- mk(); r <- terra::ifel(is.na(r), -9999, r); terra::NAflag(r) <- -9999
  terra::writeRaster(r, f3, overwrite = TRUE, datatype = "FLT4S", NAflag = -9999)
}, f3)

f4 <- file.path(out, "d.tif")
probe("4) gdal 选项里写 -a_nodata", {
  r <- mk(); r <- terra::ifel(is.na(r), -9999, r)
  terra::writeRaster(r, f4, overwrite = TRUE, datatype = "FLT4S",
                     gdal = c("COMPRESS=DEFLATE", "-a_nodata", "-9999"))
}, f4)

f5 <- file.path(out, "e.tif")
probe("5) 当前 atomic_write_raster", {
  atomic_write_raster(f5, mk(), dtype = "float32")
}, f5)

cat("\n=== 用 GDAL 读文件头 nodata ===\n")
for (f in c(f1, f2, f3, f4, f5)) {
  if (!file.exists(f)) next
  d <- terra::describe(f, print = FALSE)
  nd <- grep("NoData|NODATA", d, value = TRUE, ignore.case = TRUE)
  cat(sprintf("  %-8s %s\n", basename(f), paste(trimws(nd), collapse = " | ")))
}
