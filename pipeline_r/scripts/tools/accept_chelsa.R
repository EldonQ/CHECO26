# =============================================================================
# R/tools/accept_chelsa.R  --  CHELSA bioclim 替换最终验收（Phase 8）
#
# 用法：Rscript R/tools/accept_chelsa.R
# 逐项核验目标判据，打印 PASS/FAIL；任一 FAIL 则退出码 1。
# 前提：run_bioclim_chelsa.R 与 run_metadata_chelsa.R 已跑完、旧层已归档。
# =============================================================================
invisible(try(Sys.setlocale("LC_CTYPE", ".65001"), silent = TRUE))
if (!nzchar(Sys.getenv("CHECO_ROOT", ""))) Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source(file.path(Sys.getenv("CHECO_ROOT"), "R/_bootstrap.R"), encoding = "UTF-8")
suppressPackageStartupMessages(library(terra))

fails <- 0L
chk <- function(label, ok, detail = "") {
  cat(sprintf("[%s] %s%s\n", if (ok) "PASS" else "FAIL", label,
              if (nzchar(detail)) paste0("  (", detail, ")") else ""))
  if (!ok) fails <<- fails + 1L
}

cov <- PATH_COV()
disk <- list.files(cov, pattern = "\\.tif$", recursive = TRUE, full.names = FALSE)
disk <- disk[!grepl("\\.(tmp\\.tif|aux\\.xml)$", disk)]
chelsa <- disk[grepl("^reg/bioclim/chelsa21", disk)]
old <- disk[grepl("^reg/bioclim/cnclim1km", disk)]

# ① 层数
chk("chelsa21 层数 = 1210", length(chelsa) == 1210, paste(length(chelsa)))
chk("chelsa21 现值 = 22", sum(grepl("/present/", chelsa)) == 22)
chk("chelsa21 未来 = 1188", sum(grepl("/scenario/", chelsa)) == 1188)
chk("chelsa21 ensmean = 198", sum(grepl("chelsa21-ensmean/", chelsa)) == 198)
chk("全库交付层 = 21788", length(disk) == 21788, paste(length(disk)))
# ③ 旧层已归档
chk("旧 cnclim1km 已移出交付树", length(old) == 0, paste(length(old)))

# ② 像元级抽检（几何/掩膜/nodata/标准口径）
tpl <- rast(PATH_TEMPLATE()); msk <- rast(PATH_MASK()); msk <- !is.na(msk) & msk > 0
gcrs <- crs(tpl, proj = TRUE)
sample_vars <- c("bio02", "bio03", "bio05", "bio06", "bio12", "gdd5")
for (v in sample_vars) {
  p <- file.path(cov, "reg/bioclim/chelsa21/present", v,
                 sprintf("reg_bioclim_chelsa21_present_%s.tif", v))
  if (!file.exists(p)) { chk(paste("现值", v, "存在"), FALSE); next }
  r <- rast(p); vv <- values(r, mat = FALSE)
  geom <- ncol(r) == 4861 && nrow(r) == 4062 && identical(crs(r, proj = TRUE), gcrs)
  nv <- sum(!is.na(vv))
  inside <- sum(!is.na(values(mask(r, msk, maskvalue = FALSE, updatevalue = NA), mat = FALSE)))
  d <- describe(p, print = FALSE); nd <- grepl("NoData Value=-9999", paste(d, collapse = " "))
  is_gdd <- grepl("^gdd", v)
  cover_ok <- if (is_gdd) (inside == nv && nv > 0 && min(vv, na.rm = TRUE) >= 0) else (nv == 9490310 && inside == nv)
  chk(sprintf("现值 %s 几何/掩膜/nodata", v), geom && cover_ok && nd,
      sprintf("n=%d 外溢=%d%s", nv, nv - inside, if (is_gdd) " (gdd 允许源 NoData 减覆盖)" else ""))
}
# 标准口径断言
b02 <- values(rast(file.path(cov, "reg/bioclim/chelsa21/present/bio02/reg_bioclim_chelsa21_present_bio02.tif")), mat = FALSE)
b06 <- values(rast(file.path(cov, "reg/bioclim/chelsa21/present/bio06/reg_bioclim_chelsa21_present_bio06.tif")), mat = FALSE)
chk("bio02 标准日较差（中位 8-15°C）", { m <- median(b02, na.rm = TRUE); m > 8 && m < 15 }, sprintf("中位 %.2f", median(b02, na.rm = TRUE)))
chk("bio06 冷尾物理合理（min > -52.3°C）", min(b06, na.rm = TRUE) > -52.3, sprintf("min %.2f", min(b06, na.rm = TRUE)))

# ④ 四方一致（磁盘 = 清单 = 溯源 = 字典）
man <- read.csv(file.path(PATH_DOCS(), "MANIFEST.csv"), fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
man_cov <- sub("^covariates/", "", man$relpath[grepl("^covariates/", man$relpath)])
prov <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"), fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
prov_act <- prov$layer_path[prov$status == "active"]
vd <- read.csv(file.path(PATH_DOCS(), "variable_dictionary.csv"), fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
chk("清单 covariates = 磁盘", setequal(man_cov, disk), sprintf("清单%d 磁盘%d", length(man_cov), length(disk)))
chk("溯源 active = 磁盘", setequal(prov_act, disk), sprintf("溯源%d", length(prov_act)))
chk("字典 = 磁盘", setequal(vd$relpath, disk), sprintf("字典%d", length(vd$relpath)))
chk("溯源 chelsa21 = 1210", sum(grepl("^reg/bioclim/chelsa21", prov_act)) == 1210)
chk("字典统计已填（chelsa21 无 NA）", { x <- vd[grepl("^reg/bioclim/chelsa21", vd$relpath), ]; all(!is.na(x$n_valid)) })

# ① gdd 源齐全
gdd <- list.files("F:/LLQ/CHELSA-bioclim/CHELSA_v2.1/bioclim", pattern = "\\.tif$", recursive = TRUE)
gdd <- gdd[grepl("^gdd(0|5|10)/", gdd)]
chk("gdd0/5/10 源 = 138", length(gdd) == 138, paste(length(gdd)))

cat(sprintf("\n==== 验收 %s：%d 项 FAIL ====\n", if (fails == 0) "通过" else "未通过", fails))
quit(status = if (fails == 0) 0 else 1)