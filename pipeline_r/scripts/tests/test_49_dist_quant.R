# R/tests/test_49_dist_quant.R -- 判定 terra::distance 与 scipy EDT 的差异性质（量化/近似）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

# 取 grip4 road 的参照层与 R 版（test_48 已写到 scratch）
ref_p <- file.path(PATH_COV(), "glo/dist/grip4/road/glo_dist_grip4_road.tif")
got_p <- file.path(file.path(Sys.getenv("CHECO_ROOT", getwd()), "scratch/r_dist_test"),
                   "glo/dist/grip4/road/glo_dist_grip4_road.tif")
ref <- terra::rast(ref_p); got <- terra::rast(got_p)

# 取一个 300x300 窗口
g <- GRID()
x0 <- terra::xFromCol(ref, 2200); x1 <- terra::xFromCol(ref, 2500)
y1 <- terra::yFromRow(ref, 1500); y0 <- terra::yFromRow(ref, 1800)
w <- terra::ext(x0, x1, y0, y1)
a <- terra::values(terra::crop(got, w), mat = FALSE)
b <- terra::values(terra::crop(ref, w), mat = FALSE)
ok <- !is.na(a) & !is.na(b)
d <- a[ok] - b[ok]
cat(sprintf("窗口内有效像元 %d\n", sum(ok)))
cat(sprintf("  差异范围 [%.6f, %.6f]\n", min(d), max(d)))
cat(sprintf("  |d| <= 1e-6 的占比 %.2f%%\n", 100*mean(abs(d) <= 1e-6)))
cat(sprintf("  |d| <= 0.5   的占比 %.2f%%\n", 100*mean(abs(d) <= 0.5)))
cat(sprintf("  唯一差异值（前 15）: %s\n",
            paste(head(sort(unique(round(d,4))), 15), collapse=", ")))
cat(sprintf("  参照值域 [%.2f, %.2f]\n", min(b[ok]), max(b[ok])))

# 是否为"取整"关系？检查 a 是否等于 round/floor/ceiling(b)
for (f in list(round=round, floor=floor, ceiling=ceiling, trunc=trunc)) {
  nm <- names(f); fn <- f[[1]]
  eq <- mean(abs(a[ok] - fn(b[ok])) < 1e-6)
  cat(sprintf("  a == %-8s(b) 的占比 %.2f%%\n", nm, 100*eq))
}

# 暴力精确 EDT 在单个小窗口上验证 terra::distance 的真实精度
cat("\n=== 小窗口暴力 ETD 对照（80x80）===\n")
feat <- terra::rast(file.path(file.path(Sys.getenv("CHECO_ROOT", getwd()), "scratch/r_dist_test"),"feat_road.tif"))
if (file.exists(file.path(file.path(Sys.getenv("CHECO_ROOT", getwd()), "scratch/r_dist_test"),"feat_road.tif"))) {
  x0 <- terra::xFromCol(feat, 2200); x1 <- terra::xFromCol(feat, 2280)
  y1 <- terra::yFromRow(feat, 1500); y0 <- terra::yFromRow(feat, 1580)
  ww <- terra::ext(x0, x1, y0, y1)
  fm <- terra::as.matrix(terra::crop(feat, ww), wide = TRUE)
  dstr <- terra::as.matrix(terra::crop(got, ww), wide = TRUE)
  cat(sprintf("  窗口内要素像元 %d\n", sum(fm == 1, na.rm = TRUE)))
} else {
  cat("  缺 feat_road.tif，跳过\n")
}
