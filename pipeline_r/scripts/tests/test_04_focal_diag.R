# R/tests/test_04_focal_diag.R -- 诊断 R focal 与 Python focal 的有效性掩膜差异来源
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/00_config.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/01_common.R"), encoding = "UTF-8")

read_clean <- function(path) {
  r <- terra::rast(path)
  nd <- terra::NAflag(r)
  v <- terra::values(r, mat = FALSE)
  if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
  v[is.nan(v)] <- NA
  terra::values(r) <- v
  r
}

bp <- file.path(CHECO_ROOT, "data/covariates/glo/vege/ch2019/ch/glo_vege_ch2019_ch.tif")
fp <- file.path(CHECO_ROOT, "data/covariates/glo/vege/ch2019/ch/glo_vege_ch2019_ch_f5000.tif")
b <- read_clean(bp); ref <- read_clean(fp)
got <- apply_china_mask(focal_mean(b, 5L), NA)

gv <- terra::values(got, mat = FALSE)
rv <- terra::values(ref, mat = FALSE)
g <- GRID()
mm <- matrix(as.logical(terra::values(china_mask(), mat = FALSE)), nrow = g$height, byrow = TRUE)
gv2 <- matrix(gv, nrow = g$height, byrow = TRUE)
rv2 <- matrix(rv, nrow = g$height, byrow = TRUE)

disagree <- !is.na(rv2) & is.na(gv2)
cat(sprintf("=== 参考有效但 R 无效：%d 像元 ===\n", sum(disagree)))

rows <- row(disagree)[disagree]; cols <- col(disagree)[disagree]
cat(sprintf("  行范围 %d..%d (n=%d) ; 列范围 %d..%d (n=%d)\n",
            min(rows), max(rows), g$height, min(cols), max(cols), g$width))
cat(sprintf("  距上边界 %d 行内: %d (%.1f%%)\n", 5, sum(rows <= 5), 100*sum(rows<=5)/sum(disagree)))
cat(sprintf("  距下边界 %d 行内: %d (%.1f%%)\n", 5, sum(rows > g$height-5), 100*sum(rows>g$height-5)/sum(disagree)))
cat(sprintf("  距左边界 %d 列内: %d (%.1f%%)\n", 5, sum(cols <= 5), 100*sum(cols<=5)/sum(disagree)))
cat(sprintf("  距右边界 %d 列内: %d (%.1f%%)\n", 5, sum(cols > g$width-5), 100*sum(cols>g$width-5)/sum(disagree)))
edge <- rows <= 5 | rows > g$height-5 | cols <= 5 | cols > g$width-5
cat(sprintf("  合计落在 5 像元边界带: %d (%.1f%%)\n", sum(edge), 100*sum(edge)/sum(disagree)))

cat("\n=== 参考层在这些像元上的值 ===\n")
vals <- rv2[disagree]
cat(sprintf("  min %.6g  median %.6g  max %.6g\n", min(vals), median(vals), max(vals)))
cat(sprintf("  值为 0 的: %d (%.1f%%)\n", sum(vals==0), 100*sum(vals==0)/sum(disagree)))

cat("\n=== 基底在这些像元 11x11 邻域内的有效像元数（抽样 200 个）===\n")
b2 <- matrix(as.logical(!is.na(terra::values(b, mat = FALSE))), nrow = g$height, byrow = TRUE)
idx <- which(disagree, arr.ind = TRUE)
if (nrow(idx) > 200) idx <- idx[sample(nrow(idx), 200), , drop = FALSE]
cnt <- integer(nrow(idx))
for (k in seq_len(nrow(idx))) {
  r0 <- max(1, idx[k,1]-5):min(g$height, idx[k,1]+5)
  c0 <- max(1, idx[k,2]-5):min(g$width,  idx[k,2]+5)
  cnt[k] <- sum(b2[r0, c0])
}
cat(sprintf("  邻域有效像元数分布: min %d  median %d  max %d\n", min(cnt), median(cnt), max(cnt)))
cat(sprintf("  其中 =0 的: %d / %d\n", sum(cnt==0), length(cnt)))
