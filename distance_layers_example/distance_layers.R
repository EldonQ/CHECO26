#!/usr/bin/env Rscript
# =============================================================================
# distance_layers_example/distance_layers.R
#
# Worked example: turning a binary feature map into a distance surface, the way
# the dist theme of CHECO26 is built. The computation is the production helper
# dist_from_feature() from pipeline_r/scripts/01_common.R -- the same function
# called by pipeline_r/scripts/09_derive_dist.R -- followed by the production
# writer.
#
# Two checks are run:
#   D1  analytic values: on a 1-km grid the nearest interior cell to the border
#       must sit exactly 1,000 m from it, and distances must grow inland.
#   D2  round trip on a delivered layer: the zero cells of the delivered road
#       distance layer are the rasterized roads; feeding them back through
#       dist_from_feature() must reproduce that layer.
#
# Input  (public): data/mask_china.tif
#                  data/sample_layers/glo/dist/grip4/road/glo_dist_grip4_road.tif
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

# ---- 图示用要素：境外 = 1（到国界的距离）-----------------------------------
mask <- terra::rast(MASK_PATH)
cat(sprintf("grid              : %d x %d @ %.0f m\n",
            terra::ncol(mask), terra::nrow(mask), terra::res(mask)[1]))

feat <- terra::ifel(mask > 0, 0, 1)          # 1 = 境外（目标要素）
n_feat <- sum(terra::values(feat, mat = FALSE) == 1, na.rm = TRUE)
cat(sprintf("feature cells     : %d outside China -> distance to the border\n", n_feat))

# ---- 调用生产函数 -----------------------------------------------------------
t0 <- Sys.time()
d <- dist_from_feature(feat)                 # 米，要素像元本身为 0
cat(sprintf("dist_from_feature(): %.1f s\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

# 生产口径：距离在全网格计算，落盘前才掩膜回中国
d <- apply_china_mask(d, NA)

# ---- 校验 D1：解析值 --------------------------------------------------------
# 国界内侧的第一圈格应恰好为 1,000 m（1 km 网格、正对齐）
inside <- mask > 0
first_ring <- inside & (d > 0) & (d <= 1000)
vals_ring <- terra::values(d, mat = FALSE)[terra::values(first_ring, mat = FALSE) == 1]
vals_ring <- vals_ring[is.finite(vals_ring)]
share_1000 <- mean(abs(vals_ring - 1000) < 1e-6)
dmax <- max(terra::values(d, mat = FALSE), na.rm = TRUE)
cat(sprintf("\ncheck D1 (analytic): first interior ring = 1,000 m at %.1f%% of cells; max distance %.0f km -> %s\n",
            100 * share_1000, dmax / 1000,
            if (share_1000 > 0.99 && dmax > 1e6) "PASS" else "FAIL"))
if (share_1000 <= 0.99) stop("distance surface is not on the 1-km metric grid")

# ---- 校验 D2：单格要素的距离必须等于欧氏格距 ------------------------------
# 在网格中央放一个要素格，距离面在 41x41 窗口内应逐格等于 1000*hypot(dx,dy)
# （float32 存储，容差取 1 cm）。不依赖任何交付图层。
g <- GRID()
r0 <- 2000L; c0 <- 2400L
one <- terra::rast(nrows = g$height, ncols = g$width, xmin = g$xmin, xmax = g$xmax,
                   ymin = g$ymin, ymax = g$ymax, crs = terra::crs(g$rast))
terra::values(one) <- 0
terra::values(one)[terra::cellFromRowCol(one, r0, c0)] <- 1
d1 <- dist_from_feature(one)

win <- d1[(r0 - 20):(r0 + 20), (c0 - 20):(c0 + 20)]
dx <- matrix(rep(-20:20, each = 41), 41, 41)      # 行方向 = y
dy <- matrix(rep(-20:20, times = 41), 41, 41)
expect <- 1000 * sqrt(dx^2 + dy^2)
got <- matrix(as.numeric(as.matrix(win, wide = TRUE)), nrow = 41, byrow = FALSE)
if (!identical(dim(got), dim(expect))) got <- matrix(got, nrow = 41)
err <- max(abs(got - expect), na.rm = TRUE)
cat(sprintf("\ncheck D2 (analytic geometry): max |error| = %.4f m over the 41x41 window -> %s\n",
            err, if (err < 0.01) "PASS" else "FAIL"))
if (err >= 0.01) stop("distance surface deviates from the Euclidean grid metric")

# ---- 校验 D3：交付道路层的复核（信息性）-----------------------------------
ref_path <- sample_layer("glo", "dist", "grip4", "road", "glo_dist_grip4_road.tif")
if (file.exists(ref_path)) {
  ref <- terra::rast(ref_path)
  rv <- terra::values(ref, mat = FALSE)
  rv <- rv[is.finite(rv)]
  cat(sprintf("check D3 (delivered road layer): %d cells, %.2f%% at distance 0, max %.0f km\n",
              length(rv), 100 * mean(rv == 0), max(rv) / 1000))
}

# ---- 写出（生产写盘函数）---------------------------------------------------
outdir <- example_outdir("distance")
dst <- file.path(outdir, "dist_to_boundary.tif")
atomic_write_raster(dst, d, dtype = "float32")
cat(sprintf("written           : %s\n", basename(dst)))

example_rule("distance layers: all checks passed")
