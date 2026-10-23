# R/tests/test_22_ccl.R -- 找可用的连通域标记实现
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

cat("terra 命名空间里与连通域相关的函数:\n")
print(grep("patch|clump|conn", ls(asNamespace("terra")), value = TRUE, ignore.case = TRUE))

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
binarize <- function(sub, minval = 0.5) {
  vv <- terra::values(sub, mat = FALSE)
  vv <- ifelse(is.na(vv), 0L, as.integer(vv > minval))
  terra::values(sub) <- vv
  sub
}

for (n in c(600, 1200)) {
  sub <- binarize(crop_cells(r, 2000, 2500, n))
  cat(sprintf("\n=== %d x %d (斑块像元 %d) ===\n", ncol(sub), nrow(sub),
              as.integer(terra::global(sub, "sum", na.rm = TRUE)[1, 1])))
  for (dirs in c(4, 8)) {
    t0 <- Sys.time()
    ok <- tryCatch({
      lab <- terra::patches(sub, directions = dirs, values = TRUE)
      nm <- as.integer(terra::global(lab, "max", na.rm = TRUE)[1, 1])
      cat(sprintf("  patches(dir=%d): 成功 最大id=%d %.2fs\n", dirs, nm,
                  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
      TRUE
    }, error = function(e) { cat(sprintf("  patches(dir=%d): 失败 %s\n", dirs, conditionMessage(e))); FALSE })
  }
  if (exists("clump", where = asNamespace("terra"))) {
    t0 <- Sys.time()
    tryCatch({
      lab <- terra::clump(sub, directions = 4)
      nm <- as.integer(terra::global(lab, "max", na.rm = TRUE)[1, 1])
      cat(sprintf("  clump(dir=4): 成功 最大id=%d %.2fs\n", nm,
                  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    }, error = function(e) cat("  clump: 失败", conditionMessage(e), "\n"))
  } else cat("  clump: 不存在\n")
}
