# R/figs/fig02_layer_overview.R
# CHECO26 Figure 2 - layer-type overview (four-panel composite, English)
#
# The map cards are rendered with the standards-compliant China basemap from the
# `geo-viz` skill: provincial boundary (china.shp), South China Sea nine-dash line
# (dashline.shp) and the South China Sea inset, so every map is territorially
# complete. Palettes are the skill's semantic keys.
#
#   (a) All layers      x = 8 themes     y = 21 datasets -> 21,110 layers
#   (b) Distance layers x = 17 layers    y = 5 datasets  -> 17 layers
#   (c) Focal layers    x = 4 scales     y = 9 datasets  -> 16,286 layers
#   (d) Scenario layers x = 5 SSP-RCPs   y = 4 datasets  -> 16,990 layers
#
# Each card is rendered to a temporary PNG by ggplot2 and composited into the four-panel
# layout with base graphics, which keeps panel framing and map rendering separate.
#
# Output: 00_docs/SUBMISSION/figures/fig02_layers_overview.png / .pdf

suppressPackageStartupMessages({
  library(terra); library(sf); library(ggplot2); library(png)
})
sf::sf_use_s2(FALSE)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT   <- "E:/CHECO26/N-SDM/data/covariates"
OUT    <- "E:/CHECO26/N-SDM/00_docs/SUBMISSION/figures"
ASSETS <- "C:/Users/LQ/.agents/skills/geo-viz/assets/china"
CACHE  <- file.path(tempdir(), "checo_fig02")
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

## ---- basemap constants (from geo-viz) --------------------------------------
DISP_RES   <- 0.05
DISP_TE    <- c(73.40, 18.10, 135.15, 53.60)
INSET_XLIM <- c(105, 126)
INSET_YLIM <- c(2, 26)
BORDER_COL <- "#4E5963"
FONT       <- "Arial"

## ---- palettes (geo-viz semantic keys) --------------------------------------
pal_seq <- function(name, n = 256, rev = FALSE) {
  cols <- grDevices::hcl.colors(n, name); if (rev) rev(cols) else cols
}
PAL <- list(
  ph      = pal_seq("RdYlBu"),
  terrain = pal_seq("Terrain 2"),
  height  = pal_seq("Emrld", rev = TRUE),
  dist    = pal_seq("YlGnBu", rev = TRUE),   # near = dark
  prop    = pal_seq("YlGn", rev = TRUE),
  temp    = pal_seq("RdYlBu", rev = TRUE)
)

## ---- basemap ---------------------------------------------------------------
load_vec <- function(path) {
  v <- sf::st_read(path, quiet = TRUE)
  if (is.na(sf::st_crs(v)) || (sf::st_crs(v)$epsg %||% 0L) != 4326L)
    v <- suppressWarnings(sf::st_transform(v, 4326))
  sf::st_make_valid(v)
}

china_sf   <- load_vec(file.path(ASSETS, "china.shp"))
dash_sf    <- load_vec(file.path(ASSETS, "dashline.shp"))
china_vect <- terra::vect(file.path(ASSETS, "china.shp"))
if ((terra::crs(china_vect, describe = TRUE)$code %||% "") != "4326")
  china_vect <- terra::project(china_vect, "EPSG:4326")

## ---- raster -> display grid, masked to China -------------------------------
prep_df <- function(rel, log10_it = FALSE) {
  src <- file.path(ROOT, rel)
  if (!file.exists(src)) stop("missing: ", src)
  dst <- file.path(CACHE, paste0(gsub("[^A-Za-z0-9]", "_", rel), "_disp.tif"))
  if (!file.exists(dst)) {
    sf::gdal_utils("warp", source = src, destination = dst,
                   options = c("-t_srs", "EPSG:4326",
                               "-te", sprintf("%.4f", DISP_TE[1]), sprintf("%.4f", DISP_TE[2]),
                                       sprintf("%.4f", DISP_TE[3]), sprintf("%.4f", DISP_TE[4]),
                               "-tr", sprintf("%.4f", DISP_RES), sprintf("%.4f", DISP_RES),
                               "-r", "average", "-overwrite", "-of", "GTiff",
                               "-co", "COMPRESS=DEFLATE", "-multi", "-ovr", "AUTO"),
                   quiet = TRUE)
  }
  r <- terra::mask(terra::rast(dst)[[1]], china_vect)
  if (log10_it) r <- log10(terra::ifel(r < 0.1, 0.1, r))
  df <- terra::as.data.frame(r, xy = TRUE, na.rm = TRUE)
  names(df) <- c("x", "y", "value")
  df
}

