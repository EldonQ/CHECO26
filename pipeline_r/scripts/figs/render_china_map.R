#!/usr/bin/env Rscript
# =============================================================================
# geo-viz - Render a raster over a standards-compliant China basemap (R).
# -----------------------------------------------------------------------------
# Effect (distilled from a production research-visualization pipeline):
#   - China boundary (china.shp) + South China Sea nine-dash line (dashline.shp)
#   - South China Sea inset in the bottom-right corner
#   - Nature-style, colour-blind-friendly palettes (continuous + discrete)
#   - Transparent background, clean title, main map + legend
#   - Export 600 dpi PNG (transparent) + cairo PDF
#
# Usage:
#   Rscript render_china_map.R --input data.tif --output out/name \
#       --title "Annual Mean Temperature" --legend "degC" --palette temp --clamp
#
#   Rscript render_china_map.R --input landcover.tif --output out/lc \
#       --mode class --classes clcd --title "Land Cover"
# =============================================================================

suppressPackageStartupMessages({
  library(terra)
  library(sf)
  library(ggplot2)
})
sf::sf_use_s2(FALSE)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# ----------------------------------------------------------------------------
# Minimal CLI parser: --flag value / --flag (boolean)
# ----------------------------------------------------------------------------
parse_args <- function(args) {
  opt <- list(
    input = NULL, output = NULL, title = "", legend = "", palette = "viridis",
    mode = "continuous", classes = "clcd", band = NA_integer_,
    limits = NULL, clamp = FALSE, reverse = FALSE, midpoint = NA_real_,
    list_palettes = FALSE, src_nodata = NA_real_, assets = NULL,
    width = 7, height = 6.2, dpi = 600, res = NA_real_
  )
  bool_flags <- c("clamp", "reverse", "list_palettes")
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (!startsWith(a, "--")) { i <- i + 1L; next }
    key <- gsub("-", "_", sub("^--", "", a))
    if (key %in% bool_flags) { opt[[key]] <- TRUE; i <- i + 1L; next }
    if (key == "limits") {
      opt$limits <- as.numeric(c(args[[i + 1L]], args[[i + 2L]])); i <- i + 3L; next
    }
    val <- args[[i + 1L]]
    if (key %in% c("band")) val <- as.integer(val)
    if (key %in% c("src_nodata", "midpoint", "width", "height", "dpi", "res")) val <- as.numeric(val)
    opt[[key]] <- val
    i <- i + 2L
  }
  opt
}

# ----------------------------------------------------------------------------
# Constants (identical to the reference implementation)
# ----------------------------------------------------------------------------
DISP_RES   <- 0.05
DISP_TE    <- c(73.40, 18.10, 135.15, 53.60)  # xmin ymin xmax ymax
INSET_XLIM <- c(105, 126)
INSET_YLIM <- c(2, 26)
BORDER_COL <- "#4E5963"
FONT_FAMILY <- "sans"

pal_seq <- function(name, n = 256, rev = FALSE) {
  cols <- grDevices::hcl.colors(n, name); if (rev) rev(cols) else cols
}
PAL <- list(
  temp = pal_seq("RdYlBu", rev = TRUE), soil = pal_seq("YlOrBr"),
  prop = pal_seq("YlGn", rev = TRUE), veg = pal_seq("Greens", rev = TRUE),
  biomass = pal_seq("BuGn", rev = TRUE), height = pal_seq("Emrld", rev = TRUE),
  terrain = pal_seq("Terrain 2"), hydro = pal_seq("YlGnBu"),
  pop = pal_seq("Inferno", rev = TRUE), human = pal_seq("Rocket", rev = TRUE),
  emf = pal_seq("Viridis"), precip = pal_seq("YlGnBu"),
  seasonal = pal_seq("Viridis"), heat = pal_seq("YlOrRd"),
  solar = pal_seq("YlOrBr"), diversity = pal_seq("Viridis"),
  edge = pal_seq("PuRd"), texture = pal_seq("YlOrBr"),
  ph = pal_seq("RdYlBu"), fertility = pal_seq("Greens", rev = TRUE),
  neutral = pal_seq("Viridis"), slope = pal_seq("YlOrRd"),
  hillshade = grDevices::grey.colors(256, start = 0.05, end = 0.95),
  accum = pal_seq("YlGnBu")
)

