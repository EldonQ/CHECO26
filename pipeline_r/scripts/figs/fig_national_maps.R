# R/figs/fig_national_maps.R
# 重建 5 张国家尺度地图（此前是临时生成、无脚本留存）：
#   fig07_clcd_cropland2000.png
#   fig08_clcd_impervious2000.png
#   fig09_clcd_forest2000.png
#   fig_hfp2020.png
#   fig_urban2020_clamped.png
#
# 背景（2026-10-21）：论文需要 9 张图，其中 5 张只有 PNG、没有生成脚本。
# 对 Data Descriptor 来说"图可复现"是硬要求，所以补此脚本。
#
# 约定：
#   · 主图用栅格自身的 Albers 投影绘制（不重采样、不投影栅格）；
#   · 省级边界从 WGS84 转到同一 Albers；
#   · 右下角插南海小图（经纬度坐标，含断续线）；
#   · 输出 300 dpi PNG + 矢量 PDF（便于排版）。
#
# 用法：Rscript R/figs/fig_national_maps.R [which]
#   which = all（默认）| clcd | anthro
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

suppressMessages({ library(sf); library(ggplot2) })

OUT   <- PATH_DOCS()
FIGD  <- file.path(OUT, "figures")
VEC   <- "E:/CHECO26/china"
stopifnot(dir.exists(FIGD))

# ---- 边界 ----
load_vectors <- function(crs_target) {
  cn <- sf::st_read(file.path(VEC, "china.shp"), quiet = TRUE)
  dl <- sf::st_read(file.path(VEC, "dashline.shp"), quiet = TRUE)
  cn_a <- sf::st_transform(cn, crs_target)
  list(cn = cn, cn_a = cn_a, dl = dl)
}

# ---- 主图 ----
# 用 terra::plot 画栅格（它按栅格自身分辨率渲染，不做降采样），
# 再用 sf 叠加边界；比 ggplot + geom_raster 更省内存也更忠实。
plot_national <- function(r, pal, title, legend_title, vmin, vmax,
                          out_stem, vec, insets = TRUE) {
  # 2026-10-21 修：初版用 graphics::lines(st_coordinates(...)) 画小图，
  # 对多条 LINESTRING 会把所有线段端点按顺序连成一条折线（放射状直线）。
  # 改为 par(fig=, new=TRUE) 给小图独立坐标系，再用 plot.sf 画。
  draw_main <- function() {
    terra::plot(r, col = pal, range = c(vmin, vmax), axes = FALSE, mar = NA,
                legend = TRUE, plg = list(title = legend_title, cex = 0.85),
                main = title, cex.main = 1.4)
    plot(sf::st_geometry(vec$cn_a), add = TRUE, border = "grey35", lwd = 0.35)
  }
  draw_inset <- function() {
    # 位置按设备比例给定：右下角，不压住华南陆地
    graphics::par(fig = c(0.735, 0.925, 0.035, 0.315), new = TRUE, mar = c(0, 0, 0, 0))
    graphics::plot(sf::st_geometry(vec$dl), col = "grey20", lwd = 0.65,
                   xlim = c(106.5, 124.5), ylim = c(3, 23.5), axes = FALSE)
    graphics::plot(sf::st_geometry(vec$cn), add = TRUE, border = "grey65", lwd = 0.25)
    graphics::box(col = "grey35", lwd = 0.8)
    graphics::mtext("South China Sea", side = 3, line = -1.2, cex = 0.55, col = "grey25")
    graphics::par(fig = c(0, 1, 0, 1), new = TRUE, mar = c(0, 0, 0, 0))
    graphics::plot.new()
  }

  png_path <- file.path(FIGD, paste0(out_stem, ".png"))
  pdf_path <- file.path(FIGD, paste0(out_stem, ".pdf"))

  grDevices::png(png_path, width = 14, height = 12.4, units = "in", res = 300,
                 bg = "white", type = "cairo")
  op <- graphics::par(no.readonly = TRUE)
  graphics::par(mar = c(0.5, 0.5, 2.2, 4.6))
  draw_main()
  if (insets) draw_inset()
  graphics::par(op)
  grDevices::dev.off()

  grDevices::pdf(pdf_path, width = 14, height = 12.4, bg = "white")
  graphics::par(mar = c(0.5, 0.5, 2.2, 4.6))
  draw_main()
  if (insets) draw_inset()
  grDevices::dev.off()

  cat(sprintf("  已写出 %s (.png/.pdf)\n", out_stem))
}

