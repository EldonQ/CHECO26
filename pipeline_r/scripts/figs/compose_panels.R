# R/figs/compose_panels.R
# 把 geo-viz 单独渲染的国家尺度图合成为论文用的多联图。
#
# 为什么不在一张图里直接画三联：
#   geo-viz 的版面（主图 + 右侧色标 + 右下南海小图）是按单图设计的固定比例。
#   单图渲染再拼接，可以保证每一联都带完整色标与南海小图，不必改技能本体的版面逻辑。
#
# 输入：00_docs/SUBMISSION/figures/ 下 geo-viz 输出的单图 PNG（600 dpi）
# 输出：fig02_landcover_triptych.{png,pdf}、fig06_anthropogenic_pair.{png,pdf}
#
# 用法：Rscript R/figs/compose_panels.R
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
suppressMessages(library(grid))

FIGD <- file.path(PATH_DOCS(), "SUBMISSION", "figures")
stopifnot(dir.exists(FIGD))

# ---- 拼图 ----
# panels: 文件基名（不含 .png）；
# labels: 子图标签；out: 输出基名；W/H: 画布英寸；dpi: 输出分辨率
compose <- function(panels, labels, out, W, H, dpi = 400,
                    gap = 0.12, lab_cex = 1.5, top = 0.22, bottom = 0.10,
                    margin = 0.10) {
  files <- file.path(FIGD, paste0(panels, ".png"))
  miss <- panels[!file.exists(files)]
  if (length(miss)) stop("缺少单图: ", paste(miss, collapse = ", "))
  imgs <- lapply(files, function(f) png::readPNG(f))

  # 2026-10-21 修：
  #   1) 原来 w_cell 是标量却写 w_cell[i]，i>=2 时为 NA，后几联画不出来；
  #   2) 原来直接在 npc 里布局，而 npc 在非方形画布上不等比，会把图压扁。
  # 改为：先在**英寸**里算每联的宽高与位置，再除以 W/H 换成 npc。
  draw <- function() {
    grid.newpage()
    pushViewport(viewport(xscale = c(0, 1), yscale = c(0, 1)))
    grid.rect(gp = gpar(fill = "white", col = NA))

    n <- length(imgs)
    ar <- vapply(imgs, function(im) dim(im)[2] / dim(im)[1], 0)   # 宽/高
    avail_w_in <- W - 2 * margin - (n - 1) * gap
    avail_h_in <- H - top - bottom
    # 注意：w_in 必须是长度 n 的向量。写成标量时 w_in[i]（i>=2）为 NA，
    # 会让后几联的宽度与 x 位置都变成 NA，画不出来且不报错。
    w_in <- rep(avail_w_in / n, n)
    h_in <- w_in / ar
    if (any(h_in > avail_h_in)) {          # 太高则以高度为准
      h_in <- rep(avail_h_in, n)
      w_in <- h_in * ar
    }
    for (i in seq_len(n)) {
      x_in <- margin + (i - 1) * (avail_w_in / n + gap) + (avail_w_in / n - w_in[i]) / 2
      y_in <- bottom + (avail_h_in - h_in[i]) / 2
      grid.raster(imgs[[i]],
                  x = unit((x_in + w_in[i] / 2) / W, "npc"),
                  y = unit((y_in + h_in[i] / 2) / H, "npc"),
                  width = unit(w_in[i] / W, "npc"),
                  height = unit(h_in[i] / H, "npc"),
                  interpolate = TRUE)
      if (!is.null(labels) && nzchar(labels[i])) {
        grid.text(labels[i],
                  x = unit((x_in + 0.04) / W, "npc"),
                  y = unit((y_in + h_in[i] - 0.04) / H, "npc"),
                  just = c("left", "top"),
                  gp = gpar(fontsize = 13 * lab_cex, fontface = 2, col = "grey10"))
      }
    }
    popViewport()
  }

  png_out <- file.path(FIGD, paste0(out, ".png"))
  pdf_out <- file.path(FIGD, paste0(out, ".pdf"))
  grDevices::png(png_out, width = W, height = H, units = "in", res = dpi,
                 bg = "white", type = "cairo")
  draw(); grDevices::dev.off()
  grDevices::pdf(pdf_out, width = W, height = H, bg = "white")
  draw(); grDevices::dev.off()
  cat(sprintf("  已写出 %s (.png/.pdf)  %d 联\n", out, length(panels)))
}

# Fig. 2：CLCD 三类的面积占比（3 联）
compose(c("fig02a_cropland2000", "fig02b_forest2000", "fig02c_impervious2000"),
        c("(a)", "(b)", "(c)"),
        "fig02_landcover_triptych", W = 15.0, H = 4.35)

# Fig. 6：人类足迹与城市面积占比（2 联）
compose(c("fig06a_hfp2020", "fig06b_urban2020"),
        c("(a)", "(b)"),
        "fig06_anthropogenic_pair", W = 10.2, H = 4.35)

cat("拼图完成。\n")

# 缩略图（仅用于快速核对版面，不进论文）
thumb <- function(base, w = 1400) {
  f <- file.path(FIGD, paste0(base, ".png"))
  im <- png::readPNG(f); h <- round(dim(im)[1] * w / dim(im)[2])
  grDevices::png(file.path(FIGD, paste0("_thumb_", base, ".png")),
                 width = w, height = h, res = 96, bg = "white")
  graphics::par(mar = c(0,0,0,0)); graphics::plot.new()
  graphics::plot.window(c(0,1), c(0,1))
  graphics::rasterImage(im, 0, 0, 1, 1, interpolate = TRUE)
  grDevices::dev.off()
}
thumb("fig02_landcover_triptych")
thumb("fig06_anthropogenic_pair")
cat("缩略图已写出。\n")
