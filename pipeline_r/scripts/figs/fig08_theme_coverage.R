# R/figs/fig08_theme_coverage.R
# Fig. 8: temporal coverage of every dataset, grouped by theme.
#
# Why this figure: Table 1 lists the coverage of 25 dataset entries as prose, which
# is slow to read and hides the pattern the paper needs to make — some themes carry
# historical series, others only static layers or scenario points.
#
# The intervals below are the ones verified against the delivery by
# R/tools/check_table2.R (25/25). Keep them in step with paper_content_zh.py.
#
# Usage: Rscript R/figs/fig08_theme_coverage.R

root <- Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM")
out_dir <- file.path(root, "00_docs", "SUBMISSION", "figures")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- coverage table -----------------------------------------------------------
# kind: "obs" = observed series, "scen" = scenario / projection,
#       "pt" = discrete epochs, "static" = no time dimension
# year: for a static layer, the reference year when the product documents one
rows <- list(
  list(theme = "lulc",    name = "hlu1km",                    kind = "obs",    span = c(1960, 2020), pts = NULL, year = NA),
  list(theme = "lulc",    name = "hlu1km (SSP-RCP)",          kind = "scen",   span = c(2021, 2100), pts = NULL, year = NA),
  list(theme = "lulc",    name = "clcd",                      kind = "obs",    span = c(2000, 2025), pts = NULL, year = NA),
  list(theme = "lulc",    name = "glu1km",                    kind = "pt",     span = NULL, pts = c(2020, 2030, 2050, 2100), year = NA),
  list(theme = "bioclim", name = "chelsa21",                  kind = "static", span = NULL, pts = NULL, year = NA),
  list(theme = "bioclim", name = "chelsa21 (5-GCM ensmean)",  kind = "pt",     span = NULL, pts = c(2025, 2055, 2085), year = NA),
  list(theme = "bioclim", name = "chelsa21 (single GCM)",     kind = "pt",     span = NULL, pts = c(2025, 2055, 2085), year = NA),
  list(theme = "soil",    name = "csdlv2",                    kind = "static", span = NULL, pts = NULL, year = NA),
  list(theme = "anthro",  name = "hfp",                       kind = "obs",    span = c(2000, 2024), pts = NULL, year = NA),
  list(theme = "anthro",  name = "smod",                      kind = "pt",     span = NULL, pts = seq(1975, 2030, by = 5), year = NA),
  list(theme = "hydro",   name = "h90m",                      kind = "static", span = NULL, pts = NULL, year = NA),
  list(theme = "hydro",   name = "hydrosheds",                kind = "static", span = NULL, pts = NULL, year = NA),
  list(theme = "vege",    name = "glassndvi",                 kind = "obs",    span = c(2020, 2022), pts = NULL, year = NA),
  list(theme = "vege",    name = "catcd",                     kind = "obs",    span = c(1985, 2025), pts = NULL, year = NA),
  list(theme = "vege",    name = "ch2019 (canopy height)",    kind = "static", span = NULL, pts = NULL, year = 2019),
  list(theme = "vege",    name = "agb2019 (biomass)",         kind = "static", span = NULL, pts = NULL, year = 2019),
  list(theme = "dist",    name = "roads, water, trails",      kind = "static", span = NULL, pts = NULL, year = NA),
  list(theme = "topo",    name = "chinadem",                  kind = "static", span = NULL, pts = NULL, year = NA)
)

n <- length(rows)
themes <- unique(vapply(rows, `[[`, "", "theme"))

# lay rows out top-down, inserting a gap between theme blocks
GAP <- 1.05
ypos <- numeric(n)
cur <- 0
prev <- ""
for (i in seq_len(n)) {
  if (rows[[i]]$theme != prev && prev != "") cur <- cur + GAP
  cur <- cur + 1
  ypos[i] <- cur
  prev <- rows[[i]]$theme
}
ypos <- (max(ypos) + min(ypos)) - ypos   # first row on top
YTOP <- max(ypos)

