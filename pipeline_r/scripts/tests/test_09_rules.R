# R/tests/test_09_rules.R -- 三种真实使用的重采样规则的 R vs Python 差异全量统计
# 判据：区分"系统偏差"(mean signed) 与"随机抖动"(mean abs)。
root <- Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM")
legacy <- new.env()
source(file.path(root, "R/19_rebuild_h90m_legacy.R"), local = legacy, encoding = "UTF-8")

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
native_root <- Sys.getenv("CHECO_H90M_RAW", "E:/h90m/China_Hydrography90m/Raw")
boundary_file <- Sys.getenv("CHECO_H90M_BOUNDARY", "E:/h90m/china/china.shp")
local({
  base <- normalizePath(diag, winslash = "/", mustWork = TRUE)
  out <- file.path(diag, "r_basin.tif")
  task <- legacy$h90m_legacy_manifest()$basin
  legacy$rebuild_h90m_variable(task, legacy$h90m_native_inputs(native_root, "basin"),
                               legacy$h90m_boundary(boundary_file), base, "mode", out)
  ref <- file.path(PATH_COV(), "reg/hydro/h90m/basin/reg_hydro_h90m_basin.tif")
  current <- terra::values(terra::rast(ref), mat = FALSE)
  rebuilt <- terra::values(terra::rast(out), mat = FALSE)
  stopifnot(identical(rebuilt, current))
  stat("mode      90m basin", read_clean(out), read_clean(ref))
})

cases <- list(
  list(tag = "bilinear  气候 bio01 (CHELSA)",
       src = file.path(P("chelsa"), "bioclim/bio01/1981-2010",
                       "CHELSA_bio01_1981-2010_V.2.1.tif"),
       ref = file.path(PATH_COV(), "reg/bioclim/chelsa21/present/bio01",
                       "reg_bioclim_chelsa21_present_bio01.tif"),
       method = "bilinear", nodata = NULL, scale = NULL, out = "r_bio01_bilinear"),
  list(tag = "average   土壤 clay 0-5",
       src = file.path(P("soil_1km"), "GTiff/clay/clay_0-5cm_1km.tif"),
       ref = file.path(PATH_COV(), "reg/soil/csdlv2/clay/0",
                       "reg_soil_csdlv2_clay_0.tif"),
       method = "average", nodata = -32768, scale = 0.01, out = "r_clay0")
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