## ---- one compliant map card -> PNG ----------------------------------------
card_png <- function(df, pal, lim, tag) {
  f <- file.path(CACHE, paste0("card_", tag, ".png"))
  main <- ggplot2::ggplot() +
    ggplot2::geom_raster(data = df, ggplot2::aes(x = .data$x, y = .data$y,
                                                 fill = .data$value)) +
    ggplot2::scale_fill_gradientn(colours = pal, limits = lim,
                                  oob = scales::oob_squish, na.value = "transparent") +
    ggplot2::geom_sf(data = china_sf, fill = NA, colour = BORDER_COL, linewidth = 0.22) +
    ggplot2::geom_sf(data = dash_sf, fill = NA, colour = BORDER_COL, linewidth = 0.28) +
    ggplot2::coord_sf(xlim = DISP_TE[c(1, 3)], ylim = DISP_TE[c(2, 4)],
                      expand = FALSE, datum = NA) +
    ggplot2::theme_void(base_family = FONT) +
    ggplot2::theme(legend.position = "none",
                   plot.background  = ggplot2::element_rect(fill = "white", colour = NA),
                   panel.background = ggplot2::element_rect(fill = "white", colour = NA),
                   plot.margin = ggplot2::margin(0, 0, 0, 0))

  # South China Sea inset
  sub <- df[df$x >= INSET_XLIM[1] & df$x <= INSET_XLIM[2] &
              df$y >= INSET_YLIM[1] & df$y <= INSET_YLIM[2], , drop = FALSE]
  inset <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = china_sf, fill = "#F5F6F7", colour = NA)
  if (nrow(sub) > 0)
    inset <- inset + ggplot2::geom_raster(
      data = sub, ggplot2::aes(x = .data$x, y = .data$y, fill = .data$value)) +
      ggplot2::scale_fill_gradientn(colours = pal, limits = lim,
                                    oob = scales::oob_squish, na.value = "transparent")
  inset <- inset +
    ggplot2::geom_sf(data = china_sf, fill = NA, colour = BORDER_COL, linewidth = 0.18) +
    ggplot2::geom_sf(data = dash_sf, fill = NA, colour = BORDER_COL, linewidth = 0.25) +
    ggplot2::coord_sf(xlim = INSET_XLIM, ylim = INSET_YLIM, expand = FALSE, datum = NA) +
    ggplot2::theme_void(base_family = FONT) +
    ggplot2::theme(legend.position = "none",
                   plot.background  = ggplot2::element_rect(fill = "white", colour = NA),
                   panel.background = ggplot2::element_rect(fill = "white", colour = NA),
                   panel.border = ggplot2::element_rect(fill = NA, colour = BORDER_COL,
                                                        linewidth = 0.4),
                   plot.margin = ggplot2::margin(0, 0, 0, 0))

  b  <- DISP_TE
  xr <- b[3] - b[1]; yr <- b[4] - b[2]
  ins_w <- xr * 0.17; ins_h <- yr * 0.31
  xmax <- b[3] - xr * 0.010; xmin <- xmax - ins_w
  ymin <- b[2] + yr * 0.010; ymax <- ymin + ins_h

  p <- main + ggplot2::annotation_custom(
    grob = ggplot2::ggplotGrob(inset),
    xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax)

  # 1.739 = display-grid aspect (61.75 deg / 35.5 deg)
  ggplot2::ggsave(f, p, width = 2.6, height = 2.6 / 1.739, dpi = 600,
                  bg = "white", limitsize = FALSE)
  f
}

