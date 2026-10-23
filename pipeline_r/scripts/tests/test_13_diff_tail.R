# R/tests/test_13_diff_tail.R
# 量化 R vs Python 差异的尾部结构，为判据提供依据：
#   (1) 有效性不一致的像元有多少、占比多少、是否都贴着无效域边界
#   (2) |d|/span 的分位数与超阈值计数
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

read_clean_mat <- function(path) {
  r <- terra::rast(path)
  nd <- terra::NAflag(r)
  v <- terra::values(r, mat = FALSE)
  if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
  v[is.nan(v)] <- NA
  matrix(v, nrow = nrow(r), ncol = ncol(r), byrow = TRUE)
}

d1 <- file.path(PATH_SCRATCH(), "r_theme_equiv")
cases <- list(
  list(tag = "bio01 bilinear",       f = "glo_bioclim_cnclim1km_present_bio01.tif",
       ref = file.path(PATH_COV(), "glo/bioclim/cnclim1km/present/bio01/glo_bioclim_cnclim1km_present_bio01.tif")),
  list(tag = "clay bilinear x0.01",  f = "glo_soil_csdlv2_clay_0.tif",
       ref = file.path(PATH_COV(), "glo/soil/csdlv2/clay/0/glo_soil_csdlv2_clay_0.tif")),
  list(tag = "channel-dist-up-cel average", f = "glo_hydro_h90m_channel-dist-up-cel.tif",
       ref = file.path(PATH_COV(), "glo/hydro/h90m/channel-dist-up-cel/glo_hydro_h90m_channel-dist-up-cel.tif")),
  list(tag = "basin mode",           f = "glo_hydro_h90m_basin.tif",
       ref = file.path(PATH_COV(), "glo/hydro/h90m/basin/glo_hydro_h90m_basin.tif"))
)

cat("=== 差异尾部结构分析 ===\n")
for (cs in cases) {
  fp <- file.path(d1, cs$f)
  if (!file.exists(fp) || !file.exists(cs$ref)) { cat(sprintf("\n%s: 缺文件\n", cs$tag)); next }
  A <- read_clean_mat(fp); B <- read_clean_mat(cs$ref)
  com <- !is.na(A) & !is.na(B)
  n_com <- sum(com)
  span <- diff(range(B[com]))
  d <- abs(A[com] - B[com]) / span

  mism <- (is.na(A) & !is.na(B)) | (!is.na(A) & is.na(B))
  n_mism <- sum(mism)
  # 边界性：不一致像元 8 邻域内是否含"无效"像元（按任一侧的无效域）
  inval <- is.na(A) | is.na(B)
  nb <- matrix(FALSE, nrow(A), ncol(A))
  nr <- nrow(A); nc <- ncol(A)
  for (dy in -1:1) for (dx in -1:1) {
    if (dy == 0 && dx == 0) next
    r0 <- max(1, 1 + dy):min(nr, nr + dy); c0 <- max(1, 1 + dx):min(nc, nc + dx)
    r1 <- max(1, 1 - dy):min(nr, nr - dy); c1 <- max(1, 1 - dx):min(nc, nc - dx)
    nb[r1, c1] <- nb[r1, c1] | inval[r0, c0]
  }
  adj <- sum(mism & nb); not_adj <- sum(mism & !nb)

  cat(sprintf("\n--- %s ---\n", cs$tag))
  cat(sprintf("  有效像元 %s | span %.4g\n", format(n_com, big.mark = ","), span))
  cat(sprintf("  有效性不一致 %d (%.5f%%) : 贴近无效域 %d, 孤立 %d\n",
              n_mism, 100 * n_mism / (n_com + n_mism), adj, not_adj))
  qs <- quantile(d, c(0.5, 0.9, 0.99, 0.999, 0.9999, 1))
  cat("  |d|/span 分位: ")
  cat(paste(sprintf("p%s=%.2e", sub("^.*%$", "", names(qs)), as.numeric(qs)), collapse = "  "), "\n")
  cat("  超阈值计数: ")
  for (t in c(1e-4, 1e-3, 1e-2, 5e-2, 1e-1)) {
    n <- sum(d > t)
    cat(sprintf(" >%g:%d(%.5f%%)", t, n, 100 * n / n_com))
  }
  cat("\n")
}
