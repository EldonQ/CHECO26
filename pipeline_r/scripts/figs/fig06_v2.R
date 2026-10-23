# R/figs/fig06_v2.R
# Fig. 6 (v2): 修正类别名后的两个事实
#   (a) 森林合计在增加（+2.16 pp），未经营林微降、经营林上升 —— 与官方净增长一致
#   (b) 城市类在 2020 之后冻结（五个情景、全部未来年份完全相同）
#
# 数据来源：
#   (a) 交付层（中国掩膜，等面积网格均值），年份 1960/1970/.../2020
#   (b) 1960-2020 同上；2020-2100 为源文件实测比例（五情景逐年相同）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
OUT <- file.path(PATH_DOCS(), "figures")

# ---- (a) 由 R/tests/test_63_hlu_trend_fixed.R 实测（中国区面积占比，%）----
yr <- c(1960, 1970, 1980, 1990, 2000, 2010, 2020)
forest <- c(4.917, 4.508, 3.613, 3.705, 4.546, 4.195, 4.395)   # 442 Unmanaged forest
mng    <- c(16.665, 17.413, 18.481, 18.341, 18.012, 18.946, 19.349) # 441 Managed forest
urban  <- c(1.366, 1.426, 1.476, 1.508, 1.554, 1.599, 1.652)
total  <- forest + mng

# ---- (b) 未来：源文件实测，五个情景与全部未来年份的城市比例相同 ----
fut_yr <- c(2030, 2050, 2070, 2090, 2100)
fut_val <- 1.6524   # 与 2020 交付值一致；源实测五个情景全为同一值

# 2026-10-21：把绘图包成函数，分别喂给 png 与 pdf 设备，
# 使图同时产出 PNG 与矩量 PDF。（dev.copy2pdf 不能从 png 设备复制。）
draw_fig <- function() {
  op <- par(mfrow = c(1, 2), mar = c(4.2, 4.8, 2.6, 1.0), mgp = c(2.7, 0.7, 0))
  
  ## ---- (a) 森林 ----
  plot(NA, xlim = range(yr), ylim = c(0, 26), axes = FALSE,
       xlab = "Year", ylab = "Share of China's land area (%)",
       main = "(a) Forest increases, as official statistics report",
       font.main = 1, cex.main = 1.0)
  axis(1, at = seq(1960, 2020, 20)); axis(2, las = 1); box(bty = "l")
  grid(nx = NA, ny = NULL, col = "grey92", lty = 1)
  polygon(c(yr, rev(yr)), c(rep(0, length(yr)), rep(par("usr")[4], length(yr))),
          col = NA, border = NA)
  lines(yr, total, lwd = 3.2, col = "#1f6f4a")
  lines(yr, mng,   lwd = 2.2, col = "#2e8b57", lty = 2)
  lines(yr, forest, lwd = 2.2, col = "#8b5a2b", lty = 4)
  points(yr, total, pch = 16, cex = 0.75, col = "#1f6f4a")
  legend("left", bty = "n", cex = 0.82, inset = c(0.02, 0),
         legend = c(sprintf("total  %.2f -> %.2f  (%+.2f pp)", total[1], total[7], total[7]-total[1]),
                    sprintf("managed  %+.2f pp", mng[7]-mng[1]),
                    sprintf("unmanaged  %+.2f pp", forest[7]-forest[1])),
         col = c("#1f6f4a", "#2e8b57", "#8b5a2b"), lwd = c(3.2, 2.2, 2.2), lty = c(1, 2, 4))
  
  ## ---- (b) 城市冻结 ----
  cols <- c("#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e")
  plot(NA, xlim = c(1960, 2100), ylim = c(1.30, 1.75), axes = FALSE,
       xlab = "Year", ylab = "Urban share of China's land area (%)",
       main = "(b) Urban class frozen after 2020 in all five SSP-RCPs",
       font.main = 1, cex.main = 1.0)
  axis(1, at = seq(1960, 2100, 35)); axis(2, las = 1); box(bty = "l")
  grid(nx = NA, ny = NULL, col = "grey92", lty = 1)
  lines(yr, urban, col = "black", lwd = 2.6)
  points(yr, urban, pch = 16, cex = 0.6, col = "black")
  for (k in seq_along(cols))
    lines(c(2020, fut_yr), rep(fut_val, 6), col = cols[k], lwd = 2, lty = 1)
  abline(v = 2020, lty = 3, col = "grey40")
  legend("topleft", bty = "n", cex = 0.72,
         legend = c("1960-2020 (observed record in the product)",
                    "2020-2100, all five SSP-RCPs (identical)"),
         col = c("black", "grey30"), lwd = 2.6)
  par(op)
}

stem <- "fig06_forest_and_urban_freeze"
invisible(png(file.path(OUT, paste0(stem, ".png")), width = 11, height = 4.4,
              units = "in", res = 600, bg = "white"))
draw_fig(); invisible(dev.off())
invisible(pdf(file.path(OUT, paste0(stem, ".pdf")), width = 11, height = 4.4, bg = "white"))
draw_fig(); invisible(dev.off())

cat(sprintf("已写出 %s.png / .pdf\n", stem))
cat(sprintf("(a) 森林合计 %.3f%% -> %.3f%%  (%+.3f pp)\n", total[1], total[7], total[7]-total[1]))
cat(sprintf("(b) 城市 %.3f%% -> %.3f%%，2020 后冻结于 %.4f%%\n", urban[1], urban[7], fut_val))

# 论文（Word 稿）引用的文件名为 fig05_forest_urban_freeze，
# 写入 SUBMISSION/figures（论文图件目录），不在 00_docs/figures 留重复副本。
sub_dir <- file.path(PATH_DOCS(), "SUBMISSION", "figures")
dir.create(sub_dir, showWarnings = FALSE, recursive = TRUE)
file.copy(file.path(OUT, paste0(stem, ".png")),
          file.path(sub_dir, "fig05_forest_urban_freeze.png"), overwrite = TRUE)
file.copy(file.path(OUT, paste0(stem, ".pdf")),
          file.path(sub_dir, "fig05_forest_urban_freeze.pdf"), overwrite = TRUE)
cat("已写入 SUBMISSION/figures/fig05_forest_urban_freeze.png / .pdf\n")
