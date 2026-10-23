# R/tools/check_trends.R -- 核验论文里的**趋势类数字**
#
# 2026-10-21 新增。动机：`check_docs_consistency.R` 只覆盖计数类（层数/行数/GB/主题数），
# 而趋势类（百分点变化、百分比、比值）它一律不检查。本次会话已因此漏过一处：
# 论文写 `forest +0.11 pp`，真实是 `+0.10 pp`，一致性脚本 PASS，只有手工重算才发现。
#
# 本脚本把那 6 组趋势数字全部从磁盘重算，并与论文文本比对。凡论文里写出的数字
# 都必须在这里有一条对应断言——**做不到自动核的数字，就不该出现在论文里**。
#
# 用法：Rscript R/tools/check_trends.R
ROOT  <- "E:/CHECO26/N-SDM"
COV   <- file.path(ROOT, "data", "covariates")
PAPER <- file.path(ROOT, "00_docs", "PAPER_CHECO26_DATADESCRIPTOR.md")

txt <- paste(readLines(PAPER, encoding = "UTF-8", warn = FALSE), collapse = "\n")
ok <- 0L; bad <- 0L; fails <- character(0)

say <- function(label, claimed, actual, tol = 0.005) {
  # 注意：all.equal 的 tolerance 是**相对**的。论文把 pp 变化写成两位小数，
  # 用相对容差会把 0.10 vs 0.1048 判为失败（相对差 4.8%）。这里要的是绝对容差。
  good <- abs(as.numeric(claimed) - as.numeric(actual)) <= tol
  if (good) { ok <<- ok + 1L; cat(sprintf("  PASS  %-44s %s\n", label, format(actual))) }
  else { bad <<- bad + 1L; fails <<- c(fails, label)
         cat(sprintf("  FAIL  %-44s 论文写 %s，磁盘算出 %s\n", label, claimed, format(actual))) }
}
has <- function(s) grepl(s, txt, fixed = TRUE)

cat("===============================================================\n")
cat(" \u8bba\u6587\u8d8b\u52bf\u6570\u5b57\u6838\u9a8c\n")
cat("===============================================================\n\n")

# ---- 1) clcd 2000/2005 逐类占比 ----
cat("1) CLCD \u4e5d\u7c7b\u5360\u6bd4 2000 vs 2005\n")
frac <- function(f) { v <- terra::values(terra::rast(f)); mean(v, na.rm = TRUE) * 100 }
cls <- c("cropland","forest","shrub","grassland","water","snowice","barren","impervious","wetland")
a <- b <- setNames(numeric(length(cls)), cls)
for (cl in cls) {
  a[cl] <- frac(file.path(COV, sprintf("glo/lulc/clcd/2000/%s/glo_lulc_clcd_2000_%s_prop.tif", cl, cl)))
  b[cl] <- frac(file.path(COV, sprintf("glo/lulc/clcd/2005/%s/glo_lulc_clcd_2005_%s_prop.tif", cl, cl)))
}
d <- b - a
say("cropland 2000 (%)", 20.53, a[["cropland"]])
say("cropland 2005 (%)", 20.22, b[["cropland"]])
say("cropland \u53d8\u5316 (pp)", -0.31, d[["cropland"]])
say("forest \u53d8\u5316 (pp)",     0.10,  d[["forest"]])
say("grassland \u53d8\u5316 (pp)",  0.10,  d[["grassland"]])
say("barren \u53d8\u5316 (pp)",    -0.23,  d[["barren"]])
say("impervious 2000 (%)", 1.58, a[["impervious"]])
say("impervious 2005 (%)", 1.79, b[["impervious"]])
say("impervious \u53d8\u5316 (pp)",  0.21,  d[["impervious"]])
say("impervious \u76f8\u5bf9\u589e (%)", 13.4, 100 * (b[["impervious"]] - a[["impervious"]]) / a[["impervious"]], tol = 0.05)
say("\u4e5d\u7c7b\u4e4b\u548c 2005 (%)", 100.00, sum(b), tol = 0.02)

