# R/tests/test_03_focal_equiv.R
#
# 目标：验证 R 的 focal_mean 与 Python common.focal_mean 产出等价。
# 方法：取既有「基底 + 焦点」层对，用 R 从基底重算，与既有焦点层逐像元比对。
#
# 判据说明：
#   相对差 d/|ref| 对近零值会放大（冠层高 1e-7 m 的差异给出大相对差），不适合做门槛。
#   采用**尺度感知**判据： max|d| / (层内值域 span)。
#   合格线：有效性掩膜 0 差异，且 max|d|/span < 1e-6。

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

pairs <- list(
  list(tag = "lulc urban_prop  f1000  (3x3)",
       base  = "data/covariates/glo/lulc/glu1km/2020/urban/glo_lulc_glu1km_2020_urban_prop.tif",
       focal = "data/covariates/glo/lulc/glu1km/2020/urban/glo_lulc_glu1km_2020_urban_prop_f1000.tif",
       rc = 1L),
  list(tag = "vege ch2019      f5000  (11x11)",
       base  = "data/covariates/glo/vege/ch2019/ch/glo_vege_ch2019_ch.tif",
       focal = "data/covariates/glo/vege/ch2019/ch/glo_vege_ch2019_ch_f5000.tif",
       rc = 5L),
  list(tag = "anthro foothii01 f20000 (41x41)",
       base  = "data/covariates/glo/anthro/foothii/2001/hii/glo_anthro_foothii_2001_hii.tif",
       focal = "data/covariates/glo/anthro/foothii/2001/hii/glo_anthro_foothii_2001_hii_f20000.tif",
       rc = 20L)
)

cat("=== R focal vs Python focal 等价性 ===\n\n")
cat(sprintf("%-30s %12s %8s %8s %12s %12s %10s\n",
            "测试", "共有效", "仅R", "仅参考", "max|d|", "span", "max|d|/span"))
cat(strrep("-", 100), "\n")

all_pass <- TRUE
for (p in pairs) {
  bp <- file.path(CHECO_ROOT, p$base)
  fp <- file.path(CHECO_ROOT, p$focal)
  if (!file.exists(bp) || !file.exists(fp)) {
    cat(sprintf("%-30s  [SKIP] 缺文件\n", p$tag)); next
  }
  b   <- read_clean(bp)
  ref <- read_clean(fp)
  got <- apply_china_mask(focal_mean(b, p$rc), NA)

  gv <- terra::values(got, mat = FALSE)
  rv <- terra::values(ref, mat = FALSE)
  ok <- !is.na(gv) & !is.na(rv)
  n_only_r <- sum(!is.na(gv) & is.na(rv))
  n_only_f <- sum(is.na(gv) & !is.na(rv))

  d     <- abs(gv[ok] - rv[ok])
  span  <- diff(range(rv[ok]))
  ratio <- max(d) / span

  pass <- (n_only_r == 0L) && (n_only_f == 0L) && (ratio < 1e-6)
  all_pass <- all_pass && pass

  cat(sprintf("%-30s %12s %8d %8d %12.3e %12.4g %10.2e  %s\n",
              p$tag, format(sum(ok), big.mark = ","),
              n_only_r, n_only_f, max(d), span, ratio,
              ifelse(pass, "PASS", "FAIL")))
}

cat("\n")
cat(sprintf("=== 总结论：%s ===\n", ifelse(all_pass, "R focal 与 Python focal 等价", "存在不通过项")))
