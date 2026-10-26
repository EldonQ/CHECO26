# R/figs/fig01_workflow_v2.R
# CHECO26 Figure 1 - development workflow (English version for submission)
#
# Composition follows the technical-route-figure language common in Scientific Data
# descriptors: a vertical flow of four black pill headers (number + title + white line
# icon), a continuous cyan spine on the left with arrowheads entering each header,
# cyan filled boxes for the step outputs, an outlined 2x2 block for the core
# standardisation operations, a grey side panel for the selection criteria, and a
# summary band at the foot.
#
# Everything is drawn with base graphics (rect / polygon / segment / text); no external
# image assets, so the figure is exactly reproducible on any machine with Arial.
#
# Output (640 dpi PNG + vector PDF):
#   00_docs/SUBMISSION/figures/fig01_workflow_v2.png / .pdf
#
# The original fig01_workflow.* is left untouched; this is a separate deliverable.

OUT <- file.path(Sys.getenv("CHECO_ROOT", getwd()), "00_docs/SUBMISSION/figures")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

## ---------------------------------------------------------------- palette
BLACK  <- "#101010"
CYAN   <- "#1B9FD8"
CYAN_D <- "#0E7CA8"
GREY   <- "#F0F2F4"
DARK   <- "#1A1A1A"
WHITE  <- "#FFFFFF"
GREY_T <- "#6B7075"

FONT <- "Arial"

## ---------------------------------------------------------------- geometry
X_SPINE   <- 7.0
X_HDR_L   <- 2.0
X_HDR_R   <- 94.0
X_ITEM_L  <- 22.0
X_ITEM_R  <- 94.0

H_HDR     <- 7.0
G_HDR     <- 2.0
H_ITEM    <- 4.3
G_ITEM    <- 1.7
G_SECT    <- 2.8
H_GRID    <- 5.6

## ---------------------------------------------------------------- helpers
rr <- function(x0, y0, x1, y1, r, col = NA, border = NA, lwd = 1) {
  arc <- function(cx, cy, r, a0, a1, n = 16) {
    a <- seq(a0, a1, length.out = n)
    cbind(cx + r * cos(a), cy + r * sin(a))
  }
  r <- min(r, (x1 - x0) / 2, (y1 - y0) / 2)
  pts <- rbind(
    arc(x0 + r, y0 + r, r, pi,       1.5 * pi),
    arc(x1 - r, y0 + r, r, 1.5 * pi, 2 * pi),
    arc(x1 - r, y1 - r, r, 0,        0.5 * pi),
    arc(x0 + r, y1 - r, r, 0.5 * pi, pi)
  )
  polygon(pts[, 1], pts[, 2], col = col, border = border, lwd = lwd)
}

arrow_down <- function(x, ytop, h = 1.5, w = 1.4, col = CYAN) {
  polygon(x + c(-w / 2, w / 2, 0), ytop + c(0, 0, -h), col = col, border = col)
}

## ---------------------------------------------------------------- icons
icon_search <- function(cx, cy, s) {
  r <- 0.40 * s
  a <- seq(0, 2 * pi, length.out = 48)
  lines(cx - 0.12 * s + r * cos(a), cy + 0.14 * s + r * sin(a), col = WHITE, lwd = 1.9)
  segments(cx + 0.17 * s, cy - 0.18 * s, cx + 0.50 * s, cy - 0.54 * s,
           col = WHITE, lwd = 2.1)
}

icon_checklist <- function(cx, cy, s) {
  rr(cx - 0.48 * s, cy - 0.55 * s, cx + 0.48 * s, cy + 0.55 * s,
     0.10 * s, col = NA, border = WHITE, lwd = 1.8)
  for (k in c(0.28, 0, -0.28)) {
    segments(cx - 0.31 * s, cy + k * s, cx - 0.20 * s, cy + k * s, col = WHITE, lwd = 1.6)
    segments(cx - 0.11 * s, cy + k * s, cx + 0.34 * s, cy + k * s, col = WHITE, lwd = 1.6)
  }
}

icon_layers <- function(cx, cy, s) {
  for (k in c(0.30, 0, -0.30)) {
    polygon(cx + c(-0.44, 0, 0.44, 0) * s,
            cy + c(0, 0.19, 0, -0.19) * s + k * s,
            col = NA, border = WHITE, lwd = 1.8)
  }
}

