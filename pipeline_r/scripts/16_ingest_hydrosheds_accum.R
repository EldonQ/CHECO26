# R/16_ingest_hydrosheds_accum.R -- rebuild the five HydroSHEDS accumulation layers in R
#
# Why this exists: those five layers came from an external Python script
# (E:/HydroSHEDS Core Data/work/step8_finalize.py), which is the last piece of the
# delivery not produced by the R pipeline. R/15_ingest_h90m_accumulation.R tried a
# different route -- rebuilding from Hydrography90m -- and was rejected on 2026-10-21
# because channel peaks came out 6.2x low. That rejection says nothing about this
# route: here the source is the same as_acc_3s.tif the delivered layers came from,
# so the job is to reproduce the transformation, not to replace the data.
#
# The transformation, as recorded in the provenance table:
#   1) warp as_acc_3s (3 arc-sec, UInt32, sentinel 4294967295) to the CHECO26 grid
#      with an average of the source cells;
#   2) mask to mask_china.tif (all_touched);
#   3) fill in-mask holes within 2 km by propagating the nearest valid value, which
#      is what gdal_fillnodata -md 2 does in the original;
#   4) write float32, nodata -9999, DEFLATE, 256x256 tiles;
#   5) four focal means (3x3, 11x11, 21x21, 41x41), denominator = valid cells.
#
# Output goes to scratch first. Nothing in the delivery is touched until the result
# has been compared cell by cell with the current layers.
#
# Usage:
#   Rscript R/16_ingest_hydrosheds_accum.R            # build into scratch
#   Rscript R/16_ingest_hydrosheds_accum.R check      # compare only

Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
suppressMessages(library(terra))

SRC  <- "E:/HydroSHEDS Core Data/work/00_src/as_acc_3s.tif"
OUT  <- file.path(PATH_SCRATCH(), "hydrosheds_accum_r")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
SENT <- 4294967295

layers <- function() {
  base <- file.path(PATH_COV(), "glo/hydro/hydrosheds/accumulation")
  c(file.path(base, "glo_hydro_hydrosheds_accumulation.tif"),
    file.path(base, sprintf("glo_hydro_hydrosheds_accumulation_f%d.tif", c(1000, 5000, 10000, 20000))))
}

