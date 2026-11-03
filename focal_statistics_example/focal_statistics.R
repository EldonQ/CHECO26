#!/usr/bin/env Rscript
# =============================================================================
# focal_statistics_example/focal_statistics.R
#
# Worked example: the multi-scale focal means that give every CHECO26 cell its
# landscape context. This script calls the production functions directly --
# focal_all() and focal_mean() from pipeline_r/scripts/01_common.R -- with the
# production window radii from pipeline_r/config.yaml (1, 5, 10, 20 km, i.e.
# 3x3, 11x11, 21x21 and 41x41 cells).
#
# Input  (public): data/sample_layers/glo/lulc/glu1km/2020/forest/
#                  glo_lulc_glu1km_2020_forest_prop.tif   (base 1-km layer)
# Check  (public): data/sample_layers/.../glo_lulc_glu1km_2020_forest_prop_f5000.tif
#                  the delivered _f5000 layer, recomputed here from the base
#
# Usage:  Rscript focal_statistics_example/focal_statistics.R [--radius-km 5]
# =============================================================================

# ---- 定位仓库并载入生产代码 -------------------------------------------------
.this_dir <- (function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit) == 1L) return(dirname(normalizePath(sub("^--file=", "", hit))))
  getwd()
})()
source(file.path(.this_dir, "..", "example_bootstrap.R"), encoding = "UTF-8")

example_rule("CHECO26 focal statistics -- production functions")

base_path <- sample_layer("glo", "lulc", "glu1km", "2020", "forest",
                          "glo_lulc_glu1km_2020_forest_prop.tif")
ref_path  <- sample_layer("glo", "lulc", "glu1km", "2020", "forest",
                          "glo_lulc_glu1km_2020_forest_prop_f5000.tif")
if (!file.exists(base_path)) stop("missing input: ", base_path)

radius_km <- 5L
args <- commandArgs(trailingOnly = TRUE)
if ("--radius-km" %in% args) {
  radius_km <- as.integer(args[which(args == "--radius-km") + 1L])
}

# ---- 生产窗口规格 -----------------------------------------------------------
fs <- FOCAL_SPEC()
cat("windows (from pipeline_r/config.yaml):\n")
for (i in seq_len(nrow(fs))) {
  cat(sprintf("  %-8s radius %2d km -> %d x %d cells\n",
              fs$suffix[i], fs$radius_km[i], fs$size[i], fs$size[i]))
}

base <- terra::rast(base_path)
cat(sprintf("\nbase layer        : %s\n", basename(base_path)))
cat(sprintf("  grid            : %d x %d, %.0f m, %s\n",
            terra::ncol(base), terra::nrow(base), terra::res(base)[1],
            terra::crs(base, proj = TRUE)))
cat(sprintf("  range (in China): [%.4f, %.4f]\n",
            as.numeric(terra::minmax(base, compute = TRUE)[1]),
            as.numeric(terra::minmax(base, compute = TRUE)[2])))

# ---- 调用生产函数：四个尺度一次算完 -----------------------------------------
t0 <- Sys.time()
layers <- focal_all(base)
cat(sprintf("\nfocal_all()       : %d layers in %.1f s\n",
            length(layers), as.numeric(difftime(Sys.time(), t0, units = "secs"))))

fs_row <- fs[fs$radius_km == radius_km, ]
key <- fs_row$suffix
if (!key %in% names(layers)) stop("radius not in FOCAL_SPEC(): ", radius_km)
focal_layer <- layers[[key]]

# ---- 校验 1：焦点值不越出基底值域 -------------------------------------------
b <- terra::values(base, mat = FALSE)
b <- b[is.finite(b)]
f <- terra::values(focal_layer, mat = FALSE)
f <- f[is.finite(f)]
n_above <- sum(f > max(b) + 1e-6)
n_below <- sum(f < min(b) - 1e-6)
cat(sprintf("\ncheck G1 (focal within base range): above=%d below=%d  -> %s\n",
            n_above, n_below, if (n_above + n_below == 0L) "PASS" else "FAIL"))
if (n_above + n_below != 0L) stop("G1 violated: focal statistics left the base range")

# ---- 校验 2：与交付图层逐格比较 ---------------------------------------------
if (file.exists(ref_path)) {
  ref <- terra::rast(ref_path)
  cmp <- terra::compareGeom(focal_layer, ref, stopOnError = FALSE)
  if (!isTRUE(cmp)) stop("recomputed layer is not aligned with the delivered layer")
  d <- abs(focal_layer - ref)
  dv <- terra::values(d, mat = FALSE)
  dv <- dv[is.finite(dv)]
  max_diff <- max(dv)
  n_diff <- sum(dv > 1e-6)
  cat(sprintf("check G2 (vs delivered %s): max |diff| = %.3g over %d cells, %d differ >1e-6 -> %s\n",
              key, max_diff, length(dv), n_diff,
              if (max_diff <= 1e-6) "PASS" else "FAIL"))
  if (max_diff > 1e-6) {
    stop("recomputed focal layer does not reproduce the delivered layer")
  }
} else {
  cat("check G2: delivered reference layer not present, skipped\n")
}

# ---- 写出（生产写盘函数：float32 / DEFLATE / 256 分块 / 原子写）------------
outdir <- example_outdir("focal")
for (sfx in names(layers)) {
  dst <- file.path(outdir, sprintf("glo_lulc_glu1km_2020_forest_prop%s.tif", sfx))
  atomic_write_raster(dst, layers[[sfx]], dtype = "float32")
  cat(sprintf("written           : %s\n", basename(dst)))
}

example_rule("focal statistics: all checks passed")