# Perceptually uniform, colour-blind-safe maps shared with the Python engine.
# Values are grDevices::hcl.colors palette names (rendered natively here).
PERCEPTUAL <- c(viridis = "Viridis", cividis = "Cividis",
                inferno = "Inferno", plasma = "Plasma")

# Nature-grade themes defined by EXPLICIT hex control points. These stops are
# byte-for-byte identical to THEMES in render_china_map.py so both engines
# interpolate the exact same colours. Sequential ramps run light -> dark; the
# names in DIVERGING run low -> neutral -> high and pair with --midpoint.
THEMES <- list(
  blues   = c("#F7FBFF", "#DEEBF7", "#C6DBEF", "#9ECAE1", "#6BAED6", "#4292C6", "#2171B5", "#08519C", "#08306B"),
  greens  = c("#F7FCF5", "#E5F5E0", "#C7E9C0", "#A1D99B", "#74C476", "#41AB5D", "#238B45", "#006D2C", "#00441B"),
  purples = c("#FCFBFD", "#EFEDF5", "#DADAEB", "#BCBDDC", "#9E9AC8", "#807DBA", "#6A51A3", "#54278F", "#3F007D"),
  oranges = c("#FFF5EB", "#FEE6CE", "#FDD0A2", "#FDAE6B", "#FD8D3C", "#F16913", "#D94801", "#A63603", "#7F2704"),
  reds    = c("#FFF5F0", "#FEE0D2", "#FCBBA1", "#FC9272", "#FB6A4A", "#EF3B2C", "#CB181D", "#A50F15", "#67000D"),
  teal    = c("#F7FCFD", "#E5F5F9", "#CCECE6", "#99D8C9", "#66C2A4", "#41AE76", "#238B45", "#006D2C", "#00441B"),
  ylgnbu  = c("#FFFFD9", "#EDF8B1", "#C7E9B4", "#7FCDBB", "#41B6C4", "#1D91C0", "#225EA8", "#253494", "#081D58"),
  ylorrd  = c("#FFFFCC", "#FFEDA0", "#FED976", "#FEB24C", "#FD8D3C", "#FC4E2A", "#E31A1C", "#BD0026", "#800026"),
  mako    = c("#D5F0EA", "#9FDCCB", "#5FB3A3", "#2E8289", "#1E4F6B", "#16263F"),
  rocket  = c("#FBE6C8", "#F6A97A", "#E85D5D", "#B5305F", "#6E1A55", "#2C0B2E"),
  rdbu     = c("#053061", "#2166AC", "#4393C3", "#92C5DE", "#D1E5F0", "#F7F7F7", "#FDDBC7", "#F4A582", "#D6604D", "#B2182B", "#67001F"),
  rdylbu   = c("#313695", "#4575B4", "#74ADD1", "#ABD9E9", "#E0F3F8", "#FFFFBF", "#FEE090", "#FDAE61", "#F46D43", "#D73027", "#A50026"),
  spectral = c("#3288BD", "#66C2A5", "#ABDDA4", "#E6F598", "#FFFFBF", "#FEE08B", "#FDAE61", "#F46D43", "#D53E4F", "#9E0142"),
  brbg     = c("#543005", "#8C510A", "#BF812D", "#DFC27D", "#F6E8C3", "#F5F5F5", "#C7EAE5", "#80CDC1", "#35978F", "#01665E", "#003C30"),
  puor     = c("#7F3B08", "#B35806", "#E08214", "#FDB863", "#FEE0B6", "#F7F7F7", "#D8DAEB", "#B2ABD2", "#8073AC", "#542788", "#2D004B"),
  prgn     = c("#40004B", "#762A83", "#9970AB", "#C2A5CF", "#E7D4E8", "#F7F7F7", "#D9F0D3", "#A6DBA0", "#5AAE61", "#1B7837", "#00441B")
)
DIVERGING <- c("rdbu", "rdylbu", "spectral", "brbg", "puor", "prgn")