col_obs <- "#2C5985"
col_scen <- "#9ECAE1"
col_pt <- "#2C5985"
col_static <- "#C8C8C8"
col_rule <- "#EDEDED"
col_theme <- "#4D4D4D"

XLIM <- c(1955, 2110)
STATIC_X <- 2096

draw <- function() {
  op <- par(mar = c(3.6, 13.4, 1.2, 1.2), mgp = c(2.1, 0.45, 0), las = 1,
            xaxs = "i", yaxs = "i", family = "sans")
  on.exit(par(op), add = TRUE)

  plot(NA, xlim = XLIM, ylim = c(0.2, YTOP + 3.4), axes = FALSE, xlab = "", ylab = "")

  segments(1960, ypos, 2100, ypos, col = col_rule, lwd = 0.6)
  abline(v = 2020, lty = 3, lwd = 1.0, col = "#8C8C8C")

  for (i in seq_len(n)) {
    r <- rows[[i]]; y <- ypos[i]
    if (!is.null(r$span)) {
      x0 <- max(r$span[1], 1960); x1 <- min(r$span[2], 2100)
      rect(x0, y - 0.22, x1, y + 0.22,
           col = if (r$kind == "obs") col_obs else col_scen, border = NA)
    }
    if (!is.null(r$pts)) {
      pts <- r$pts[r$pts >= 1960 & r$pts <= 2100]
      segments(min(pts), y, max(pts), y, col = col_pt, lwd = 0.7)
      points(pts, rep(y, length(pts)), pch = 21, bg = "white", col = col_pt,
             cex = 0.72, lwd = 0.9)
    }
    if (r$kind == "static") {
      if (is.na(r$year)) {
        points(STATIC_X, y, pch = 22, bg = col_static, col = "#6E6E6E", cex = 1.05)
      } else {
        points(r$year, y, pch = 22, bg = col_static, col = "#6E6E6E", cex = 1.05)
      }
    }
  }

  # theme brackets and labels
  for (th in themes) {
    idx <- which(vapply(rows, `[[`, "", "theme") == th)
    yy <- ypos[idx]
    segments(1958.5, min(yy) - 0.34, 1958.5, max(yy) + 0.34, lwd = 2.0, col = col_theme)
    mtext(th, side = 2, at = mean(range(yy)), line = 11.9, cex = 0.78, las = 0,
          col = col_theme)
  }

  axis(2, at = ypos, labels = vapply(rows, `[[`, "", "name"), tick = FALSE,
       cex.axis = 0.72, line = -0.5)
  axis(1, at = seq(1960, 2100, 20), cex.axis = 0.8, tcl = -0.3)
  mtext("Year", side = 1, line = 2.0, cex = 0.86)
  mtext("present", side = 3, at = 2020, cex = 0.66, line = 0.2, col = "#555555")
  mtext("no time dimension", side = 3, at = STATIC_X, cex = 0.66, line = 0.2,
        col = "#555555")

  legend(x = 1958, y = YTOP + 3.25, xjust = 0, yjust = 1, ncol = 2, bty = "n",
         cex = 0.72, seg.len = 1.5, x.intersp = 0.7, y.intersp = 1.05,
         legend = c("observed series", "scenario / projection", "epochs",
                    "static layer"),
         pch = c(NA, NA, 21, 22), lty = c(1, 1, NA, NA), lwd = c(6, 6, NA, NA),
         pt.bg = c(NA, NA, "white", col_static),
         pt.cex = c(NA, NA, 0.8, 1.0),
         col = c(col_obs, col_scen, col_pt, "#6E6E6E"))
}

for (dev in c("png", "pdf")) {
  f <- file.path(out_dir, paste0("fig08_theme_coverage.", dev))
  if (dev == "png") {
    png(f, width = 7.0, height = 5.2, units = "in", res = 600, bg = "white")
  } else {
    pdf(f, width = 7.0, height = 5.2, bg = "white")
  }
  draw()
  dev.off()
  cat("written:", f, "\n")
}
