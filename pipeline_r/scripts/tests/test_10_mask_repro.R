# R/tests/test_10_mask_repro.R
# 先把 R 生成的 mask/template 写到 scratch，与现有产物逐像元比对。
# 只有完全一致（或差异已被解释）才允许 02_template.R 覆盖正式文件。
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
suppressPackageStartupMessages({ library(terra) })
source("E:/CHECO26/N-SDM/R/00_config.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/01_common.R", encoding = "UTF-8")

g <- GRID()
out <- file.path(PATH_SCRATCH(), "diag_template"); ensure_dir(out)

# ---- R 版 mask ----
shp <- P("china_shp")
v <- terra::project(terra::vect(shp), terra::crs(g$rast))
all_touched <- isTRUE(CFG()$mask$all_touched)
cat(sprintf("china.shp: %d 要素 ; all_touched=%s\n", nrow(v), all_touched))

m_touch <- terra::rasterize(v, g$rast, field = 1, touches = TRUE,  background = 0)
m_plain <- terra::rasterize(v, g$rast, field = 1, touches = FALSE, background = 0)
nt <- as.integer(terra::global(m_touch, "sum", na.rm = TRUE)[1, 1])
np <- as.integer(terra::global(m_plain, "sum", na.rm = TRUE)[1, 1])
cat(sprintf("  R touches=TRUE : %d 像元\n  R touches=FALSE: %d 像元\n", nt, np))

# ---- 现有 mask ----
ref <- terra::rast(PATH_MASK())
nv_ref <- as.integer(terra::global(ref, "sum", na.rm = TRUE)[1, 1])
cat(sprintf("  现有 mask_china.tif : %d 像元\n", nv_ref))

# ---- 逐像元比对 ----
cmp <- function(a, b, lab) {
  av <- terra::values(a, mat = FALSE); bv <- terra::values(b, mat = FALSE)
  same <- sum(av == bv, na.rm = TRUE)
  cat(sprintf("  %-28s 相同 %s / %s  (%.4f%%) | 仅A %d | 仅B %d\n",
              lab, format(same, big.mark = ","), format(length(av), big.mark = ","),
              100 * same / length(av),
              sum(av == 1 & bv != 1, na.rm = TRUE),
              sum(av != 1 & bv == 1, na.rm = TRUE)))
}
cat("\n=== 与现有 mask 比对 ===\n")
cmp(m_touch, ref, "R touches=TRUE vs 现有")
cmp(m_plain, ref, "R touches=FALSE vs 现有")

# ---- template ----
t <- g$rast; terra::values(t) <- 1
ref_t <- terra::rast(PATH_TEMPLATE())
cat("\n=== template 比对 ===\n")
cat(sprintf("  dim 相同: %s | res 相同: %s | ext 相同: %s\n",
            ncol(t) == ncol(ref_t) && nrow(t) == nrow(ref_t),
            isTRUE(all.equal(terra::res(t), terra::res(ref_t))),
            isTRUE(all.equal(as.vector(terra::ext(t)), as.vector(terra::ext(ref_t))))))
tv <- terra::values(t, mat = FALSE); rv <- terra::values(ref_t, mat = FALSE)
cat(sprintf("  值全相等(==1): R %s / 现有 %s\n",
            all(tv == 1), all(rv == 1, na.rm = TRUE)))

# ---- 保存 scratch 版本供后续使用 ----
terra::writeRaster(m_touch, file.path(out, "mask_r_touch.tif"), overwrite = TRUE, datatype = "INT1U")
terra::writeRaster(m_plain, file.path(out, "mask_r_plain.tif"), overwrite = TRUE, datatype = "INT1U")
cat("\nscratch 版本已写出:", out, "\n")