# Resolve a palette name -> colour vector. Order: THEMES -> PERCEPTUAL ->
# semantic PAL. Unknown names abort with a helpful message (no silent misuse).
resolve_palette <- function(name, reverse = FALSE) {
  cols <- if (!is.null(THEMES[[name]])) THEMES[[name]]
    else if (name %in% names(PERCEPTUAL)) pal_seq(PERCEPTUAL[[name]])
    else if (!is.null(PAL[[name]])) PAL[[name]]
    else stop("Unknown palette '", name, "'. Run --list-palettes to see options.")
  if (isTRUE(reverse)) rev(cols) else cols
}

print_palettes <- function() {
  seq_k <- setdiff(names(THEMES), DIVERGING)
  cat("Nature-grade themes (byte-for-byte identical in Python and R):\n")
  cat("  sequential :", paste(seq_k, collapse = ", "), "\n")
  cat("  diverging  :", paste(DIVERGING, collapse = ", "), "  (pair with --midpoint)\n")
  cat("  perceptual :", paste(names(PERCEPTUAL), collapse = ", "), "\n")
  cat("Semantic keys (auto-picked by variable type):\n")
  cat(" ", paste(sort(names(PAL)), collapse = ", "), "\n")
  cat("Add --reverse to flip any palette.\n")
}

CLASS_DEFS <- list(
  clcd = list(
    codes = c(1, 2, 3, 4, 5, 6, 7, 8, 9),
    labels = c("Cropland", "Forest", "Shrub", "Grassland", "Water",
               "Snow/Ice", "Barren", "Impervious", "Wetland"),
    colors = c("#FAE39C", "#446F33", "#33A02C", "#ABD37B", "#1E69B4",
               "#A6CEE3", "#CFBDA3", "#E24290", "#289BE8")),
  glulc6 = list(
    codes = c(1, 2, 3, 4, 5, 6),
    labels = c("Cropland", "Forest", "Grassland", "Urban", "Barren", "Water"),
    colors = c("#E8C86E", "#2E7D32", "#9CCB6A", "#B2182B", "#D7C9A8", "#3B7BB4")),
  harmonised = list(
    codes = c(11, 22, 33, 441, 442, 55, 66, 77),
    labels = c("Urban", "Cropland", "Pasture", "Managed forest",
               "Unmanaged forest", "Grass/shrub", "Sparse veg.", "Water"),
    colors = c("#B2182B", "#E8C86E", "#C7A76C", "#2E7D32", "#7FBF7B",
               "#9CCB6A", "#D7C9A8", "#3B7BB4"))
)

# ----------------------------------------------------------------------------
# Basemap
# ----------------------------------------------------------------------------
load_vec <- function(path) {
  if (!file.exists(path)) return(NULL)
  v <- sf::st_read(path, quiet = TRUE)
  if (is.na(sf::st_crs(v)) || (sf::st_crs(v)$epsg %||% 0L) != 4326L) {
    v <- suppressWarnings(sf::st_transform(v, 4326))
  }
  sf::st_make_valid(v)
}

# ----------------------------------------------------------------------------
# Raster: reproject to unified grid + mask to China
# ----------------------------------------------------------------------------
prepare_raster <- function(input, china_vect, band, mode, src_nodata, cache, res = NA_real_) {
  method <- if (identical(mode, "class")) "near" else "average"
  # 2026-10-21 项目内修改：原脚本把显示网格硬编码为 0.05°（约 5.5 km）。
  # 对 1 km 产品而言，600 dpi 下每输出像素约 1.3 km，0.05° 网格会出现明显方块。
  # 因此加一个 --res 参数；未给时仍回落到原值。
  res_use <- if (is.na(res)) DISP_RES else res
  wopt <- c("-t_srs", "EPSG:4326",
            "-te", sprintf("%.4f", DISP_TE[1]), sprintf("%.4f", DISP_TE[2]),
                    sprintf("%.4f", DISP_TE[3]), sprintf("%.4f", DISP_TE[4]),
            "-tr", sprintf("%.6f", res_use), sprintf("%.6f", res_use),
            "-r", method, "-overwrite", "-of", "GTiff",
            "-co", "COMPRESS=DEFLATE", "-multi", "-ovr", "AUTO")
  work_src <- input
  if (!is.na(band) && terra::nlyr(terra::rast(input)) > 1L) {
    tmp_b <- file.path(cache, "band_extract.tif")
    sf::gdal_utils("translate", source = input, destination = tmp_b,
                   options = c("-b", as.character(band)), quiet = TRUE)
    work_src <- tmp_b
  }
  if (!is.na(src_nodata)) wopt <- c(wopt, "-srcnodata", as.character(src_nodata))
  dst <- file.path(cache, "display.tif")
  sf::gdal_utils("warp", source = work_src, destination = dst,
                 options = wopt, quiet = TRUE)
  r <- terra::rast(dst)[[1]]
  if (terra::is.factor(r)) {
    codes <- terra::values(r)[, 1]
    r <- terra::setValues(terra::rast(r), codes)
  }
  r <- terra::mask(r, china_vect)
  df <- terra::as.data.frame(r, xy = TRUE, na.rm = TRUE)
  names(df) <- c("x", "y", "value")
  df
}