## ---- panel geometry --------------------------------------------------------
ASPECT <- 1.739
CARD_W <- 0.420                      # 卡片宽（面板宽度比例）
CARD_H <- CARD_W * 50 / ASPECT / 46  # 按 1.739 的显示网格长宽比反算
# 错位 0.22（x）/ 0.19（y）：重叠约 48% / 28%，每张卡片都能看清大半
CARD_XY <- list(c(0.100, 0.130), c(0.320, 0.320), c(0.540, 0.510))

## ---- content ---------------------------------------------------------------
LAYERS <- list(
  list(title = "(a) All layers", ylab = "21 datasets", xlab = "8 themes",
       nlab = "21,110 layers",
       rel = c("glo/soil/csdlv2/ph/0/glo_soil_csdlv2_ph_0.tif",
               "glo/topo/chinadem/elev/glo_topo_chinadem_elev.tif",
               "glo/vege/ch2019/ch/glo_vege_ch2019_ch.tif"),
       pals = list(PAL$ph, PAL$terrain, PAL$height),
       labels = c("Soil pH (0-5 cm)", "Elevation", "Canopy height")),
  list(title = "(b) Distance layers", ylab = "5 datasets",
       xlab = "17 layers (log10 colour scale)", nlab = "17 layers", log = TRUE,
       rel = c("glo/dist/gsw/water/glo_dist_gsw_water.tif",
               "glo/dist/h90m/stream-dist-dw-near/glo_dist_h90m_stream-dist-dw-near.tif",
               "glo/dist/grip4/majorroad/glo_dist_grip4_majorroad.tif"),
       pals = list(PAL$dist, PAL$dist, PAL$dist),
       labels = c("Surface water", "Rivers", "Major roads")),
  list(title = "(c) Focal layers", ylab = "9 datasets",
       xlab = "Cropland proportion, 4 scales", nlab = "16,286 layers",
       rel = c("glo/lulc/clcd/2000/cropland/glo_lulc_clcd_2000_cropland_prop_f1000.tif",
               "glo/lulc/clcd/2000/cropland/glo_lulc_clcd_2000_cropland_prop_f10000.tif",
               "glo/lulc/clcd/2000/cropland/glo_lulc_clcd_2000_cropland_prop_f20000.tif"),
       pals = list(PAL$prop, PAL$prop, PAL$prop),
       labels = c("1 km", "10 km", "20 km"), zlim = c(0, 1)),
  list(title = "(d) Scenario layers", ylab = "4 datasets",
       xlab = "5 SSP-RCP scenarios, temperature 2030", nlab = "16,990 layers",
       rel = c("glo/bioclim/cnclim1km-ensmean/scenario/2030/ssp126/bio01/glo_bioclim_cnclim1km-ensmean_scenario_2030_ssp126_bio01.tif",
               "glo/bioclim/cnclim1km-ensmean/scenario/2030/ssp245/bio01/glo_bioclim_cnclim1km-ensmean_scenario_2030_ssp245_bio01.tif",
               "glo/bioclim/cnclim1km-ensmean/scenario/2030/ssp585/bio01/glo_bioclim_cnclim1km-ensmean_scenario_2030_ssp585_bio01.tif"),
       pals = list(PAL$temp, PAL$temp, PAL$temp),
       labels = c("SSP1-2.6", "SSP2-4.5", "SSP5-8.5"))
)

cat("rendering map cards on the compliant basemap ...\n")
for (i in seq_along(LAYERS)) {
  L <- LAYERS[[i]]
  dfs <- lapply(L$rel, function(r) prep_df(r, isTRUE(L$log)))
  lims <- if (is.null(L$zlim))
            lapply(dfs, function(d)
              as.numeric(stats::quantile(d$value, c(0.02, 0.98), na.rm = TRUE)))
          else rep(list(L$zlim), length(dfs))
  LAYERS[[i]]$png <- mapply(function(d, lm, k)
    card_png(d, L$pals[[k]], lm, sprintf("%d_%d", i, k)),
    dfs, lims, seq_along(dfs), SIMPLIFY = TRUE)
  cat(sprintf("  %-22s %d cards\n", L$title, length(dfs)))
}

