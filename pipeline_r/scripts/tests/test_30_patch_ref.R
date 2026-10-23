# R/tests/test_30_patch_ref.R -- 检查参照 patch 层的值域与有效范围
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

REF <- file.path(PATH_COV(), "glo/lulc/glu1km/2020")
OUT <- "E:/CHECO26/N-SDM/scratch/r_lulc_full/glo/lulc/glu1km/2020"

files <- c("glo_lulc_glu1km_2020_patchdensity-all_f5000.tif",
           "glo_lulc_glu1km_2020_patchsize-all_f5000.tif",
           "glo_lulc_glu1km_2020_patchdensity-forest_f5000.tif",
           "glo_lulc_glu1km_2020_patchsize-forest_f5000.tif")

for (f in files) {
  cat("\n=== ", f, " ===\n", sep = "")
  rp <- file.path(REF, f); gp <- file.path(OUT, f)
  for (lab in c("参照", "R")) {
    p <- if (lab == "参照") rp else gp
    if (!file.exists(p)) { cat(sprintf("  %s: 缺\n", lab)); next }
    r <- read_clean(p)
    v <- terra::values(r, mat = FALSE); v <- v[!is.na(v)]
    cat(sprintf("  %-4s n=%10s  min %12.4f  中位 %12.4f  max %12.4f  唯一值 %d\n",
                lab, format(length(v), big.mark = ","),
                min(v), median(v), max(v), length(unique(v))))
  }
  # 若两边都有效，看差异分布
  if (file.exists(rp) && file.exists(gp)) {
    a <- terra::values(read_clean(gp), mat = FALSE)
    b <- terra::values(read_clean(rp), mat = FALSE)
    cat(sprintf("  仅R有效 %d | 仅参照有效 %d | 都有效 %d\n",
                sum(!is.na(a) & is.na(b)), sum(is.na(a) & !is.na(b)),
                sum(!is.na(a) & !is.na(b))))
  }
}