main <- function(which = "all") {
  crs_a <- terra::crs(terra::rast(file.path(PATH_COV(), "glo/topo/chinadem/elev/glo_topo_chinadem_elev.tif")))
  vec <- load_vectors(crs_a)
  cat(sprintf("边界: %d 省 ; 断续线 %d 条\n", nrow(vec$cn), nrow(vec$dl)))

  if (which %in% c("all", "clcd")) {
    specs <- list(
      list(cl = "cropland",   stem = "fig07_clcd_cropland2000",
           title = "Cropland proportion, 2000 (CLCD 30 m -> 1 km)",
           pal = grDevices::colorRampPalette(c("#F7FCF0", "#C7E9C0", "#41AB5D", "#00441B"))(256)),
      list(cl = "forest",     stem = "fig09_clcd_forest2000",
           title = "Forest proportion, 2000 (CLCD 30 m -> 1 km)",
           pal = grDevices::colorRampPalette(c("#F7FCF5", "#C7E9C0", "#238B45", "#00441B"))(256)),
      list(cl = "impervious", stem = "fig08_clcd_impervious2000",
           title = "Impervious-surface proportion, 2000 (CLCD 30 m -> 1 km)",
           pal = grDevices::colorRampPalette(c("#FFF5F0", "#FCBBA1", "#CB181D", "#67000D"))(256))
    )
    for (sp in specs) {
      f <- file.path(PATH_COV(), sprintf("glo/lulc/clcd/2000/%s/glo_lulc_clcd_2000_%s_prop.tif", sp$cl, sp$cl))
      if (!file.exists(f)) { cat("  跳过（层不存在）:", sp$stem, "\n"); next }
      r <- terra::rast(f)
      cat(sprintf("  %s ...\n", sp$stem))
      plot_national(r, sp$pal, sp$title, "Areal proportion", 0, 1, sp$stem, vec)
    }
  }

  if (which %in% c("all", "anthro")) {
    f1 <- file.path(PATH_COV(), "glo/anthro/hfp/2020/hfp/glo_anthro_hfp_2020_hfp.tif")
    if (file.exists(f1)) {
      r <- terra::rast(f1); rg <- terra::global(r, c("min", "max"), na.rm = TRUE)
      cat("  fig_hfp2020 ...\n")
      plot_national(r, grDevices::colorRampPalette(c("#FFFFE5", "#FEE391", "#FEC44F",
                                                     "#E6550D", "#662506"))(256),
                    "Human Footprint, 2020", "HFP index", rg[1, 1], rg[1, 2],
                    "fig_hfp2020", vec)
    }
    f2 <- file.path(PATH_COV(), "glo/anthro/smod/2020/glo_anthro_smod_2020.tif")
    if (!file.exists(f2)) {
      cand <- list.files(file.path(PATH_COV(), "glo/anthro/smod"), "\\.tif$",
                         recursive = TRUE, full.names = TRUE)
      cand <- cand[grepl("2020", cand)]
      f2 <- if (length(cand)) cand[1] else NA_character_
    }
    if (!is.na(f2) && file.exists(f2)) {
      r <- terra::rast(f2); rg <- terra::global(r, c("min", "max"), na.rm = TRUE)
      cat("  fig_urban2020_clamped ...\n")
      plot_national(r, grDevices::colorRampPalette(c("#F7FBFF", "#9ECAE1", "#3182BD", "#08306B"))(256),
                    "Settlement degree (GHS-SMOD), 2020", "SMOD class",
                    rg[1, 1], rg[1, 2], "fig_urban2020_clamped", vec)
    } else cat("  跳过 smod：找不到 2020 层\n")
  }
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) a[1] else "all")
}
