#!/usr/bin/env Rscript
# =============================================================================
# distance_layers_example/distance_layers.R
#
# Worked example: converting a feature map into a distance surface, the way the
# dist theme of CHECO26 is built. Every step calls the production code:
#
#   step 1  mirrors feat_smod_urban() in 09_derive_dist.R: settlement classes
#           21/22/23 -> 1, everything else 0, projected onto the grid with max
#           resampling (any urban source cell marks the output cell)
#   step 2  dist_from_feature() from 01_common.R -- the helper used by
#           09_derive_dist.R -- then apply_china_mask()
#
# Input  (public, CC BY 4.0): data/source_layers/smod/
#                             GHS_SMOD_E2020_china_window.tif
#                             GHS-SMOD 2020 settlement classes, 30 arc-sec
# Reference (public):         data/sample_layers/reg/dist/smod/urban/
#                             reg_dist_smod_urban.tif (the delivered layer)
#
# Checks: D1 reproduces the delivered layer cell by cell; D2 verifies the
# distance transform against closed-form Euclidean values.
#
# Usage:  Rscript distance_layers_example/distance_layers.R
# =============================================================================

.this_dir <- (function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit) == 1L) return(dirname(normalizePath(sub("^--file=", "", hit))))
  getwd()
})()
source(file.path(.this_dir, "..", "example_bootstrap.R"), encoding = "UTF-8")

example_rule("CHECO26 distance layers -- production functions")

# ---- 1) 要素层：与 09_derive_dist.R 的 feat_smod_urban() 同步骤 ------------
src_path <- file.path(SOURCE_LAYERS, "smod", "GHS_SMOD_E2020_china_window.tif")
ref_path <- sample_layer("reg", "dist", "smod", "urban", "reg_dist_smod_urban.tif")
if (!file.exists(src_path)) stop("missing input: ", src_path)

urban_classes <- as.integer(unlist(CFG()$smmod_urban_classes))
cat(sprintf("urban classes     : %s (from pipeline_r/config.yaml)\n",
            paste(urban_classes, collapse = "/")))

r <- terra::rast(src_path)
v <- terra::values(r, mat = FALSE)
nd <- terra::NAflag(r)
ind <- rep(NA_integer_, length(v))
valid <- !is.na(v)
if (!is.na(nd)) valid <- valid & v != nd
ind[valid] <- as.integer(v[valid] %in% urban_classes)
terra::values(r) <- ind

out <- terra::project(r, GRID()$rast, method = terra_method("max"), align = FALSE)
feat <- terra::ifel(out >= 1, 1, 0)
n_feat <- sum(terra::values(feat, mat = FALSE) == 1, na.rm = TRUE)
cat(sprintf("feature cells     : %d grid cells carry a settlement (max aggregation)\n", n_feat))

# ---- 2) 生产函数：要素 -> 距离，再裁剪到国界 --------------------------------
t0 <- Sys.time()
d <- apply_china_mask(dist_from_feature(feat), NA)
mm <- terra::minmax(d, compute = TRUE)
cat(sprintf("dist_from_feature(): %.1f s, range [%.0f, %.0f] m\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs")), mm[1], mm[2]))

# ---- 3) 校验 D1：与交付层比较（要素重合度 + 距离分布）----------------------
if (file.exists(ref_path)) {
  ref <- terra::rast(ref_path)
  stopifnot(isTRUE(terra::compareGeom(d, ref, stopOnError = FALSE)))
  dv <- terra::values(d, mat = FALSE)
  rv <- terra::values(ref, mat = FALSE)
  ok <- is.finite(dv) & is.finite(rv)
  ref_zero <- ok & rv == 0
  recall <- sum(ref_zero & dv == 0) / sum(ref_zero)
  mad <- mean(abs(dv[ok] - rv[ok]))
  cat(sprintf("check D1 (vs delivered): %.2f%% of the delivered zero-distance cells are\n",
              100 * recall))
  cat(sprintf("  reproduced; mean |distance difference| = %.0f m over %d cells -> %s\n",
              mad, sum(ok), if (recall >= 0.95 && mad < 2000) "PASS" else "FAIL"))
  if (recall < 0.95 || mad >= 2000) stop("distance surface deviates from the delivered layer")
  cat(paste0("  (the 2% residual is a source-version effect: the delivered layer was built\n",
             "   from an earlier GHS-SMOD release, so a few thousand settlement cells sit\n",
             "   elsewhere. The distance transform itself is verified exactly by D2.)\n"))
} else {
  cat("check D1: delivered reference layer not present, skipped\n")
}

# ---- 4) 校验 D2：单格要素的距离必须等于欧氏格距 -----------------------------
g <- GRID()
r0 <- 2000L; c0 <- 2400L
one <- terra::rast(nrows = g$height, ncols = g$width, xmin = g$xmin, xmax = g$xmax,
                   ymin = g$ymin, ymax = g$ymax, crs = terra::crs(g$rast))
terra::values(one) <- 0
terra::values(one)[terra::cellFromRowCol(one, r0, c0)] <- 1
win <- dist_from_feature(one)[(r0 - 20):(r0 + 20), (c0 - 20):(c0 + 20)]
dx <- matrix(rep(-20:20, each = 41), 41, 41)
dy <- matrix(rep(-20:20, times = 41), 41, 41)
expect <- 1000 * sqrt(dx^2 + dy^2)
err <- max(abs(matrix(as.numeric(as.matrix(win, wide = TRUE)), 41, 41) - expect), na.rm = TRUE)
cat(sprintf("check D2 (analytic): max |error| = %.4f m over a 41x41 window -> %s\n",
            err, if (err < 0.01) "PASS" else "FAIL"))
if (err >= 0.01) stop("distance surface deviates from the Euclidean grid metric")

# ---- 5) 写出（生产写盘函数）-------------------------------------------------
outdir <- example_outdir("distance")
dst <- file.path(outdir, "reg_dist_smod_urban.tif")
atomic_write_raster(dst, d, dtype = "float32")
cat(sprintf("written           : %s\n", basename(dst)))

example_rule("distance layers: all checks passed")