build <- function() {
  tpl <- rast(PATH_TEMPLATE())
  cat(sprintf("模板 %d x %d\n", ncol(tpl), nrow(tpl)))

  r <- rast(SRC)
  cat(sprintf("源 %d x %d, %s, nodata %s\n", ncol(r), nrow(r),
              paste(datatype(r), collapse = ","), paste(NAflag(r), collapse = ",")))
  NAflag(r) <- SENT

  # China bbox with a margin, in source coordinates, before the expensive warp
  e <- ext(73, 136, 17, 55)
  r <- crop(r, e)
  cat(sprintf("裁剪后 %d x %d（%.1f%% 的原始像元）\n", ncol(r), nrow(r),
              100 * (ncol(r) * nrow(r)) / (156000 * 72000)))

  t0 <- Sys.time()
  w <- terra::project(r, tpl, method = "average", threads = TRUE)
  cat(sprintf("重投影(average): %.0f 秒\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))

  # sentinel must not enter the average; it is already NAflag, but guard anyway
  w <- ifel(w >= SENT - 1, NA, w)

  msk <- rast(PATH_MASK())
  w <- mask(w, msk, maskvalues = c(0, NA), updatevalue = NA)
  nv0 <- sum(!is.na(values(w, mat = FALSE)))
  cat(sprintf("掩膜后有效格 %s\n", format(nv0, big.mark = ",")))

  # Hole filling, matching gdal_fillnodata -md 2: an inverse-distance-squared
  # weighted average of the valid cells within two pixels. A plain 3x3 mean was
  # tried first and differed from the delivered layer by >10 % (relative) on 0.27 %
  # of cells, because it weights every neighbour equally regardless of distance.
  fw <- 5L
  ctr <- (fw + 1L) / 2
  offs <- expand.grid(dr = seq_len(fw), dc = seq_len(fw))
  d2 <- (offs$dr - ctr)^2 + (offs$dc - ctr)^2
  idw <- function(v) {
    ok <- !is.na(v) & d2 > 0
    if (!any(ok)) return(NA_real_)
    wt <- 1 / d2[ok]
    sum(v[ok] * wt) / sum(wt)
  }
  n_before <- sum(!is.na(values(w, mat = FALSE)))
  f <- focal(w, w = matrix(1, fw, fw), fun = idw, na.policy = "only")
  w <- ifel(is.na(w), f, w)
  n_after <- sum(!is.na(values(w, mat = FALSE)))
  cat(sprintf("  空洞 IDW 填充（≤2 km）：新增 %s 格\n", format(n_after - n_before, big.mark = ",")))
  w <- mask(w, msk, maskvalues = c(0, NA), updatevalue = NA)

  base_out <- file.path(OUT, "glo_hydro_hydrosheds_accumulation.tif")
  # writeRaster defaults to NaN as the missing value; the delivery convention is -9999
  NAflag(w) <- -9999
  writeRaster(w, base_out, overwrite = TRUE, datatype = "FLT4S", NAflag = -9999,
              gdal = c("COMPRESS=DEFLATE", "TILED=YES", "PREDICTOR=3"))
  v <- values(w, mat = FALSE)
  cat(sprintf("基底: 有效 %s；min %.6g 中位 %.6g max %.6g\n",
              format(sum(!is.na(v)), big.mark = ","),
              min(v, na.rm = TRUE), median(v, na.rm = TRUE), max(v, na.rm = TRUE)))

  for (rad in c(1L, 5L, 10L, 20L)) {
    k <- 2L * rad + 1L
    f <- focal(w, w = matrix(1, k, k), fun = "mean", na.rm = TRUE, na.policy = "all")
    f <- mask(f, msk, maskvalues = c(0, NA), updatevalue = NA)
    p <- file.path(OUT, sprintf("glo_hydro_hydrosheds_accumulation_f%d.tif", rad * 1000L))
    NAflag(f) <- -9999
    writeRaster(f, p, overwrite = TRUE, datatype = "FLT4S", NAflag = -9999,
                gdal = c("COMPRESS=DEFLATE", "TILED=YES", "PREDICTOR=3"))
    vf <- values(f, mat = FALSE)
    cat(sprintf("  焦点 %2d km: 有效 %s；max %.4g\n", rad,
                format(sum(!is.na(vf)), big.mark = ","), max(vf, na.rm = TRUE)))
    rm(f); gc(verbose = FALSE)
  }
  cat("输出:", OUT, "\n")
  invisible(OUT)
}

check <- function() {
  ref <- layers()
  new <- file.path(OUT, basename(ref))
  for (i in seq_along(ref)) {
    if (!file.exists(new[i])) { cat(sprintf("%-52s [未生成]\n", basename(ref[i]))); next }
    a <- values(rast(new[i]), mat = FALSE)
    b <- values(rast(ref[i]), mat = FALSE)
    ok <- !is.na(a) & !is.na(b)
    only_new <- sum(!is.na(a) & is.na(b)); only_old <- sum(is.na(a) & !is.na(b))
    d <- a[ok] - b[ok]
    cat(sprintf("%-52s 共用 %s | 新独有 %d | 旧独有 %d | 偏差 %+.3g | 平均|d| %.3g | max|d| %.3g\n",
                gsub("^glo_hydro_hydrosheds_accumulation", "base", sub("\\.tif$", "", basename(ref[i]))),
                format(sum(ok), big.mark = ","), only_new, only_old,
                mean(d), mean(abs(d)), max(abs(d))))
  }
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a) >= 1 && a[1] == "check") check() else { build(); check() }
}
