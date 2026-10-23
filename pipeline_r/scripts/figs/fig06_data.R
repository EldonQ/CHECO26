# R/figs/fig06_data.R  --  阶段 1：算出 Fig.6 的全部数值并落 CSV
# 计算与绘图分离：先把数算对并存盘，核对无误后再画图
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

DIR <- file.path(PATH_ARCHIVE(), "harmonised", "Harmonised-1960-2100")
FILES <- c(ssp126 = "SSP1_RCP26_country-f.tif", ssp245 = "SSP2_RCP45_country-f.tif",
           ssp370 = "SSP3_RCP70_country-f.tif", ssp460 = "SSP4_RCP60_country-f.tif",
           ssp585 = "SSP5_RCP85_country-f.tif")
WIN <- terra::ext(70, 140, 12, 58)
r1 <- terra::rast(file.path(DIR, FILES[[1]]))
band_of <- function(y) as.integer(y) - 1959L

frac <- function(band, cls) {
  rc <- terra::crop(r1[[band]], WIN, snap = "near")
  fr <- terra::freq(rc, digits = 0)
  fr <- fr[!is.na(fr$value), ]
  tot <- sum(fr$count)
  if (!tot) return(NA_real_)
  sum(fr$count[as.character(fr$value) == cls]) / tot
}

hist_years <- seq(1960, 2020, by = 10)
cat("=== 历史段 ===\n")
res <- data.frame(year = hist_years,
                  forest    = NA_real_,
                  mngforest = NA_real_,
                  urban     = NA_real_)
for (i in seq_along(hist_years)) {
  y <- hist_years[i]
  res$forest[i]    <- frac(band_of(y), "Unmanaged forest")
  res$mngforest[i] <- frac(band_of(y), "Managed forest")
  res$urban[i]     <- frac(band_of(y), "Urban")
  cat(sprintf("  %d  forest %.4f  mng %.4f  urban %.4f\n",
              y, res$forest[i], res$mngforest[i], res$urban[i]))
}

cat("\n=== 未来段（五个情景的 Urban）===\n")
future_years <- c(2025L, 2050L, 2075L, 2100L)
fut <- data.frame(year = future_years)
for (s in names(FILES)) {
  rs <- terra::rast(file.path(DIR, FILES[[s]]))
  v <- numeric(length(future_years))
  for (i in seq_along(future_years)) {
    rc <- terra::crop(rs[[band_of(future_years[i])]], WIN, snap = "near")
    fr <- terra::freq(rc, digits = 0); fr <- fr[!is.na(fr$value), ]
    v[i] <- sum(fr$count[as.character(fr$value) == "Urban"]) / sum(fr$count)
  }
  fut[[s]] <- v
  cat(sprintf("  %s: %s\n", s, paste(sprintf("%.4f", v), collapse = " ")))
  rm(rs); gc(verbose = FALSE)
}

out <- file.path(PATH_DOCS(), "figures")
dir.create(out, showWarnings = FALSE, recursive = TRUE)
write.csv(res, file.path(out, "fig06_history.csv"), row.names = FALSE)
write.csv(fut, file.path(out, "fig06_future_urban.csv"), row.names = FALSE)
cat("\n已写出 fig06_history.csv 与 fig06_future_urban.csv\n")

cat("\n=== 关键结论 ===\n")
tot <- res$forest + res$mngforest
cat(sprintf("  森林合计: %.3f%% (1960) -> %.3f%% (2020)  变化 %+.3f 个百分点\n",
            tot[1]*100, tot[length(tot)]*100, (tot[length(tot)]-tot[1])*100))
cat(sprintf("  城市:     %.3f%% (1960) -> %.3f%% (2020)  变化 %+.3f 个百分点\n",
            res$urban[1]*100, res$urban[length(res$urban)]*100,
            (res$urban[length(res$urban)]-res$urban[1])*100))
cat(sprintf("  2100 年五情景城市占比范围: %.4f%% - %.4f%%\n",
            min(as.matrix(fut[, -1]))*100, max(as.matrix(fut[, -1]))*100))
