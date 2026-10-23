# R/tests/test_01_config.R -- 校验 00_config.R 与 01_common.R 的网格/掩膜是否与现有产物一致
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/00_config.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/01_common.R"), encoding = "UTF-8")

print_grid()

tpl <- terra::rast(PATH_TEMPLATE())
g <- GRID()

cat("\n=== 与现有 template_albers1km.tif 比对 ===\n")
cat(sprintf("  dim : R %d x %d | 现有 %d x %d -> %s\n",
            g$width, g$height, ncol(tpl), nrow(tpl),
            ifelse(g$width == ncol(tpl) && g$height == nrow(tpl), "OK", "MISMATCH")))
cat(sprintf("  res : R %s | 现有 %s -> %s\n",
            paste(terra::res(g$rast), collapse = ","),
            paste(terra::res(tpl), collapse = ","),
            ifelse(isTRUE(all.equal(terra::res(g$rast), terra::res(tpl))), "OK", "MISMATCH")))
cat(sprintf("  ext : R    %s\n        现有 %s -> %s\n",
            paste(as.vector(terra::ext(g$rast)), collapse = ", "),
            paste(as.vector(terra::ext(tpl)), collapse = ", "),
            ifelse(isTRUE(all.equal(as.vector(terra::ext(g$rast)),
                                    as.vector(terra::ext(tpl)))), "OK", "MISMATCH")))
cat(sprintf("  CRS : %s\n", ifelse(terra::crs(g$rast) == terra::crs(tpl), "OK", "DIFFER")))

cat("\n=== 掩膜 ===\n")
m <- china_mask()
cat(sprintf("  境内像元: %s\n", format(as.numeric(terra::global(m, "sum", na.rm = TRUE)[1, 1]), big.mark = ",")))
cat(sprintf("  掩膜对齐: %s\n",
            ifelse(isTRUE(all.equal(as.vector(terra::ext(m)), as.vector(terra::ext(g$rast)))),
                   "OK", "MISMATCH")))

cat("\n=== 焦点规格 ===\n")
print(FOCAL_SPEC())

cat("\n=== check_alignment 对既有层的判定（抽 3 层应全 TRUE）===\n")
probe <- c(
  "data/covariates/glo/bioclim/cnclim1km/present/bio01/glo_bioclim_cnclim1km_present_bio01.tif",
  "data/covariates/glo/anthro/smod/2020/urbanprop/glo_anthro_smod_2020_urbanprop.tif",
  "data/covariates/glo/lulc/glu1km/2020/urban/glo_lulc_glu1km_2020_urban_prop_f5000.tif"
)
for (p in probe) {
  fp <- file.path(CHECO_ROOT, p)
  cat(sprintf("  %-72s %s\n", basename(fp), check_alignment(fp)))
}
