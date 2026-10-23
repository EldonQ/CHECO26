# R/tests/test_59_gdal_threads.R
# 实测 GDAL_NUM_THREADS / GDAL_CACHEMAX 对 CLCD band_props 的影响
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/06_derive_lulc_clcd.R", envir = .ing)

r <- terra::rast(.ing$clcd_src(2020))
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0
codes <- as.integer(names(.ing$CLCD_LEGEND))

cat("=== 基线：当前设置 ===\n")
cat(sprintf("  GDAL_NUM_THREADS = %s\n",
            tryCatch(terra::getGDALconfig("GDAL_NUM_THREADS"), error = function(e) "(不可读)")))
cat(sprintf("  GDAL_CACHEMAX    = %s\n",
            tryCatch(terra::getGDALconfig("GDAL_CACHEMAX"), error = function(e) "(不可读)")))

tm <- function() {
  t0 <- Sys.time()
  p <- .ing$band_props(r, 1500L, 25L, codes, tag = "bench")
  as.numeric(difftime(Sys.time(), t0, units = "secs"))
}

cat("\n=== 单带计时（25 行，含读源 + segregate + 落盘 + project）===\n")
t_base <- tm(); cat(sprintf("  基线            : %6.1f s\n", t_base))

# 试 GDAL_NUM_THREADS
try_threads <- function(n) {
  ok <- tryCatch({
    terra::setGDALconfig("GDAL_NUM_THREADS", as.character(n)); TRUE
  }, error = function(e) { cat("  setGDALconfig 不可用:", conditionMessage(e), "\n"); FALSE })
  if (!ok) return(NA_real_)
  t <- tm()
  cat(sprintf("  NUM_THREADS=%-3d : %6.1f s  (%.2fx)\n", n, t, t_base / t))
  t
}

for (n in c(4L, 8L)) try_threads(n)

# 试 GDAL_CACHEMAX（加大对 project 的缓存）
ok <- tryCatch({ terra::setGDALconfig("GDAL_CACHEMAX", "1024"); TRUE },
               error = function(e) FALSE)
if (ok) {
  t <- tm(); cat(sprintf("  CACHEMAX=1024   : %6.1f s  (%.2fx)\n", t, t_base / t))
}

# 恢复
tryCatch({ terra::setGDALconfig("GDAL_NUM_THREADS", "1")
           terra::setGDALconfig("GDAL_CACHEMAX", "512") }, error = function(e) NULL)
cat("\n注：计时含系统 I/O 波动，差异 <15% 视为噪声。\n")
