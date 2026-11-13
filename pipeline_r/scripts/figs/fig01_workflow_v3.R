# R/figs/fig01_workflow_v3.R
# Fig. 1 (v3): CHECO26 development workflow, landscape timeline.
#
# Same four stages as before, drawn as a top-to-bottom timeline: a numbered rail on
# the left, a bold stage title, and the stage's tasks as square chips. Deliberately
# unlike the vertical pill-and-bar diagram used elsewhere: no icons, no rounded
# black headers, no branch spine on the right.
#
# The canvas height is derived from the content, so nothing can collide with the
# summary band at the bottom.
#
# v2 (fig01_workflow_v2.R / .png) is left untouched; this script writes new files.
#
# Usage: Rscript R/figs/fig01_workflow_v3.R

root <- Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM")
out_dir <- file.path(root, "00_docs", "SUBMISSION", "figures")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- palette ---------------------------------------------------------------
INK     <- "#12312F"
RAIL    <- "#0F5257"
ACCENT  <- "#C8862B"
CHIP_BG <- "#F5F1E8"
CHIP_BD <- "#D9D0BF"
CRIT_BG <- "#FFFFFF"
CRIT_BD <- "#0F5257"
TXT     <- "#1F1F1F"
MUTED   <- "#4A4A4A"
BAND_BG <- "#0F5257"

# ---- content ---------------------------------------------------------------
STAGES <- list(
  list(title = "Identify",
       note  = "what is already published, and on what terms",
       rows  = list(c("Review national and international data services",
                      "Compile candidates and check each licence"))),
  list(title = "Select",
       note  = "three tests every candidate must pass",
       rows  = list(c("Ecologically meaningful", "Covers all of China",
                      "At least as fine as 1 km")),
       criteria = TRUE),
  list(title = "Harmonise",
       note  = "the decisions the sources leave to the user",
       rows  = list(c("Vectors to raster", "One projection", "One resolution"),
                    c("Categories become continuous shares",
                      "Neighbourhood context at four scales",
                      "Distance to water and roads"),
                    c("Clip to the national boundary",
                      "One data type, one no-data value"))),
  list(title = "Publish",
       note  = "so that others can rebuild and verify",
       rows  = list(c("Variable dictionary and licence for every layer",
                      "Checksums for every delivered file")))
)

# ---- geometry (centimetres) ------------------------------------------------
W        <- 16.6
RAIL_X   <- 1.05
CHIP_X0  <- 1.95
CHIP_X1  <- W - 0.45
TITLE_H  <- 0.86
CHIP_H   <- 0.72
ROW_GAP  <- 0.14
STAGE_GAP <- 0.46
TOP_PAD  <- 0.40
BOT_PAD  <- 0.34

stage_h <- vapply(STAGES, function(st) {
  n <- length(st$rows)
  TITLE_H + n * CHIP_H + (n - 1) * ROW_GAP
}, 0)
body_h <- sum(stage_h) + STAGE_GAP * (length(STAGES) - 1)
H      <- BOT_PAD + body_h + TOP_PAD

# ---- drawing ---------------------------------------------------------------
wrap2 <- function(s, maxchars) {
  words <- strsplit(s, " ")[[1]]
  if (length(words) < 2 || nchar(s) <= maxchars) return(s)
  # split at the word boundary that balances the two lines best
  best <- NA_integer_; best_w <- Inf
  for (k in seq_len(length(words) - 1L)) {
    a <- paste(words[1:k], collapse = " ")
    b <- paste(words[(k + 1L):length(words)], collapse = " ")
    w <- max(nchar(a), nchar(b))
    if (w < best_w) { best_w <- w; best <- k }
  }
  c(paste(words[1:best], collapse = " "),
    paste(words[(best + 1L):length(words)], collapse = " "))
}

draw <- function() {
  par(mar = c(0, 0, 0, 0), ps = 9, family = "sans", xaxs = "i", yaxs = "i")
  plot(NA, xlim = c(0, W), ylim = c(0, H), axes = FALSE, xlab = "", ylab = "")

  top <- H - TOP_PAD
  rail_bot <- top - body_h
  segments(RAIL_X, rail_bot, RAIL_X, top, col = RAIL, lwd = 2.0)

  y_cursor <- top
  for (i in seq_along(STAGES)) {
    st <- STAGES[[i]]
    y0 <- y_cursor
    y_center <- y0 - TITLE_H / 2

    symbols(RAIL_X, y_center, circles = 0.30, inches = FALSE, add = TRUE,
            bg = ACCENT, fg = ACCENT)
    text(RAIL_X, y_center, i, col = "white", cex = 1.02, font = 2)

    text(RAIL_X + 0.52, y_center, st$title, adj = c(0, 0.5), col = INK,
         cex = 1.34, font = 2)
    if (!is.null(st$note)) {
      text(CHIP_X1, y_center, st$note, adj = c(1, 0.5), col = MUTED,
           cex = 0.76, font = 3)
    }

    y_chip_top <- y0 - TITLE_H
    for (r in seq_along(st$rows)) {
      labels <- st$rows[[r]]
      m <- length(labels)
      avail <- CHIP_X1 - CHIP_X0
      gap <- 0.14
      wid <- (avail - gap * (m - 1)) / m
      ytop <- y_chip_top - (r - 1) * (CHIP_H + ROW_GAP)
      ybot <- ytop - CHIP_H
      for (k in seq_along(labels)) {
        x0 <- CHIP_X0 + (k - 1) * (wid + gap)
        x1 <- x0 + wid
        is_crit <- isTRUE(st$criteria)
        rect(x0, ybot, x1, ytop,
             col = if (is_crit) CRIT_BG else CHIP_BG,
             border = if (is_crit) CRIT_BD else CHIP_BD,
             lwd = 1.0, lty = if (is_crit) 2 else 1)
        if (!is_crit) rect(x0, ybot, x0 + 0.07, ytop, col = RAIL, border = NA)
        lines <- wrap2(labels[k], maxchars = max(18, floor(wid * 6.4)))
        ymid <- (ybot + ytop) / 2
        if (length(lines) == 2) {
          text((x0 + x1) / 2 + 0.03, ymid + 0.155, lines[1], cex = 0.78, col = TXT)
          text((x0 + x1) / 2 + 0.03, ymid - 0.155, lines[2], cex = 0.78, col = TXT)
        } else {
          text((x0 + x1) / 2 + 0.03, ymid, lines[1], cex = 0.78, col = TXT)
        }
      }
    }
    y_cursor <- y0 - stage_h[i] - STAGE_GAP
  }
}

for (dev in c("png", "pdf")) {
  f <- file.path(out_dir, paste0("fig01_workflow_v3.", dev))
  if (dev == "png") {
    png(f, width = W / 2.54, height = H / 2.54, units = "in", res = 600, bg = "white")
  } else {
    pdf(f, width = W / 2.54, height = H / 2.54, bg = "white")
  }
  draw()
  dev.off()
  cat(sprintf("written: %s  (%.1f x %.1f cm)\n", f, W, H))
}
