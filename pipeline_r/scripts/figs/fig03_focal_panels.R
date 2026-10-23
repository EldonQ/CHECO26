# R/figs/fig03_focal_panels.R
# Fig. 3: 多尺度焦点层对比 —— 一个基底 + 四个半径，局部放大
# 用 hlu1km 2020 urban 比例（空间纹理清晰，适合展示平滑效果）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
suppressPackageStartupMessages(library(grDevices))

OUT <- file.path(PATH_DOCS(), "figures")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

YEAR <- if (length(commandArgs(TRUE))) as.integer(commandArgs(TRUE)[1]) else 2007L
base_parts <- c("glo", "lulc", "hlu1km", as.character(YEAR), "urban")
FS <- FOCAL_SPEC()

# ---- 选定放大窗口：北京-天津-河北（urban 纹理最丰富）----
lon <- 116.0; lat <- 39.2; half <- 90000   # 180 km × 180 km 窗口
pt <- terra::vect(data.frame(x = lon, y = lat),
                  geom = c("x", "y"), crs = "EPSG:4326")
# 用模板的 Albers 投影
tmpl <- terra::rast(PATH_TEMPLATE())
pt_al <- terra::project(pt, terra::crs(tmpl))
xy <- terra::crds(pt_al)
cat(sprintf("中心点 Albers 坐标: (%.0f, %.0f)\n", xy[1, 1], xy[1, 2]))
win <- terra::ext(xy[1, 1] - half, xy[1, 1] + half, xy[1, 2] - half, xy[1, 2] + half)

# ---- 读取并裁剪 5 个层 ----
read_crop <- function(suffix) {
  p <- layer_path(base_parts, paste0("_prop", suffix))
  if (!file.exists(p)) return(NULL)
  r <- terra::rast(p)
  terra::crop(r, win, snap = "out")
}
layers <- list(read_crop(""))
for (k in seq_len(nrow(FS))) layers[[k + 1]] <- read_crop(FS$suffix[k])   # FS$suffix 已含前导 _
labels <- c("Base (1 km)", sprintf("%d km (n=%d)", FS$radius_km, FS$size))
keep <- !vapply(layers, is.null, TRUE)
layers <- layers[keep]; labels <- labels[keep]
cat(sprintf("可用面板: %d / 5\n", length(layers)))
if (!length(layers)) quit(save = "no", status = 1)

# ---- 统一色阶（所有面板共享，才可比）----
vals <- unlist(lapply(layers, function(r) {
  v <- terra::values(r, mat = FALSE); v[is.finite(v)]
}))
lim <- c(0, quantile(vals, 0.995, na.rm = TRUE))
cat(sprintf("共享色阶: [%.3f, %.3f]\n", lim[1], lim[2]))

# ---- 出图 ----
# 2026-10-21：改为把绘图包成函数，分别喂给 png 与 pdf 设备，
# 使每张图同时产出 PNG 与矢量 PDF。（dev.copy2pdf 不能从 png 设备复制。）
# 共用调色板（原在被替换的那段里定义）
pal <- grDevices::hcl.colors(64, "YlGnBu", rev = TRUE)

draw_panels <- function() {
  op <- par(mfrow = c(1, length(layers)), mar = c(0.8, 0.6, 2.2, 0.6),
            oma = c(0, 0, 1.6, 0), mgp = c(1.5, 0.3, 0))
  on.exit(par(op), add = TRUE)
  for (i in seq_along(layers)) {
    terra::plot(layers[[i]], col = pal, range = lim, axes = FALSE, legend = FALSE,
                maxcell = 4e6, mar = NA, colNA = "white",
                main = labels[i], cex.main = 1.15, font.main = 1)
  }
  mtext(sprintf("Urban areal proportion, %d — square-window means, shared colour scale", YEAR),
        outer = TRUE, cex = 1.15, font = 2, line = 0.2)
}

draw_bar <- function() {
  op <- par(mar = c(0.1, 0.1, 0.1, 0.1)); on.exit(par(op), add = TRUE)
  image(matrix(seq(lim[1], lim[2], length.out = 256), 1), col = pal, axes = FALSE,
        xlab = "", ylab = "")
  axis(1, at = seq(0, 1, 0.25),
       labels = sprintf("%.2f", seq(lim[1], lim[2], length.out = 5)),
       cex.axis = 1.0, tick = FALSE, line = -0.8)
  mtext("proportion", side = 1, line = 0.8, cex = 1.0)
}

stem <- sprintf("fig03_focal_panels_%d", YEAR)
invisible(png(file.path(OUT, paste0(stem, ".png")), width = 15, height = 3.6,
              units = "in", res = 600, bg = "white")); draw_panels(); invisible(dev.off())
invisible(pdf(file.path(OUT, paste0(stem, ".pdf")), width = 15, height = 3.6, bg = "white")); draw_panels(); invisible(dev.off())

invisible(png(file.path(OUT, "fig03_colourbar.png"), width = 6, height = 0.9,
              units = "in", res = 600, bg = "white")); draw_bar(); invisible(dev.off())
invisible(pdf(file.path(OUT, "fig03_colourbar.pdf"), width = 6, height = 0.9, bg = "white")); draw_bar(); invisible(dev.off())

cat(sprintf("已写出 %s.png / .pdf 与 fig03_colourbar.png / .pdf\n", stem))
cat(sprintf("尺寸: %s\n", paste(vapply(layers, function(r) sprintf("%dx%d",
    terra::ncol(r), terra::nrow(r)), ""), collapse = ", ")))
