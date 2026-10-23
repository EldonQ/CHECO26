# R/figs/fig01_workflow.R
# 图 1：CHECO26 建库工作流
#
# 四步流程图：(1) 识别 → (2) 筛选 → (3) 标准化 → (4) 发布。
# 我们做同样四步，但每步都标注**本库实测的数字**，使图本身携带信息而不只是装饰：
#   第 4 步不是"上传 Zenodo"，而是"发布"——附 SHA-256 清单、溯源表、变量字典、许可矩阵。
#
# 2026-10-21 第一版用 grid.roundrect 画圆角框，在非等比例视口里半径被拉成沙漏形、
# 文字也没落位。改为基础图形（rect + text），定位以英寸为单位换算，可控且稳定。
#
# 用法：Rscript R/figs/fig01_workflow.R
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

FIGD <- file.path(PATH_DOCS(), "figures")

# ---- 实测数字（改这里之前先确认磁盘）----
N_LAYERS   <- 21110L
N_THEMES   <- 8L
N_DATASETS <- 21L
N_VALID    <- 9490310L
N_MANIFEST <- 21118L
SIZE_GB    <- 169.4
N_UNIQUE   <- 14047L
THEMES <- data.frame(
  theme = c("lulc", "bioclim", "soil", "anthro", "hydro", "vege", "dist", "topo"),
  n     = c(20150L, 532L, 196L, 137L, 44L, 30L, 17L, 4L),
  stringsAsFactors = FALSE)
stopifnot(sum(THEMES$n) == N_LAYERS, nrow(THEMES) == N_THEMES)
fmt <- function(x) format(x, big.mark = ",", scientific = FALSE)

W_IN <- 13; H_IN <- 5.9

draw <- function() {
  graphics::par(mar = c(0, 0, 0, 0), oma = c(0, 0, 0, 0), xpd = NA, ps = 10)
  graphics::plot.new()
  # 用英寸做用户坐标，避免纵横比例失真
  graphics::plot.window(xlim = c(0, W_IN), ylim = c(0, H_IN))

  title_y <- H_IN - 0.34
  graphics::text(W_IN/2, title_y, "CHECO26 development workflow",
                 cex = 1.5, font = 2)

  steps <- list(
    list(h = "1  Dataset identification",
         body = c("Screen national and international",
                  "geodata services and the literature",
                  "for China-wide layers that are",
                  "openly licensed and at least as",
                  "fine as 1 km natively.")),
    list(h = "2  Dataset selection",
         body = c("Three criteria: ecological",
                  "relevance, national coverage,",
                  "native resolution not coarser",
                  "than the target grid.",
                  sprintf("%d datasets qualified.", N_DATASETS))),
    list(h = "3  Layer processing",
         body = c("Reproject and resample onto",
                  "one grid; one-hot encode",
                  "categorical sources; focal,",
                  "distance, proportion and",
                  "landscape metrics; mask.")),
    list(h = "4  Release",
         body = c(sprintf("%s SHA-256 digests", fmt(N_MANIFEST)),
                  sprintf("%s provenance rows", fmt(N_MANIFEST)),
                  sprintf("%s dictionary rows", fmt(N_LAYERS)),
                  "per-layer licence matrix,",
                  "byte-level verification."))
  )

  n <- length(steps); gap <- 0.34
  bw <- (W_IN - 2*0.30 - (n - 1)*gap) / n
  bx <- 0.30 + (seq_len(n) - 1) * (bw + gap)
  btop <- title_y - 0.38
  bh <- 1.92; hdr <- 0.32

  for (i in seq_len(n)) {
    xl <- bx[i]; xr <- xl + bw; yb <- btop - bh
    graphics::rect(xl, yb, xr, btop, col = "grey97", border = "grey35", lwd = 1.1)
    graphics::rect(xl, btop - hdr, xr, btop, col = "#E3EBF3", border = "grey35", lwd = 1.1)
    graphics::text((xl + xr)/2, btop - hdr/2, steps[[i]]$h, cex = 0.84, font = 2)
    yy <- btop - hdr - 0.24
    for (ln in steps[[i]]$body) {
      graphics::text(xl + 0.09, yy, ln, adj = c(0, 0.5), cex = 0.66, col = "grey20")
      yy <- yy - 0.255
    }
    if (i < n) {
      graphics::arrows(xr + 0.05, btop - bh/2, bx[i + 1] - 0.05, btop - bh/2,
                       length = 0.09, lwd = 1.5, col = "grey30")
    }
  }

  # ---- 网格条 ----
  ybar <- btop - bh - 0.42
  graphics::text(W_IN/2, ybar,
    sprintf(paste0("One grid for every layer:  China_Albers  |  1,000 m cells  |  ",
                   "4,861 x 4,062 grid  |  %s cells inside China (48.1%%)  |  ",
                   "%s layers  |  %.1f GB"),
            fmt(N_VALID), fmt(N_LAYERS), SIZE_GB),
    cex = 0.78, col = "grey15")

  # ---- 主题构成：8 个等宽单元格（长度编码在这里无意义，lulc 占 95.5%）----
  graphics::text(W_IN/2, ybar - 0.40, "Theme composition",
                 cex = 0.82, font = 2, col = "grey20")
  k <- nrow(THEMES)
  cw <- (W_IN - 0.60) / k
  cy <- ybar - 1.30; chh <- 0.46
  pal <- c("#2C6E49", "#4C9F70", "#88B04B", "#D9A441", "#C97B3C",
           "#8C6D62", "#6C7A89", "#A6A6A6")
  for (i in seq_len(k)) {
    xa <- 0.30 + (i - 1)*cw
    graphics::rect(xa, cy, xa + cw - 0.04, cy + chh, col = pal[i], border = "white", lwd = 1)
    graphics::text((xa*2 + cw - 0.04)/2, cy + chh*0.66, THEMES$theme[i],
                   cex = 0.66, col = "white", font = 2)
    graphics::text((xa*2 + cw - 0.04)/2, cy + chh*0.28, fmt(THEMES$n[i]),
                   cex = 0.62, col = "white")
  }
  graphics::text(W_IN/2, cy - 0.26,
                 sprintf("%d themes  |  %d datasets  |  %s layers",
                         N_THEMES, N_DATASETS, fmt(N_LAYERS)),
                 cex = 0.74, col = "grey25")

  graphics::text(W_IN/2, 0.30,
    sprintf("Counts are pre-deduplication; %s of the %s layers (66.5%%) are distinct at the byte level.",
            fmt(N_UNIQUE), fmt(N_LAYERS)),
    cex = 0.63, col = "grey35", font = 3)
}

png_path <- file.path(FIGD, "fig01_workflow.png")
pdf_path <- file.path(FIGD, "fig01_workflow.pdf")

grDevices::png(png_path, width = W_IN, height = H_IN, units = "in", res = 600,
               bg = "white", type = "cairo")
draw(); grDevices::dev.off()
grDevices::pdf(pdf_path, width = W_IN, height = H_IN, bg = "white")
draw(); grDevices::dev.off()

cat(sprintf("已写出 %s (.png/.pdf)\n", "fig01_workflow"))
cat(sprintf("  层数 %s ; 主题 %d ; 数据集 %d ; 有效像元 %s ; 体积 %.1f GB ; 唯一 %s\n",
            fmt(N_LAYERS), N_THEMES, N_DATASETS, fmt(N_VALID), SIZE_GB, fmt(N_UNIQUE)))

