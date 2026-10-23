# R/figs/fig10_clcd_30m_vs_1km.R
# 目的：把"30 m 源 -> 1 km 面积比例"到底带来了什么信息，画成一张两面板图
#
# 左：CLCD 30 m 原始类别（同一窗口）
# 右：由它派生的 1 km 耕地面积比例
#
# 为什么这张图重要：它直观解释了口径问题。
# 1 km 格子里有约 1,111 个 30 m 像元，所以"比例"是真实的混合度；
# 而 1 km 源的产品（hlu1km / GLULC）在同样大小的格子里几乎没有混合，
# 它的"比例"只是类别指示。左右两面板放在一起就看得出差别。
#
# 不使用 geo-viz 引擎：它会重采样到 0.05° 显示网格，会毁掉 30 m 细节。
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
suppressPackageStartupMessages({ library(ggplot2); library(patchwork) })

# 取一个耕地比例中等的窗口（混合像元多，最能看出差异）
cv <- terra::values(terra::rast(layer_path(c("glo","lulc","clcd","2000","cropland"), "_prop")),
                    mat = FALSE)
mv <- terra::values(china_mask(), mat = FALSE)
# 2026-10-20 修：只按"混合像元 + 境内"选点，结果选中了海岸带像元，
# 其周围 40x40 km 大部分是海（源数据 NA），两面板几乎全空。
# 现在要求**整个 40x40 窗口内全部为有效耕地比例层像元**。
n <- 40L
cand <- which(!is.na(cv) & cv > 0.35 & cv < 0.55 & !is.na(mv) & mv == 1)
cand <- cand[order(abs(cand - length(cv) / 2))]
pick <- NA_integer_
for (cc in cand) {
  rr <- ((cc - 1L) %/% 4861L) + 1L
  cl <- ((cc - 1L) %%  4861L) + 1L
  if (rr < n || rr > 4062L - n || cl < n || cl > 4861L - n) next
  blk <- cv[((rr - n/2):(rr + n/2 - 1)) * 0 + 1]   # 占位，下面用矩阵判定
  ok <- TRUE
  for (dd in c(-n, n)) {
    if (rr + dd >= 1 && rr + dd <= 4062L) {
      if (anyNA(cv[((rr + dd - 1L) * 4861L + cl - n/2):((rr + dd - 1L) * 4861L + cl + n/2)])) { ok <- FALSE; break }
    }
  }
  if (ok) { pick <- cc; break }
}
if (is.na(pick)) stop("找不到四周均有效的混合像元")
cat(sprintf("选定像元 %d（耕地比例 %.3f）\n", pick, cv[pick]))
# terra 的行优先编号：cell = (row-1)*ncol + col
# 早先写反成 %/%4062 与 %%4062，导致窗口落在错误位置、两面板全空
r0 <- ((pick - 1L) %/% 4861L) + 1L
c0 <- ((pick - 1L) %%  4861L) + 1L
x0 <- terra::xFromCol(GRID()$rast, c0) - 500
x1 <- terra::xFromCol(GRID()$rast, c0 + n - 1L) + 500
y1 <- terra::yFromRow(GRID()$rast, r0) + 500
y0 <- terra::yFromRow(GRID()$rast, r0 + n - 1L) - 500
win <- terra::ext(x0, x1, y0, y1)
cat(sprintf("窗口: %.0f..%.0f, %.0f..%.0f  (%.0f km²)\n", x0, x1, y0, y1, (x1-x0)*(y1-y0)/1e6))

# --- 左：30 m 类别 ---
src <- terra::rast(file.path(PATH_ARCHIVE(), "clcd-albert", "CLCD_v01_2000_albert.tif"))
if (is.na(terra::NAflag(src))) terra::NAflag(src) <- 0
fine <- terra::crop(src, win, snap = "out")
fv <- terra::as.data.frame(fine, xy = TRUE, na.rm = TRUE)
names(fv)[3] <- "code"
fv$code <- factor(fv$code, levels = 1:9,
                  labels = c("Cropland","Forest","Shrub","Grassland","Water",
                             "Snow/Ice","Barren","Impervious","Wetland"))
pal <- c("Cropland"="#FAE39C","Forest"="#446F33","Shrub"="#33A32C","Grassland"="#ABD37B",
         "Water"="#1E69B4","Snow/Ice"="#A6CEE3","Barren"="#CFBDA3",
         "Impervious"="#E24290","Wetland"="#289BE8")
cat(sprintf("左面板: %d 个 30 m 像元\n", nrow(fv)))

p1 <- ggplot(fv, aes(x, y, fill = code)) +
  geom_raster() +
  scale_fill_manual(values = pal, name = "CLCD class", drop = FALSE) +
  coord_equal(expand = FALSE) +
  labs(subtitle = sprintf("(a) CLCD 30 m classes — %s source pixels", format(nrow(fv), big.mark = ","))) +
  theme_void(base_size = 9) +
  theme(legend.position = "right",
        legend.key.size = unit(0.32, "cm"),
        legend.text = element_text(size = 6.5),
        legend.title = element_text(size = 7.5),
        plot.subtitle = element_text(size = 8, hjust = 0))

# --- 右：1 km 耕地比例 ---
coarse <- terra::crop(terra::rast(layer_path(c("glo","lulc","clcd","2000","cropland"), "_prop")),
                      win)
cvv <- terra::as.data.frame(coarse, xy = TRUE, na.rm = TRUE)
names(cvv)[3] <- "p"
cat(sprintf("右面板: %d 个 1 km 像元\n", nrow(cvv)))

p2 <- ggplot(cvv, aes(x, y, fill = p)) +
  geom_raster() +
  scale_fill_gradientn(colours = c("#F7FCF5","#C7E9C0","#74C476","#238B45","#00441B"),
                       limits = c(0, 1), name = "Cropland\nproportion") +
  coord_equal(expand = FALSE) +
  labs(subtitle = sprintf("(b) 1 km cropland proportion — %s cells", format(nrow(cvv), big.mark = ","))) +
  theme_void(base_size = 9) +
  theme(legend.position = "right",
        legend.key.size = unit(0.32, "cm"),
        legend.text = element_text(size = 6.5),
        legend.title = element_text(size = 7.5),
        plot.subtitle = element_text(size = 8, hjust = 0))

out <- file.path(PATH_DOCS(), "figures", "fig10_clcd_30m_vs_1km")
p <- p1 + p2 +
  plot_annotation(
    title = "Why the 30 m source matters: one 1 km cell contains ~1,111 source pixels",
    caption = "Same 40 x 40 km window, CLCD 2000. Panel (b) is the areal proportion of cropland stored in the archive.",
    theme = theme(plot.title = element_text(size = 10, face = "bold"),
                  plot.caption = element_text(size = 7, colour = "grey35")))

ggsave(paste0(out, ".png"), p, width = 9.2, height = 4.6, dpi = 600, bg = "white")
ggsave(paste0(out, ".pdf"), p, width = 9.2, height = 4.6, bg = "white")
cat(sprintf("\n已输出:\n  %s.png\n  %s.pdf\n", out, out))
