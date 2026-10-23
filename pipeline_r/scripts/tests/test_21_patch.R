# R/tests/test_21_patch.R -- 隔离测试 patch_metric（小窗口），定位栈溢出
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/05_derive_lulc.R", envir = .ing)

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
  terra::values(sub) <- vv
  sub
}

for (n in c(100, 300, 600)) {
  cat(sprintf("\n=== 窗口 %d x %d ===\n", n, n))
  sub <- binarize(crop_cells(r, 2000, 2500, n))
  cat(sprintf("  尺寸 %d x %d ; 斑块像元 %d\n", ncol(sub), nrow(sub),
              as.integer(terra::global(sub, "sum", na.rm = TRUE)[1, 1])))
  t0 <- Sys.time()
  lab <- tryCatch(terra::patches(sub, directions = 4, values = TRUE),
                  error = function(e) { cat("  patches 失败:", conditionMessage(e), "\n"); NULL })
  if (is.null(lab)) next
  nmax <- as.integer(terra::global(lab, "max", na.rm = TRUE)[1, 1])
  cat(sprintf("  patches 成功: 最大 id=%d, 耗时 %.2fs\n", nmax,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

cat("\n=== 完整 patch_metric（300x300, r=5）===\n")
sub <- binarize(crop_cells(r, 2000, 2500, 300))
t0 <- Sys.time()
res <- tryCatch(.ing$patch_metric(sub, 5L),
                error = function(e) { cat("  失败:", conditionMessage(e), "\n"); NULL })
if (!is.null(res)) {
  cat(sprintf("  成功，耗时 %.2fs\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  dv <- terra::values(res$density, mat = FALSE); mv <- terra::values(res$msize, mat = FALSE)
  cat(sprintf("  density: [%.4f, %.4f] 有效 %d\n", min(dv, na.rm = TRUE), max(dv, na.rm = TRUE), sum(!is.na(dv))))
  cat(sprintf("  msize  : [%.4f, %.4f] 有效 %d\n", min(mv, na.rm = TRUE), max(mv, na.rm = TRUE), sum(!is.na(mv))))
}