icon_archive <- function(cx, cy, s) {
  rr(cx - 0.48 * s, cy - 0.52 * s, cx + 0.48 * s, cy + 0.52 * s,
     0.10 * s, col = NA, border = WHITE, lwd = 1.8)
  segments(cx - 0.26 * s, cy - 0.30 * s, cx + 0.26 * s, cy - 0.30 * s,
           col = WHITE, lwd = 1.8)
  segments(cx, cy - 0.24 * s, cx, cy + 0.16 * s, col = WHITE, lwd = 2.1)
  polygon(cx + c(-0.16, 0.16, 0) * s, cy + c(0.12, 0.12, 0.36) * s,
          col = WHITE, border = WHITE)
}

## ---------------------------------------------------------------- content
STEPS <- list(
  list(n = 1, title = "Dataset identification", icon = icon_search,
       items = c("Screen national and international geodata services and the literature",
                 "Compile a candidate layer list with an initial licence check")),
  list(n = 2, title = "Dataset selection", icon = icon_checklist,
       criteria = TRUE,
       items = c("Ecological relevance", "China-wide coverage",
                 "Native resolution at least as fine as 1 km")),
  list(n = 3, title = "Layer processing", icon = icon_layers,
       grid = c("Rasterise vector sources", "Reproject to China_Albers",
                "Resample to the 1 km grid", "One-hot encode categories"),
       items = c("Area-weighted aggregation; focal 1/5/10/20 km; distances",
                 "Mask to the national boundary (all_touched)",
                 "Unify float32 and \u22129999; atomic write")),
  list(n = 4, title = "Publication", icon = icon_archive,
       items = c("SHA-256 manifest (21,118); provenance (21,118 \u00d7 21 fields)",
                 "Variable dictionary (21,110 rows); per-layer licence matrix",
                 "Every delivered file is verifiable at the byte level"))
)

h_of <- function(st) {
  h <- H_HDR + G_HDR
  if (!is.null(st$grid)) h <- h + 2 * H_GRID + 2 * G_ITEM
  h + length(st$items) * H_ITEM + (length(st$items) - 1) * G_ITEM
}
H <- 2 + sum(vapply(STEPS, h_of, 0)) + G_SECT * (length(STEPS) - 1) + 13 + 2

