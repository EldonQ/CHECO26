# R/figs/fig06_anomalies.R
# Fig. 6: 两个已披露的源产品异常
#   (a) harmonised 森林轨迹（1960-2020）—— 与官方统计相反
#   (b) 城市类在 2020 之后冻结 —— 五个情景在 2100 年也几乎相同
#
# 全部从**源文件**用流式 terra::freq() 计算，不读交付层（避免满负荷时 bad_alloc）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

OUT <- file.path(PATH_DOCS(), "figures")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

DIR <- file.path(PATH_ARCHIVE(), "harmonised", "Harmonised-1960-2100")
FILES <- c(ssp126 = "SSP1_RCP26_country-f.tif", ssp245 = "SSP2_RCP45_country-f.tif",
           ssp370 = "SSP3_RCP70_country-f.tif", ssp460 = "SSP4_RCP60_country-f.tif",
           ssp585 = "SSP5_RCP85_country-f.tif")
WIN <- terra::ext(70, 140, 12, 58)
# 源文件带类别表，terra::freq() 返回文字标签；用标签匹配最稳妥
URBAN <- "Urban"; MNG <- "Managed forest"; FOREST <- "Unmanaged forest"

r1 <- terra::rast(file.path(DIR, FILES[[1]]))

#' 用流式 freq 算某类在某年（China 窗口内）的面积分数
frac <- function(band, cls) {
  rc <- terra::crop(r1[[band]], WIN, snap = "near")
  fr <- terra::freq(rc, digits = 0)
  fr <- fr[!is.na(fr$value), ]
  tot <- sum(fr$count)
  if (!tot) return(NA_real_)
  hit <- sum(fr$count[as.character(fr$value) == cls])
  hit / tot
}
band_of <- function(y) as.integer(y) - 1959L

# ---- 历史段 ----
hist_years <- seq(1960, 2020, by = 10)
cat("读历史段（源文件，流式）...\n")
h_forest <- vapply(hist_years, function(y) frac(band_of(y), FOREST), 0)
h_mng    <- vapply(hist_years, function(y) frac(band_of(y), MNG), 0)
h_urban  <- vapply(hist_years, function(y) frac(band_of(y), URBAN), 0)

cat("\n年    forest   mngforest   合计     urban\n")
for (i in seq_along(hist_years))
  cat(sprintf("%d  %7.3f%%  %8.3f%%  %7.3f%%  %7.3f%%\n", hist_years[i],
              h_forest[i]*100, h_mng[i]*100, (h_forest[i]+h_mng[i])*100, h_urban[i]*100))

# ---- 未来段：五个情景的城市 ----
future_years <- c(2030, 2050, 2070, 2090, 2100)
cat("\n读未来段城市（五个源文件）...\n")
f_urban <- matrix(NA_real_, length(future_years), length(FILES),
                  dimnames = list(future_years, names(FILES)))
for (j in seq_along(FILES)) {
  rj <- terra::rast(file.path(DIR, FILES[[j]]))
  for (i in seq_along(future_years)) {
    rc <- terra::crop(rj[[band_of(future_years[i])]], WIN, snap = "near")
    fr <- terra::freq(rc, digits = 0); fr <- fr[!is.na(fr$value), ]
    f_urban[i, j] <- sum(fr$count[as.character(fr$value) == URBAN]) / sum(fr$count)
  }
  rm(rj); gc(verbose = FALSE)
}
cat("\n未来 urban 占比（%）:\n"); print(round(f_urban * 100, 4))

# ---- 出图 ----
png(file.path(OUT, "fig06_anomalies.png"), width = 11, height = 4.3,
    units = "in", res = 300, bg = "white")
op <- par(mfrow = c(1, 2), mar = c(4.2, 4.8, 2.8, 1.0), mgp = c(2.7, 0.7, 0))

## (a)
plot(NA, xlim = range(hist_years), ylim = c(19, 30), axes = FALSE,
     xlab = "Year", ylab = "Share of China's land area (%)",
     main = "(a) Forest declines, contrary to official statistics",
     font.main = 1, cex.main = 1.0)
axis(1, at = seq(1960, 2020, 20)); axis(2, las = 1); box(bty = "l")
grid(nx = NA, ny = NULL, col = "grey92", lty = 1)
tot <- h_forest + h_mng
lines(hist_years, tot*100, lwd = 3, col = "#1f6f4a")
lines(hist_years, h_forest*100, lwd = 2, col = "#2e8b57", lty = 2)
lines(hist_years, h_mng*100, lwd = 1.4, col = "#8b5a2b", lty = 4)
points(hist_years, tot*100, pch = 16, cex = 0.7, col = "#1f6f4a")
legend("bottomleft", bty = "n", cex = 0.8,
       legend = c("forest + managed", "forest only", "managed only"),
       col = c("#1f6f4a", "#2e8b57", "#8b5a2b"), lwd = c(3, 2, 1.4), lty = c(1, 2, 4))

## (b)
plot(NA, xlim = c(1960, 2100), ylim = range(c(h_urban, f_urban))*100 + c(-0.05, 0.05),
     axes = FALSE, xlab = "Year", ylab = "Urban share of China's land area (%)",
     main = "(b) Urban class frozen after 2020",
     font.main = 1, cex.main = 1.0)
axis(1, at = seq(1960, 2100, 35)); axis(2, las = 1); box(bty = "l")
grid(nx = NA, ny = NULL, col = "grey92", lty = 1)
cols <- c("#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e")
for (j in seq_along(FILES))
  lines(c(2020, future_years), c(tail(h_urban, 1), f_urban[, j])*100, col = cols[j], lwd = 2)
lines(hist_years, h_urban*100, col = "black", lwd = 2.4)
points(hist_years, h_urban*100, pch = 16, cex = 0.55, col = "black")
abline(v = 2020, lty = 3, col = "grey40")
legend("topleft", bty = "n", cex = 0.72, legend = c("1960-2020", names(FILES)),
       col = c("black", cols), lwd = 2)
mtext("Fig. 6 - Two source-level anomalies disclosed in the archive",
      outer = TRUE, cex = 1.12, font = 2, line = 0.1)
par(op); invisible(dev.off())
cat("\n已写出 fig06_anomalies.png\n")