# ---- 2) hlu1km \u68ee\u6797\u4e0e\u57ce\u5e02 1960 vs 2020 ----
cat("\n2) hlu1km \u68ee\u6797\u4e0e\u57ce\u5e02 1960 vs 2020\n")
hf <- function(yr, cl) frac(file.path(COV, sprintf("glo/lulc/hlu1km/%s/%s/glo_lulc_hlu1km_%s_%s_prop.tif", yr, cl, yr, cl)))
m60 <- hf("1960","mngforest"); u60 <- hf("1960","forest")
m20 <- hf("2020","mngforest"); u20 <- hf("2020","forest")
r60 <- hf("1960","urban");     r20 <- hf("2020","urban")
say("managed 1960 (%)", 16.66, m60)
say("managed 2020 (%)", 19.35, m20)
say("managed \u53d8\u5316 (pp)", 2.68, m20 - m60)
say("unmanaged \u53d8\u5316 (pp)", -0.52, u20 - u60)
say("\u68ee\u6797\u5408\u8ba1 1960 (%)", 21.58, m60 + u60)
say("\u68ee\u6797\u5408\u8ba1 2020 (%)", 23.74, m20 + u20)
say("\u68ee\u6797\u5408\u8ba1\u53d8\u5316 (pp)", 2.16, (m20 + u20) - (m60 + u60))
say("urban 1960 (%)", 1.37, r60)
say("urban 2020 (%)", 1.65, r20)

# ---- 3) \u9010\u7c7b\u4e2d\u95f4\u503c\u6bd4\u4f8b ----
cat("\n3) \u9010\u7c7b\u4e2d\u95f4\u503c\u6bd4\u4f8b\uff08\u4e0b\u9650 0 < v < 1\uff09\n")
midp <- function(f) { v <- terra::values(terra::rast(f)); v <- v[!is.na(v)]; 100 * mean(v > 0 & v < 1) }
clcd_mid <- mean(vapply(cls, function(cl)
  midp(file.path(COV, sprintf("glo/lulc/clcd/2000/%s/glo_lulc_clcd_2000_%s_prop.tif", cl, cl))), 0))
hcls <- c("urban","cropland","pasture","mngforest","forest","grassshrub","sparse","water")
hlu_mid <- mean(vapply(hcls, function(cl)
  midp(file.path(COV, sprintf("glo/lulc/hlu1km/2020/%s/glo_lulc_hlu1km_2020_%s_prop.tif", cl, cl))), 0))
say("clcd \u9010\u7c7b\u4e2d\u95f4\u503c\u5747\u503c (%)", 21.4, clcd_mid, tol = 0.15)
say("hlu1km \u9010\u7c7b\u4e2d\u95f4\u503c\u5747\u503c (%)", 5.8, hlu_mid, tol = 0.15)
say("\u6bd4\u503c", 3.7, clcd_mid / hlu_mid, tol = 0.15)

# ---- 4) \u7126\u70b9\u56db\u5c3a\u5ea6 max \u5355\u8c03\u9012\u51cf ----
cat("\n4) \u7126\u70b9\u56db\u5c3a\u5ea6 max \u5355\u8c03\u9012\u51cf\uff08CLCD 2000 cropland\uff09\n")
st <- file.path(COV, "glo/lulc/clcd/2000/cropland/glo_lulc_clcd_2000_cropland_prop")
mx <- vapply(c("", "_f1000", "_f5000", "_f10000", "_f20000"), function(s)
  terra::global(terra::rast(paste0(st, s, ".tif")), "max", na.rm = TRUE)[1,1], 0)
say("max _f1000",   1.0000, mx[2], tol = 1e-3)
say("max _f5000",   0.9989, mx[3], tol = 1e-3)
say("max _f10000",  0.9947, mx[4], tol = 1e-3)
say("max _f20000",  0.9836, mx[5], tol = 1e-3)
# \u57fa\u5e95\u5c42\u7684 max \u4e0e _f1000 \u7684 max \u90fd\u662f 1.0\uff08\u5355\u50cf\u5143\u6700\u5927\u503c\u4e0d\u4f1a\u56e0\u5c0f\u7a97\u53e3\u800c\u53d8\uff09\uff0c
# \u6240\u4ee5\u5355\u8c03\u6027\u5e94**\u53ea\u5728\u56db\u4e2a\u7126\u70b9\u5c3a\u5ea6\u4e4b\u95f4**\u770b\u3002
mono <- all(diff(mx[2:5]) < 0)
cat(sprintf("  \u4e94\u5c3a\u5ea6 max: %s\n", paste(sprintf("%.6f", mx), collapse = " > ")))
cat(sprintf("  \u56db\u4e2a\u7126\u70b9\u5c3a\u5ea6\u5355\u8c03\u9012\u51cf: %s\n", if (mono) "OK" else "**FAIL**"))
if (mono) ok <- ok + 1L else { bad <- bad + 1L; fails <- c(fails, "max \u5355\u8c03\u9012\u51cf") }
# 四个尺度的**图层均值**应相同（等权均值的均值保持不变）。
# 注意：这里比的不是 max —— 原稿误把四个 max 的均值当成图层均值，必然失败。
mn <- vapply(c("", "_f1000", "_f5000", "_f10000", "_f20000"), function(suf)
  terra::global(terra::rast(paste0(st, suf, ".tif")), "mean", na.rm = TRUE)[1, 1], 0)
