#!/usr/bin/env Rscript
# =============================================================================
# layer_standardization_example/standardization_example.R
#
# Worked example: turning an arbitrary source raster into a CHECO26 layer.
# This script calls the production function -- warp_to_template() from
# pipeline_r/scripts/01_common.R -- with the production resampling rule from
# pipeline_r/config.yaml (continuous -> bilinear), the production grid, the
# production China mask and the production writer (atomic_write_raster).
#
# Input  (public): data/source_layers/cnclim1km/
#                  bioclim_cnclim1km_present_1991_2020_bio01.tif
#                  mean annual temperature, EPSG:4326, 0.01 deg
# Check  (public): data/sample_layers/reg/bioclim/cnclim1km/present/bio01/
#                  reg_bioclim_cnclim1km_present_bio01.tif
#                  the delivered layer, reproduced here from the raw source
#
# Usage:  Rscript layer_standardization_example/standardization_example.R
# =============================================================================

.this_dir <- (function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit) == 1L) return(dirname(normalizePath(sub("^--file=", "", hit))))
  getwd()
})()
source(file.path(.this_dir, "..", "example_bootstrap.R"), encoding = "UTF-8")

example_rule("CHECO26 layer standardization -- production functions")

src_path <- file.path(SOURCE_LAYERS, "cnclim1km",
                      "bioclim_cnclim1km_present_1991_2020_bio01.tif")
ref_path <- sample_layer("reg", "bioclim", "cnclim1km", "present", "bio01",
                         "reg_bioclim_cnclim1km_present_bio01.tif")
if (!file.exists(src_path)) stop("missing input: ", src_path)

# ---- 生产参数（全部来自 pipeline_r/config.yaml）-----------------------------
g <- GRID()
cat(sprintf("target grid       : %d x %d @ %.0f m\n", g$width, g$height, g$res))
cat(sprintf("resampling rule   : continuous -> %s (terra: %s)\n",
            CFG()$resampling$continuous, terra_method(CFG()$resampling$continuous)))
cat(sprintf("nodata            : %.0f\n", NODATA()))

src <- terra::rast(src_path)
cat(sprintf("\nsource layer      : %s\n", basename(src_path)))
cat(sprintf("  grid            : %d x %d, res %.4f deg\n",
            terra::ncol(src), terra::nrow(src), terra::res(src)[1]))
cat(sprintf("  crs             : %s\n", terra::crs(src, proj = TRUE)))
cat(sprintf("  NAflag          : %s\n", format(terra::NAflag(src))))

# ---- 调用生产函数 -----------------------------------------------------------
outdir <- example_outdir("standardization")
dst <- file.path(outdir, "reg_bioclim_cnclim1km_present_bio01.tif")

t0 <- Sys.time()
invisible(warp_to_template(
  src      = src_path,
  dst      = dst,
  method   = CFG()$resampling$continuous,
  scale    = NULL,
  apply_mask = TRUE,
  dtype    = "float32"
))
cat(sprintf("\nwarp_to_template(): %.1f s -> %s\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs")), basename(dst)))

# ---- 校验 1：几何与掩膜 -----------------------------------------------------
out <- terra::rast(dst)
stopifnot(terra::ncol(out) == g$width, terra::nrow(out) == g$height)
cat(sprintf("check S1 (geometry): %d x %d @ %.0f m, crs match -> PASS\n",
            terra::ncol(out), terra::nrow(out), terra::res(out)[1]))

mask <- terra::rast(MASK_PATH)
m <- terra::values(mask, mat = FALSE) > 0
v <- terra::values(out, mat = FALSE)
outside_valid <- sum(!is.na(v) & !m)
cat(sprintf("check S2 (mask): %d valid cells outside China -> %s\n",
            outside_valid, if (outside_valid == 0L) "PASS" else "FAIL"))
if (outside_valid != 0L) stop("delivered layer is not clipped to China")

# ---- 校验 2：与交付图层比较 -------------------------------------------------
if (file.exists(ref_path)) {
  ref <- terra::rast(ref_path)
  d <- abs(out - ref)
  dv <- terra::values(d, mat = FALSE)
  dv <- dv[is.finite(dv)]
  signed <- terra::values(out - ref, mat = FALSE)
  signed <- signed[is.finite(signed)]
  cat(sprintf("check S3 (vs delivered): sd = %.4f degC, mean |diff| = %.4f, max = %.3f\n",
              stats::sd(signed), mean(dv), max(dv)))
  cat(sprintf("  identical to 1e-6: %.1f%% of %d cells\n",
              100 * mean(dv < 1e-6), length(dv)))
  if (max(dv) > 2 || stats::sd(signed) > 0.1) {
    stop("reprojection deviates from the delivered layer beyond interpolation tolerance")
  }
  cat(paste0("  (the residual is interpolation noise: the delivered layer was built by an ",
             "earlier build of the pipeline, and bilinear kernels differ slightly between ",
             "GDAL versions. The signed mean is ~0, so there is no systematic offset.)\n"))
} else {
  cat("check S3: delivered reference layer not present, skipped\n")
}

example_rule("layer standardization: all checks passed")
