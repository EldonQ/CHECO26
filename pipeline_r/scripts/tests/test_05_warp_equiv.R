# R/tests/test_05_warp_equiv.R
#
# 目标：验证 R 的 warp_to_template 与 Python common.warp_to_template 产出等价。
# 覆盖三种主流模式：
#   1) bilinear（0.01° WGS84 气候 -> Albers），无缩放
#   2) average + scale 0.01（int16 300m 人类足迹 -> 1km）
#   3) bilinear + scale 0.01（int16 1km 土壤 -> 1km）
#
# 判据：有效性掩膜 0 差异；max|d| / span < 1e-6。

Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/00_config.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/01_common.R", encoding = "UTF-8")

read_clean <- function(path) {
  r <- terra::rast(path)
  nd <- terra::NAflag(r)
  v <- terra::values(r, mat = FALSE)
  if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
  v[is.nan(v)] <- NA
  terra::values(r) <- v
  r
}

cases <- list(
  list(tag = "bioclim bio01  bilinear",
       src   = file.path(P("bioclim"), "cnclim1km/present/1991_2020/bio01",
                          "bioclim_cnclim1km_present_1991_2020_bio01.tif"),
       ref   = file.path(PATH_COV(), "glo/bioclim/cnclim1km/present/bio01",
                          "glo_bioclim_cnclim1km_present_bio01.tif"),
       method = "bilinear", nodata = NULL, scale = NULL),
  list(tag = "foothii 2001  average x0.01",
       src   = file.path(P("foothii"), "hii_2001-01-01.tif"),
       ref   = file.path(PATH_COV(), "glo/anthro/foothii/2001/hii",
                          "glo_anthro_foothii_2001_hii.tif"),
       method = "average", nodata = -32768, scale = 0.01),
  list(tag = "soil clay 0-5 bilinear x0.01",
       src   = file.path(P("soil_1km"), "GTiff/clay/clay_0-5cm_1km.tif"),
       ref   = file.path(PATH_COV(), "glo/soil/csdlv2/clay/0",
                          "glo_soil_csdlv2_clay_0.tif"),
       method = "bilinear", nodata = -32768, scale = 0.01)
)

cat("=== R warp vs Python warp 等价性 ===\n\n")
cat(sprintf("%-32s %12s %8s %8s %12s %12s %10s\n",
            "测试", "共有效", "仅R", "仅参考", "max|d|", "span", "max|d|/span"))
cat(strrep("-", 104), "\n")

all_pass <- TRUE
tmpdir <- file.path(PATH_SCRATCH(), "r_equiv"); ensure_dir(tmpdir)

for (cs in cases) {
  if (!file.exists(cs$src) || !file.exists(cs$ref)) {
    cat(sprintf("%-32s  [SKIP] 缺文件\n", cs$tag)); next
  }
  dst <- file.path(tmpdir, paste0(gsub("[^A-Za-z0-9]+", "_", cs$tag), ".tif"))
  warp_to_template(cs$src, dst, method = cs$method,
                   src_nodata = cs$nodata, scale = cs$scale)

  got <- read_clean(dst)
  ref <- read_clean(cs$ref)
  gv <- terra::values(got, mat = FALSE)
  rv <- terra::values(ref, mat = FALSE)
  ok <- !is.na(gv) & !is.na(rv)
  n_only_r <- sum(!is.na(gv) & is.na(rv))
  n_only_f <- sum(is.na(gv) & !is.na(rv))

  d <- abs(gv[ok] - rv[ok])
  span <- diff(range(rv[ok]))
  ratio <- max(d) / span
  pass <- (n_only_r == 0L) && (n_only_f == 0L) && (ratio < 1e-6)
  all_pass <- all_pass && pass

  cat(sprintf("%-32s %12s %8d %8d %12.3e %12.4g %10.2e  %s\n",
              cs$tag, format(sum(ok), big.mark = ","),
              n_only_r, n_only_f, max(d), span, ratio,
              ifelse(pass, "PASS", "FAIL")))
}

cat("\n")
cat(sprintf("=== 总结论：%s ===\n", ifelse(all_pass, "R warp 与 Python warp 等价", "存在不通过项")))