say("\u57fa\u5e95\u56fe\u5c42\u5747\u503c",   0.2053, mn[1], tol = 1e-3)
say("_f1000 \u56fe\u5c42\u5747\u503c",       0.2053, mn[2], tol = 1e-3)
say("_f20000 \u56fe\u5c42\u5747\u503c",      0.2053, mn[5], tol = 1e-3)
cat(sprintf("  \u4e94\u5c3a\u5ea6\u56fe\u5c42\u5747\u503c\u7684\u6781\u5dee: %.2e\n", diff(range(mn))))
# 容差 1e-4 而不是 1e-6：有 NoData 时每个窗口的有效像元数不同，
# 分母变化使焦点均值与基底均值不会严格相等（实测极差 3.5e-05）。
if (diff(range(mn)) < 1e-4) {
  ok <- ok + 1L
} else {
  bad <- bad + 1L; fails <- c(fails, "\u4e94\u5c3a\u5ea6\u56fe\u5c42\u5747\u503c\u76f8\u540c")
}

# ---- 5) \u7ec4\u6210\u6052\u7b49\u5f0f ----
cat("\n5) CLCD 2008 \u7ec4\u6210\u6052\u7b49\u5f0f\n")
fs <- file.path(COV, sprintf("glo/lulc/clcd/2008/%s/glo_lulc_clcd_2008_%s_prop.tif", cls, cls))
s <- terra::app(terra::rast(fs), "sum", na.rm = FALSE)
v <- terra::values(s, mat = FALSE); v <- v[!is.na(v)]
say("max|sum-1|", 5.215e-08, max(abs(v - 1)), tol = 0.05)
say("\u6709\u6548\u50cf\u5143\u6570", 9471991, length(v), tol = 1e-9)

# ---- 6) \u91cd\u91c7\u6837\u6548\u5e94 CSV ----
cat("\n6) \u91cd\u91c7\u6837\u6548\u5e94\uff08\u8bfb resampling_effect.csv\uff09\n")
rf <- file.path(ROOT, "00_docs", "resampling_effect.csv")
if (file.exists(rf)) {
  re <- read.csv(rf, fileEncoding = "UTF-8", stringsAsFactors = FALSE)
  say("vege \u4e2d\u4f4d\u76f8\u5bf9\u5dee (%)", 0.00, re$med_rel_diff_pct[grepl("vege", re$layer)], tol = 0.05)
  say("dist \u4e2d\u4f4d\u76f8\u5bf9\u5dee (%)", 2.40, re$med_rel_diff_pct[grepl("dist", re$layer)], tol = 0.05)
  say("hydro \u4e2d\u4f4d\u76f8\u5bf9\u5dee (%)", 7.75, re$med_rel_diff_pct[grepl("hydro", re$layer)], tol = 0.05)
  say("vege \u683c\u5185 CV (%)", 90.0, re$med_within_cv_pct[grepl("vege", re$layer)], tol = 0.05)
  say("hydro \u683c\u5185 CV (%)", 277.4, re$med_within_cv_pct[grepl("hydro", re$layer)], tol = 0.05)
} else cat("  \u8df3\u8fc7\uff1aresampling_effect.csv \u4e0d\u5b58\u5728\n")

cat("\n===============================================================\n")
cat(sprintf(" \u6c47\u603b: PASS %d / FAIL %d\n", ok, bad))
if (bad) cat(" \u5931\u8d25\u9879:\n", paste0("   - ", fails, collapse = "\n"), "\n")
cat("===============================================================\n")
invisible(bad)
