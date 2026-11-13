# R/figs/fig02_layers_atlas.R
# Fig. 2 (new layout): the four layer families as a specimen atlas.
#
# Instead of four quadrant panels with diagonally stacked cards and axes, the figure
# is four horizontal strips. Each strip carries a solid header block (family, layer
# count, dataset count) on the left, and three bare example maps on the right, with
# the layer name printed under each map. No axes, no colour bars: the strips are a
# catalogue of what the archive contains, not a quantitative reading.
#
# Inputs: bare map tiles rendered by render_china_map.R with --bare, kept in
#   00_docs/figures/tiles/
# Output: 00_docs/SUBMISSION/figures/fig02_layers_atlas.{png,pdf}
#
# Usage: Rscript R/figs/fig02_layers_atlas.R

root <- Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM")
tile_dir <- file.path(root, "00_docs", "figures", "tiles")
out_dir  <- file.path(root, "00_docs", "SUBMISSION", "figures")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- palette ---------------------------------------------------------------
HEAD_BG  <- "#000000"
HEAD_ALT <- "#000000"
TXT      <- "#000000"
SUB      <- "#FFFFFF"
EDGE     <- "#000000"

# ---- content ---------------------------------------------------------------
STRIPS <- list(
  list(letter = "(a)", title = "All layers", n = "21,788 layers",
       sub = "8 themes \u00d7 25 datasets",
       note = "1,503 + 3,982 + 16,286 + 17",
       tiles = c("t_ph", "t_elev", "t_canopy"),
       labels = c("soil pH, 0-5 cm", "elevation", "canopy height")),
  list(letter = "(b)", title = "Composition", n = "3,982 layers",
       sub = "3 products \u00d7 5 scales",
       note = "one share per class",
       tiles = c("t_crop1k", "t_forest", "t_imperv"),
       labels = c("cropland", "forest", "impervious")),
  list(letter = "(c)", title = "Context", n = "16,286 layers",
       sub = "9 datasets \u00d7 4 radii",
       note = "windows of 1 to 20 km",
       tiles = c("t_crop1k", "t_crop10k", "t_crop20k"),
       labels = c("1 km", "10 km", "20 km")),
  list(letter = "(d)", title = "Distance", n = "17 layers",
       sub = "5 datasets \u00d7 5 features",
       note = "metres to the nearest",
       tiles = c("t_water", "t_stream", "t_road"),
       labels = c("surface water", "streams", "major roads")),
  list(letter = "(e)", title = "Future branch", n = "16,990 layers",
       sub = "4 datasets \u00d7 5 SSP-RCP",
       note = "future of (b) and (c)",
       tiles = c("t_ssp126", "t_ssp245", "t_ssp585"),
       labels = c("SSP1-2.6", "SSP2-4.5", "SSP5-8.5"))
)

# ---- geometry (centimetres) ------------------------------------------------
W        <- 16.6
MARGIN   <- 0.45
HEAD_W   <- 4.72
HEAD_GAP <- 0.32
TILE_W   <- 3.50
TILE_GAP <- 0.20
TILE_ASP <- 3.5 / 4.2          # height / width of the rendered tiles
TILE_H   <- TILE_W * TILE_ASP
LABEL_H  <- 0.44
STRIP_GAP <- 0.38
TOP_PAD  <- 0.34
BOT_PAD  <- 0.28

strip_h <- TILE_H + LABEL_H
H <- TOP_PAD + length(STRIPS) * strip_h + (length(STRIPS) - 1L) * STRIP_GAP + BOT_PAD

missing <- unlist(lapply(STRIPS, function(s) {
  # guard: paste0(character(0), ".png") returns ".png" on this R build
  bad <- s$tiles[!file.exists(file.path(tile_dir, paste0(s$tiles, ".png")))]
  if (length(bad)) paste0(bad, ".png") else character(0)
}))
if (length(missing)) stop("missing tiles: ", paste(missing, collapse = ", "))

draw <- function() {
  par(mar = c(0, 0, 0, 0), ps = 9, family = "sans", xaxs = "i", yaxs = "i")
  plot(NA, xlim = c(0, W), ylim = c(0, H), axes = FALSE, xlab = "", ylab = "")

  tiles_x0 <- MARGIN + HEAD_W + HEAD_GAP
  y_top <- H - TOP_PAD

  for (i in seq_along(STRIPS)) {
    st <- STRIPS[[i]]
    y0 <- y_top - (i - 1L) * (strip_h + STRIP_GAP)   # top of this strip
    y_tile_bot <- y0 - TILE_H

    # header block
    bg <- if (i %% 2 == 0) HEAD_ALT else HEAD_BG
    rect(MARGIN, y_tile_bot, MARGIN + HEAD_W, y0, col = bg, border = NA)

    tx <- MARGIN + 0.34
    text(tx, y0 - 0.34, st$letter, adj = c(0, 0.5), col = "white", cex = 0.86, font = 2)
    text(tx + 0.62, y0 - 0.34, st$title, adj = c(0, 0.5), col = "white", cex = 1.10, font = 2)
    text(tx, y0 - 1.28, st$n, adj = c(0, 0.5), col = "white", cex = 1.42, font = 2)
    text(tx, y0 - 1.94, st$sub, adj = c(0, 0.5), col = SUB, cex = 0.84)
    if (!is.null(st$note)) {
      text(tx, y_tile_bot + 0.26, st$note, adj = c(0, 0.5), col = SUB, cex = 0.68, font = 3)
    }

    # tiles and their labels
    for (k in seq_along(st$tiles)) {
      x0 <- tiles_x0 + (k - 1L) * (TILE_W + TILE_GAP)
      x1 <- x0 + TILE_W
      img <- png::readPNG(file.path(tile_dir, paste0(st$tiles[k], ".png")))
      rasterImage(img, x0, y_tile_bot, x1, y0, interpolate = TRUE)
      rect(x0, y_tile_bot, x1, y0, col = NA, border = EDGE, lwd = 0.8)
      text((x0 + x1) / 2, y_tile_bot - 0.22, st$labels[k], col = TXT, cex = 0.80)
    }
  }
}

for (dev in c("png", "pdf")) {
  f <- file.path(out_dir, paste0("fig02_layers_atlas.", dev))
  if (dev == "png") {
    png(f, width = W / 2.54, height = H / 2.54, units = "in", res = 600, bg = "white")
  } else {
    pdf(f, width = W / 2.54, height = H / 2.54, bg = "white")
  }
  draw()
  dev.off()
  cat(sprintf("written: %s  (%.1f x %.1f cm)\n", f, W, H))
}