## ---------------------------------------------------------------- draw
draw <- function() {
  par(mar = c(0, 0, 0, 0), family = FONT)
  plot(NA, xlim = c(0, 100), ylim = c(0, H), axes = FALSE, xlab = "", ylab = "")

  y <- H - 2

  # ---- 宽度自检：任何文字超出其容器即停止，避免静默溢出 ----
  {
    op0 <- par(usr = c(0, 100, 0, H))
    avail_item <- 72 - 4.0            # 子项框内可用宽度（留两侧内边距）
    for (st in STEPS) {
      for (tx in st$items) {
        w <- strwidth(tx, cex = 0.86, family = FONT)
        if (w > avail_item) stop(sprintf("文字超出子项框 %.1f > %.1f: %s", w, avail_item, tx))
      }
      if (!is.null(st$grid)) {
        mid_w <- (X_ITEM_R - X_ITEM_L) / 2 - 0.8 - 1.2
        for (tx in st$grid) {
          w <- strwidth(tx, cex = 0.92, family = FONT)
          if (w > mid_w) stop(sprintf("文字超出网格框 %.1f > %.1f: %s", w, mid_w, tx))
        }
      }
    }
    par(op0)
  }

  ytmp <- y
  for (st in STEPS) ytmp <- ytmp - h_of(st) - G_SECT
  y_bottom <- ytmp + G_SECT + G_ITEM
  segments(X_SPINE, y, X_SPINE, y_bottom, col = CYAN, lwd = 3.2)

  for (i in seq_along(STEPS)) {
    st <- STEPS[[i]]

    # ---------------- header pill ----------------
    y_hdr_top <- y
    y_hdr_bot <- y - H_HDR
    rr(X_HDR_L, y_hdr_bot, X_HDR_R, y_hdr_top, H_HDR / 2, col = BLACK, border = BLACK)
    if (i > 1) arrow_down(X_SPINE, y_hdr_top + 0.28, h = 1.35, w = 1.35, col = CYAN)

    text(X_HDR_L + 5.2, y_hdr_top - H_HDR / 2, sprintf("%d", st$n),
         cex = 1.62, font = 2, col = WHITE, family = FONT)
    text(X_HDR_L + 9.2, y_hdr_top - H_HDR / 2, st$title,
         cex = 1.40, font = 2, col = WHITE, family = FONT, adj = c(0, 0.5))
    st$icon(X_HDR_R - 5.0, (y_hdr_top + y_hdr_bot) / 2, 2.85)

    y <- y_hdr_bot - G_HDR

    # ---------------- criteria side panel ----------------
    if (isTRUE(st$criteria)) {
      panel_top <- y + 1.5
      panel_bot <- y - (length(st$items) * H_ITEM +
                        (length(st$items) - 1) * G_ITEM) - 1.5
      rect(1.2, panel_bot, X_HDR_R, panel_top, col = GREY, border = NA)
      text(4.6, (panel_top + panel_bot) / 2, "CRITERIA", srt = 90, cex = 0.82,
           font = 2, col = GREY_T, family = FONT)
    }

    # ---------------- 2x2 outline grid ----------------
    if (!is.null(st$grid)) {
      g_l <- X_ITEM_L; g_r <- X_ITEM_R
      mid <- (g_l + g_r) / 2
      top_y <- y
      bot_y <- y - 2 * H_GRID - G_ITEM
      top_c <- top_y - H_GRID / 2
      bot_c <- bot_y + H_GRID / 2
      x_br <- X_ITEM_L - 2.2

      segments(X_SPINE, top_c, x_br, top_c, col = CYAN, lwd = 2.8)
      segments(x_br, bot_c, x_br, top_c, col = CYAN, lwd = 2.8)
      segments(x_br, top_c, g_l, top_c, col = CYAN, lwd = 2.8)
      segments(x_br, bot_c, g_l, bot_c, col = CYAN, lwd = 2.8)
      segments(mid - 0.7, top_c, mid + 0.7, top_c, col = CYAN, lwd = 2.2)
      segments(mid - 0.7, bot_c, mid + 0.7, bot_c, col = CYAN, lwd = 2.2)

      boxes <- list(
        c(g_l, top_y - H_GRID, mid - 0.8, top_y),
        c(mid + 0.8, top_y - H_GRID, g_r, top_y),
        c(g_l, bot_y, mid - 0.8, bot_y + H_GRID),
        c(mid + 0.8, bot_y, g_r, bot_y + H_GRID)
      )
      for (k in seq_along(boxes)) {
        b <- boxes[[k]]
        rr(b[1], b[2], b[3], b[4], 0.7, col = WHITE, border = CYAN_D, lwd = 1.5)
        text((b[1] + b[3]) / 2, (b[2] + b[4]) / 2, st$grid[k],
             cex = 0.92, col = DARK, family = FONT)
      }
      y <- bot_y - G_ITEM
    }

    # ---------------- output boxes ----------------
    for (k in seq_along(st$items)) {
      y_top <- y
      y_bot <- y - H_ITEM
      rr(X_ITEM_L, y_bot, X_ITEM_R, y_top, 0.55, col = CYAN, border = CYAN)
      segments(X_SPINE, (y_top + y_bot) / 2, X_ITEM_L, (y_top + y_bot) / 2,
               col = CYAN, lwd = 2.8)
      text(X_ITEM_L + 2.0, (y_top + y_bot) / 2, st$items[k],
           cex = 0.86, col = WHITE, family = FONT, adj = c(0, 0.5))
      y <- y_bot - G_ITEM
    }

    y <- y - G_SECT + G_ITEM
  }

  arrow_down(X_SPINE, y_bottom + 1.0, h = 1.55, w = 1.55, col = CYAN)

  # ---------------- summary band ----------------
  band_top <- y - G_SECT + G_ITEM - 1.2
  band_bot <- 2.0
  rect(X_HDR_L, band_bot, X_HDR_R, band_top, col = BLACK, border = NA)
  text(52, (band_top + band_bot) / 2 + 2.0,
       "8 themes \u00b7 21 datasets \u00b7 21,110 layers \u00b7 170.9 GB",
       cex = 1.30, font = 2, col = WHITE, family = FONT)
  text(52, (band_top + band_bot) / 2 - 2.2,
       "China_Albers \u00b7 1,000 m \u00b7 4,861 \u00d7 4,062 \u00b7 9,490,310 cells inside China (48.1%)",
       cex = 0.88, col = "#C9CDD1", family = FONT)
}

## ---------------------------------------------------------------- export
W_IN <- 180 / 25.4
H_IN <- W_IN * H / 100

cat(sprintf("canvas 100 x %d units -> %.2f x %.2f in\n", round(H), W_IN, H_IN))

invisible(png(file.path(OUT, "fig01_workflow_v2.png"),
              width = W_IN, height = H_IN, units = "in", res = 640,
              bg = "white", type = "cairo"))
draw(); invisible(dev.off())

invisible(cairo_pdf(file.path(OUT, "fig01_workflow_v2.pdf"),
                    width = W_IN, height = H_IN, bg = "white"))
draw(); invisible(dev.off())

cat("wrote fig01_workflow_v2.png / .pdf\n")
