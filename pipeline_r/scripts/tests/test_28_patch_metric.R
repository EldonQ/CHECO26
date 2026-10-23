# R/tests/test_28_patch_metric.R
# 在 1000x1000 输出窗口上验证 patch_metric，与参照层同窗口对比（排除 r+5 边界）
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/05_derive_lulc.R", envir = .ing)

g <- GRID()
REF <- file.path(PATH_COV(), "glo/lulc/glu1km/2020")

# 用已有 prop 基底重建 binary：
#   all    = 中国境内（用 mask）
#   forest = forest_prop == 1
read_bin <- function(kind) {
  if (kind == "all") {
    m <- china_mask()
    r <- terra::rast(m)
    terra::values(r) <- as.integer(terra::values(m, mat = FALSE) == 1)
    r
  } else {
    r <- terra::rast(file.path(REF, "forest/glo_lulc_glu1km_2020_forest_prop.tif"))
    v <- terra::values(r, mat = FALSE); nd <- terra::NAflag(r)
    if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
    terra::values(r) <- ifelse(!is.na(v) & v > 0.5, 1L, 0L)
    r
  }
}

crop_cells <- function(x, r0, c0, nr_, nc_) {
  x0 <- terra::xFromCol(x, c0)
  x1 <- if (c0 + nc_ > ncol(x)) terra::xmax(x) else terra::xFromCol(x, c0 + nc_)
  y1 <- terra::yFromRow(x, r0)
  y0 <- if (r0 + nr_ > nrow(x)) terra::ymin(x) else terra::yFromRow(x, r0 + nr_)
  terra::crop(x, terra::ext(x0, x1, y0, y1), snap = "out")
}

# 造林窗口：秦岭-淮河一带，森林斑块结构丰富
R0 <- 1900; C0 <- 2400; N <- 1000

for (kind in c("all", "forest")) {
  cat(sprintf("\n=== scope=%s（%dx%d 窗口）===\n", kind, N, N))
  bin_full <- read_bin(kind)
  bin <- crop_cells(bin_full, R0, C0, N, N)
  vv <- terra::values(bin, mat = FALSE)
  cat(sprintf("  斑块像元 %s / %s (%.1f%%)\n",
              format(sum(vv == 1, na.rm = TRUE), big.mark = ","),
              format(length(vv), big.mark = ","), 100 * mean(vv == 1, na.rm = TRUE)))

  for (rr in c(5L, 20L)) {
    t0 <- Sys.time()
    pm <- .ing$patch_metric(bin, rr)
    el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    for (metric in c("patchdensity", "patchsize")) {
      ref_f <- file.path(REF, sprintf("glo_lulc_glu1km_2020_%s-%s_f%d.tif",
                                      metric, kind, rr * 1000))
      if (!file.exists(ref_f)) { cat(sprintf("    参照缺失: %s\n", basename(ref_f))); next }
      ref <- crop_cells(terra::rast(ref_f), R0, C0, N, N)
      rv <- terra::values(ref, mat = FALSE); nd <- terra::NAflag(ref)
      if (!is.na(nd)) rv[!is.na(rv) & rv == nd] <- NA
      got <- if (metric == "patchdensity") pm$density else pm$msize
      gv <- terra::values(got, mat = FALSE)

      # 排除距窗口边界 rr+5 像元的环带
      mg <- rr + 5L
      gi <- matrix(gv, N, N, byrow = TRUE); ri <- matrix(rv, N, N, byrow = TRUE)
      core <- matrix(TRUE, N, N); core[1:mg, ] <- FALSE; core[(N - mg + 1):N, ] <- FALSE
      core[, 1:mg] <- FALSE; core[, (N - mg + 1):N] <- FALSE
      ok <- core & !is.na(gi) & !is.na(ri)
      d <- abs(gi[ok] - ri[ok])
      span <- diff(range(ri[ok]))
      cat(sprintf("    r=%2dkm %-13s com %8s | mis %d | mean|d| %.3e | max|d| %.3e | max/span %.2e\n",
                  rr, metric, format(sum(ok), big.mark = ","),
                  sum(core & (is.na(gi) != is.na(ri))), mean(d), max(d), max(d) / span))
    }
    cat(sprintf("    （r=%dkm 计算耗时 %.1fs）\n", rr, el))
  }
}
