# R/tests/test_53_chelsa.R -- CHELSA v2.1 专项单元测试（2026-11-13 新增）
# 验证：层数构成、bio03 百分数口径、bio02 标准日较差、ensmean = 5 GCM 逐像元均值。
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
suppressPackageStartupMessages(library(terra))
cov <- PATH_COV()
pres <- file.path(cov, "reg/bioclim/chelsa21/present")
npass <- 0; ntot <- 0
chk <- function(tag, ok) { ntot <<- ntot + 1; npass <<- npass + ok
  cat(sprintf("  [%s] %s\n", ifelse(ok, "PASS", "FAIL"), tag)) }

# 1) 层数构成
all_ch <- list.files(file.path(cov, "reg/bioclim"), pattern = "[.]tif$", recursive = TRUE)
chk("chelsa21 总层数 = 1210", length(all_ch) == 1210)
chk("现值 = 22", sum(grepl("/present/", all_ch)) == 22)
chk("未来 = 1188", sum(grepl("/scenario/", all_ch)) == 1188)

# 2) bio03 百分数口径（0-100，中位约 26）
b03 <- values(rast(file.path(pres, "bio03/reg_bioclim_chelsa21_present_bio03.tif")), mat = FALSE)
m03 <- median(b03, na.rm = TRUE)
chk(sprintf("bio03 百分数口径（中位 %.2f ∈ [20,45]，max ≤ 100）", m03),
    m03 > 20 && m03 < 45 && max(b03, na.rm = TRUE) <= 100)

# 3) bio02 标准日较差（中位 8-15）
b02 <- values(rast(file.path(pres, "bio02/reg_bioclim_chelsa21_present_bio02.tif")), mat = FALSE)
m02 <- median(b02, na.rm = TRUE)
chk(sprintf("bio02 标准日较差（中位 %.2f ∈ [8,15]）", m02), m02 > 8 && m02 < 15)

# 4) ensmean = 5 GCM 逐像元等权均值（抽 bio01 / 2055 / ssp370）
gcms <- c("gfdl-esm4", "ipsl-cm6a-lr", "mpi-esm1-2-hr", "mri-esm2-0", "ukesm1-0-ll")
sub <- "scenario/2055/ssp370/bio01"
ens <- rast(file.path(cov, "reg/bioclim/chelsa21-ensmean", sub,
                      "reg_bioclim_chelsa21-ensmean_scenario_2055_ssp370_bio01.tif"))
gcm_rasts <- lapply(gcms, function(g)
  rast(file.path(cov, paste0("reg/bioclim/chelsa21-", g), sub,
                 paste0("reg_bioclim_chelsa21-", g, "_scenario_2055_ssp370_bio01.tif"))))
mean5 <- mean(rast(gcm_rasts), na.rm = TRUE)
d <- abs(values(ens, mat = FALSE) - values(mean5, mat = FALSE))
chk(sprintf("ensmean = 5 GCM 均值（max|diff| = %.2e）", max(d, na.rm = TRUE)),
    max(d, na.rm = TRUE) < 1e-4)

cat(sprintf("\n=== CHELSA 专项 %d / %d 通过 ===\n", npass, ntot))
stopifnot(npass == ntot)