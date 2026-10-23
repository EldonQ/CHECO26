# R/tests/test_09_rules.R -- 三种真实使用的重采样规则的 R vs Python 差异全量统计
# 判据：区分"系统偏差"(mean signed) 与"随机抖动"(mean abs)。
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

stat <- function(tag, a, b) {
  av <- terra::values(a, mat = FALSE); bv <- terra::values(b, mat = FALSE)
  ok <- !is.na(av) & !is.na(bv)
  if (sum(ok) < 100) { cat(sprintf("%-28s 有效像元不足\n", tag)); return(invisible()) }
  d  <- av[ok] - bv[ok]
  ad <- abs(d)
  span <- diff(range(bv[ok]))
  ident <- mean(ad == 0)
  cat(sprintf("%-28s span %9.4g | 完全相同 %6.2f%% | mean(有符号) %+9.3e | mean|d| %9.3e | max|d| %9.3e\n",
              tag, span, ident * 100, mean(d), mean(ad), max(ad)))
  cat(sprintf("%-28s   |d|>1e-5: %7.3f%%  >0.001 span: %7.3f%%  >0.01 span: %7.3f%%  >0.1 span: %7.3f%%\n",
              "", mean(ad > 1e-5) * 100,
              mean(ad > 0.001 * span) * 100,
              mean(ad > 0.01 * span) * 100,
              mean(ad > 0.1 * span) * 100))
  invisible()
}

diag <- file.path(PATH_SCRATCH(), "diag_warp"); ensure_dir(diag)

cases <- list(
  list(tag = "bilinear  气候 bio01",
       src = file.path(P("bioclim"), "cnclim1km/present/1991_2020/bio01",
                       "bioclim_cnclim1km_present_1991_2020_bio01.tif"),
       ref = file.path(PATH_COV(), "glo/bioclim/cnclim1km/present/bio01",
                       "glo_bioclim_cnclim1km_present_bio01.tif"),
       method = "bilinear", nodata = NULL, scale = NULL, out = "r_bio01_bilinear"),
  list(tag = "average   人类足迹 2001",
       src = file.path(P("foothii"), "hii_2001-01-01.tif"),
       ref = file.path(PATH_COV(), "glo/anthro/foothii/2001/hii",
                       "glo_anthro_foothii_2001_hii.tif"),
       method = "average", nodata = -32768, scale = 0.01, out = "r_foothii2001"),
  list(tag = "average   土壤 clay 0-5",
       src = file.path(P("soil_1km"), "GTiff/clay/clay_0-5cm_1km.tif"),
       ref = file.path(PATH_COV(), "glo/soil/csdlv2/clay/0",
                       "glo_soil_csdlv2_clay_0.tif"),
       method = "average", nodata = -32768, scale = 0.01, out = "r_clay0"),
  list(tag = "mode      90m 分类 basin",
       src = file.path(P("hydro_final"), "basin", "basin_china.tif"),
       ref = file.path(PATH_COV(), "glo/hydro/h90m/basin",
                       "glo_hydro_h90m_basin.tif"),
       method = "mode", nodata = NULL, scale = NULL, out = "r_basin")
)

cat("=== 三种真实规则的 R vs Python 差异 ===\n\n")
for (cs in cases) {
  if (!file.exists(cs$src) || !file.exists(cs$ref)) {
    cat(sprintf("%-28s [SKIP] 缺文件\n", cs$tag)); next
  }
  dst <- file.path(diag, paste0(cs$out, ".tif"))
  ok <- tryCatch({ warp_to_template(cs$src, dst, method = cs$method,
                                    src_nodata = cs$nodata, scale = cs$scale); TRUE },
                 error = function(e) { cat(sprintf("%-28s [ERR] %s\n", cs$tag, conditionMessage(e))); FALSE })
  if (!ok) next
  stat(cs$tag, read_clean(dst), read_clean(cs$ref))
  cat("\n")
}
