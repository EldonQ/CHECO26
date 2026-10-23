# R/tests/test_66_clcd_bench.R
# 把 band_props 的耗时按阶段拆开，找出真正的瓶颈
# 只跑 1 个带（25 行），约 90 秒
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/06_derive_lulc_clcd.R", envir = .ing)

YEAR <- 2010L
r0 <- 1000L          # 起始输出行
NR <- 25L            # 一个带
codes <- as.integer(names(.ing$CLCD_LEGEND))

tm <- function(expr) {
  t <- Sys.time(); v <- force(expr)
  list(v = v, s = as.numeric(difftime(Sys.time(), t, units = "secs")))
}

src <- .ing$clcd_src(YEAR)
cat(sprintf("源: %s\n", src))
r <- terra::rast(src)
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0
g <- GRID()

cat(sprintf("\n=== 单带耗时分解（year=%d, row0=%d, %d 行, %d 类）===\n\n",
            YEAR, r0, NR, length(codes)))

# 1) 读源窗口（含 2 格 margin）
margin <- 2L
y_top <- terra::yFromRow(g$rast, r0 - margin)
y_bot <- terra::yFromRow(g$rast, r0 + NR - 1L + margin)
# 换算到源的行列（源是 30 m，同一 Albers，只是原点偏移）
xmin <- g$xmin; xmax <- g$xmax
src_ext <- terra::ext(xmin, xmax, y_bot - 60, y_top + 60)

t1 <- tm({
  sub <- terra::crop(r, src_ext, snap = "out")
  v   <- terra::values(sub, mat = FALSE)
})
cat(sprintf("  1) 读源窗口        : %6.1f s   (%.1f M 像元)\n", t1$s, length(t1$v)/1e6))

t2 <- tm({
  s <- sub
  vv <- terra::values(s, mat = FALSE)
  vv[is.na(vv) | !(vv %in% codes)] <- NA
  terra::values(s) <- vv
})
cat(sprintf("  2) 清无效值        : %6.1f s\n", t2$s))

t3 <- tm({
  oh <- terra::segregate(s, classes = codes, keep = FALSE, other = 0)
})
cat(sprintf("  3) segregate %d 层  : %6.1f s\n", length(codes), t3$s))

tmp <- tempfile(fileext = ".tif")
t4 <- tm({
  terra::writeRaster(oh, tmp, overwrite = TRUE, datatype = "INT1U",
                     gdal = c("COMPRESS=DEFLATE", "TILED=YES", "BIGTIFF=IF_SAFER"))
})
sz <- file.size(tmp) / 1e6
cat(sprintf("  4) 写 INT1U 临时   : %6.1f s   (%.0f MB)\n", t4$s, sz))

t5 <- tm({
  ohh <- terra::rast(tmp)
  out <- terra::project(ohh, terra::crop(g$rast, terra::ext(xmin, xmax, y_bot, y_top)),
                        method = terra_method("average"), align = FALSE)
})
cat(sprintf("  5) project %d 层    : %6.1f s\n", length(codes), t5$s))

t6 <- tm({
  for (k in seq_along(codes)) {
    p <- tempfile(fileext = ".tif")
    terra::writeRaster(out[[k]], p, overwrite = TRUE, datatype = "FLT4S",
                       gdal = c("COMPRESS=DEFLATE", "TILED=YES"))
    unlink(p)
  }
})
cat(sprintf("  6) 写 %d 个输出     : %6.1f s\n", length(codes), t6$s))

tot <- t1$s + t2$s + t3$s + t4$s + t5$s + t6$s
cat(sprintf("\n  合计               : %6.1f s\n", tot))
cat("\n  === 占比 ===\n")
for (nm in c("读源", "清无效", "segregate", "写临时", "project", "写输出")) {
  v <- switch(nm, "读源"=t1$s, "清无效"=t2$s, "segregate"=t3$s,
              "写临时"=t4$s, "project"=t5$s, "写输出"=t6$s)
  cat(sprintf("    %-10s %5.1f %%\n", nm, 100*v/tot))
}

# 年化推算
nband <- ceiling(4062 / NR)
cat(sprintf("\n  === 年化推算 ===\n  每年 %d 带 × %.1f s = %.2f 小时/年/分片\n",
            nband, tot, nband*tot/3600))
cat(sprintf("  26 年 × 4 分片(各 6.5 年) = %.1f 小时墙钟\n", nband*tot*6.5/3600))

unlink(tmp)