# ----------------------------------------------------------------------------
# build_map: main map + South China Sea inset (single ggplot)
# ----------------------------------------------------------------------------
build_map <- function(df, china_sf, dashline_sf, title, legend_title,
                      discrete, palette, limits, class_def, midpoint = NA_real_) {
  bounds <- as.numeric(sf::st_bbox(china_sf))
  if (discrete) {
    keep <- class_def$codes %in% as.integer(as.character(unique(df$value)))
    codes <- class_def$codes[keep]; labs <- class_def$labels[keep]
    cols <- class_def$colors[keep]
    df$value <- factor(df$value, levels = as.character(codes), labels = labs)
    fill_scale <- ggplot2::scale_fill_manual(
      values = stats::setNames(cols, labs), name = legend_title,
      na.value = "transparent", drop = TRUE)
  } else {
    rescaler <- if (!is.na(midpoint)) {
      function(x, to = c(0, 1), from = range(x, na.rm = TRUE))
        scales::rescale_mid(x, to, from, mid = midpoint)
    } else scales::rescale
    fill_scale <- ggplot2::scale_fill_gradientn(
      colours = palette, name = legend_title, limits = limits,
      rescaler = rescaler, oob = scales::oob_squish, na.value = "transparent")
  }

  main_theme <- ggplot2::theme_void(base_size = 11, base_family = FONT_FAMILY) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", hjust = 0.5, size = 12,
                                         margin = ggplot2::margin(b = 3)),
      plot.background   = ggplot2::element_rect(fill = "transparent", colour = NA),
      panel.background  = ggplot2::element_rect(fill = "transparent", colour = NA),
      legend.background = ggplot2::element_rect(fill = "transparent", colour = NA),
      legend.key        = ggplot2::element_rect(fill = "transparent", colour = NA),
      legend.position = "right",
      legend.key.width = ggplot2::unit(0.42, "cm"),
      legend.key.height = ggplot2::unit(1.4, "cm"),
      plot.margin = ggplot2::margin(4, 4, 4, 4))

  p <- ggplot2::ggplot() +
    ggplot2::geom_raster(data = df, ggplot2::aes(x = .data$x, y = .data$y,
                                                 fill = .data$value)) +
    fill_scale +
    ggplot2::geom_sf(data = china_sf, fill = NA, colour = BORDER_COL, linewidth = 0.22)
  if (!is.null(dashline_sf))
    p <- p + ggplot2::geom_sf(data = dashline_sf, fill = NA, colour = BORDER_COL,
                              linewidth = 0.30)
  p <- p + ggplot2::coord_sf(xlim = bounds[c(1, 3)], ylim = bounds[c(2, 4)],
                             expand = FALSE, datum = NA) +
    ggplot2::labs(title = title) + main_theme

  # inset --------------------------------------------------------------------
  sub <- df[df$x >= INSET_XLIM[1] & df$x <= INSET_XLIM[2] &
              df$y >= INSET_YLIM[1] & df$y <= INSET_YLIM[2], , drop = FALSE]
  inset <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = china_sf, fill = "#F5F6F7", colour = NA)
  if (nrow(sub) > 0)
    inset <- inset + ggplot2::geom_raster(
      data = sub, ggplot2::aes(x = .data$x, y = .data$y, fill = .data$value)) +
      fill_scale
  inset <- inset +
    ggplot2::geom_sf(data = china_sf, fill = NA, colour = BORDER_COL, linewidth = 0.18)
  if (!is.null(dashline_sf))
    inset <- inset + ggplot2::geom_sf(data = dashline_sf, fill = NA,
                                      colour = BORDER_COL, linewidth = 0.25)
  inset <- inset +
    ggplot2::coord_sf(xlim = INSET_XLIM, ylim = INSET_YLIM, expand = FALSE, datum = NA) +
    ggplot2::theme_void(base_family = FONT_FAMILY) +
    ggplot2::theme(
      legend.position = "none",
      plot.background = ggplot2::element_rect(fill = "transparent", colour = NA),
      panel.background = ggplot2::element_rect(fill = "transparent", colour = NA),
      panel.border = ggplot2::element_rect(fill = NA, colour = BORDER_COL, linewidth = 0.4),
      plot.margin = ggplot2::margin(0, 0, 0, 0))

  xr <- bounds[3] - bounds[1]; yr <- bounds[4] - bounds[2]
  ins_w <- xr * 0.16; ins_h <- yr * 0.30
  xmax <- bounds[3] - xr * 0.012; xmin <- xmax - ins_w
  ymin <- bounds[2] + yr * 0.012; ymax <- ymin + ins_h
  p + ggplot2::annotation_custom(grob = ggplot2::ggplotGrob(inset),
                                 xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax)
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main <- function() {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  if (isTRUE(opt$list_palettes)) { print_palettes(); return(invisible()) }
  if (is.null(opt$input) || is.null(opt$output))
    stop("--input and --output are required (or use --list-palettes)")
  if (!file.exists(opt$input)) stop("Input raster not found: ", opt$input)

  script_dir <- tryCatch({
    a <- commandArgs(FALSE)
    f <- sub("^--file=", "", a[grep("^--file=", a)])
    if (length(f)) dirname(normalizePath(f)) else getwd()
  }, error = function(e) getwd())
  assets <- opt$assets %||% file.path(script_dir, "..", "assets", "china")
  china_shp <- file.path(assets, "china.shp")
  dash_shp  <- file.path(assets, "dashline.shp")
  if (!file.exists(china_shp)) stop("china.shp not found under: ", assets)

  china_sf <- load_vec(china_shp)
  dashline_sf <- load_vec(dash_shp)
  china_vect <- terra::vect(china_shp)
  if (!is.na(terra::crs(china_vect)) &&
      (terra::crs(china_vect, describe = TRUE)$code %||% "") != "4326")
    china_vect <- terra::project(china_vect, "EPSG:4326")

  cache <- file.path(tempdir(), "geoviz_cache")
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  df <- prepare_raster(opt$input, china_vect, opt$band, opt$mode,
                       opt$src_nodata, cache, opt$res)
  if (nrow(df) == 0L) stop("No valid data inside China after masking.")

  discrete <- identical(opt$mode, "class")
  lim <- opt$limits
  if (!discrete && isTRUE(opt$clamp) && is.null(lim)) {
    lim <- as.numeric(stats::quantile(df$value, c(0.02, 0.98), na.rm = TRUE))
    if (!all(is.finite(lim)) || diff(lim) == 0) lim <- range(df$value, na.rm = TRUE)
  }
  palette <- resolve_palette(opt$palette, reverse = isTRUE(opt$reverse))
  class_def <- if (discrete) CLASS_DEFS[[opt$classes]] else NULL

  p <- build_map(df, china_sf, dashline_sf, opt$title, opt$legend,
                 discrete, palette, lim, class_def, opt$midpoint)

  outdir <- dirname(normalizePath(opt$output, mustWork = FALSE))
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  png_path <- paste0(opt$output, ".png")
  pdf_path <- paste0(opt$output, ".pdf")
  ggplot2::ggsave(png_path, p, width = opt$width, height = opt$height,
                  dpi = opt$dpi, bg = "transparent", limitsize = FALSE)
  ggplot2::ggsave(pdf_path, p, width = opt$width, height = opt$height,
                  device = grDevices::cairo_pdf, bg = "transparent",
                  limitsize = FALSE)
  message("  wrote: ", basename(png_path), " / ", basename(pdf_path))
}

main()