## ---- composite -------------------------------------------------------------
AXIS_COL <- "#3C4146"

arrow_ax <- function(x0, y0, x1, y1, lwd = 1.2) {
  segments(x0, y0, x1, y1, col = AXIS_COL, lwd = lwd)
  d <- 0.016
  if (x0 == x1) polygon(x1 + c(-d, d, 0), c(y1, y1, y1 + d * 1.5),
                        col = AXIS_COL, border = AXIS_COL)
  else polygon(c(x1, x1, x1 + d * 1.5), y1 + c(-d, d, 0),
               col = AXIS_COL, border = AXIS_COL)
}

panel <- function(px, py, pw, ph, L) {
  X <- function(u) px + u * pw
  Y <- function(v) py + v * ph

  text(X(0.50), Y(0.985), L$title, cex = 1.24, font = 2, col = "#1A1A1A", family = FONT)
  text(X(0.50), Y(0.916), L$nlab, cex = 0.86, col = "#6B7075", family = FONT)

  arrow_ax(X(0.075), Y(0.105), X(0.075), Y(0.860))
  arrow_ax(X(0.075), Y(0.105), X(0.965), Y(0.105))

  text(X(0.026), Y(0.48), L$ylab, srt = 90, cex = 0.90, col = "#6B7075", family = FONT)
  text(X(0.52), Y(0.048), L$xlab, cex = 0.88, col = "#6B7075", family = FONT)

  geo <- lapply(CARD_XY, function(xy) {
    x0 <- X(xy[1]); y0 <- Y(xy[2])
    list(x0 = x0, y0 = y0,
         w = X(xy[1] + CARD_W) - x0,
         h = Y(xy[2] + CARD_H) - y0)
  })
  for (k in seq_along(geo)) {
    g <- geo[[k]]
    rect(g$x0, g$y0, g$x0 + g$w, g$y0 + g$h, col = "white", border = NA)
    img <- png::readPNG(L$png[k])
    rasterImage(img, g$x0, g$y0, g$x0 + g$w, g$y0 + g$h, interpolate = TRUE)
    rect(g$x0, g$y0, g$x0 + g$w, g$y0 + g$h, col = NA, border = "#5A5F64", lwd = 0.9)
  }
  # labels clear above each card, clamped inside the panel
  for (k in seq_along(geo)) {
    g <- geo[[k]]
    cex <- 0.62
    w <- strwidth(L$labels[k], cex = cex, family = FONT)
    xl <- min(max(g$x0, X(0.02)), X(0.965) - w)
    text(xl, g$y0 + g$h + strheight("Ag", cex = cex, family = FONT) * 1.55,
         L$labels[k], cex = cex, col = "#1A1A1A", family = FONT, adj = c(0, 0.5))
  }
}

draw <- function() {
  par(mar = c(0, 0, 0, 0), family = FONT)
  plot(NA, xlim = c(0, 100), ylim = c(0, 100), axes = FALSE, xlab = "", ylab = "")
  pos <- list(c(0.00, 0.52), c(0.50, 0.52), c(0.00, 0.02), c(0.50, 0.02))
  for (i in seq_along(LAYERS))
    panel(pos[[i]][1] * 100, pos[[i]][2] * 100, 50, 46, LAYERS[[i]])
}

W_IN <- 180 / 25.4
H_IN <- 172 / 25.4
invisible(png(file.path(OUT, "fig02_layers_overview.png"),
              width = W_IN, height = H_IN, units = "in", res = 640,
              bg = "white", type = "cairo"))
draw(); invisible(dev.off())
invisible(cairo_pdf(file.path(OUT, "fig02_layers_overview.pdf"),
                    width = W_IN, height = H_IN, bg = "white"))
draw(); invisible(dev.off())
cat("wrote fig02_layers_overview.png / .pdf\n")
