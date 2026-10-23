# R/tests/test_54_newds_validate.R -- 新数据集（hfp/hlu1km/clcd）的焦点不变量与值域校验
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

FS <- FOCAL_SPEC()

#' 对「基底 + 焦点」组检查：焦点均值必须落在基底 [min, max] 内
check_group <- function(base, tols = 1e-4) {
  r <- terra::rast(base)
  nd <- terra::NAflag(r)
  bv <- terra::values(r, mat = FALSE)
  if (!is.na(nd)) bv[!is.na(bv) & abs(bv - nd) < 1e-6] <- NA
  bv <- bv[!is.na(bv)]
  if (!length(bv)) return(NULL)
  lo <- min(bv) - tols; hi <- max(bv) + tols
  out <- list()
  for (k in seq_len(nrow(FS))) {
    fp <- paste0(sub("\\.tif$", "", base), FS$suffix[k], ".tif")
    if (!file.exists(fp)) { out[[FS$suffix[k]]] <- NA; next }
    fr <- terra::rast(fp); fnd <- terra::NAflag(fr)
    fv <- terra::values(fr, mat = FALSE)
    if (!is.na(fnd)) fv[!is.na(fv) & abs(fv - fnd) < 1e-6] <- NA
    fv <- fv[!is.na(fv)]
    if (!length(fv)) { out[[FS$suffix[k]]] <- NA; next }
    out[[FS$suffix[k]]] <- sum(fv < lo | fv > hi)
  }
  list(base_min = min(bv), base_max = max(bv), n = length(bv), bad = out)
}

report <- function(ds, bases) {
  cat(sprintf("\n=== %s（%d 个基底层抽样）===\n", ds, length(bases)))
  tot_bad <- 0; nchk <- 0
  for (b in bases) {
    g <- tryCatch(check_group(b), error = function(e) NULL)
    if (is.null(g)) next
    bad <- unlist(g$bad)
    if (all(is.na(bad))) next
    tot_bad <- tot_bad + sum(bad, na.rm = TRUE); nchk <- nchk + sum(!is.na(bad))
    cat(sprintf("  %-52s base [%.4g, %.4g]  越界焦点像元 %d\n",
                basename(b), g$base_min, g$base_max, sum(bad, na.rm = TRUE)))
  }
  cat(sprintf("  合计: %d 个焦点层，越界像元 %d（应为 0）\n", nchk, tot_bad))
}

# hfp
p1 <- file.path(PATH_COV(), "glo/anthro/hfp")
bases1 <- list.files(p1, pattern = "^glo_anthro_hfp_[0-9]+_hfp\\.tif$",
                     recursive = TRUE, full.names = TRUE)
cat(sprintf("hfp: %d 个基底层（应有 25）\n", length(bases1)))
if (length(bases1)) report("anthro/hfp", head(bases1, 5))

# hlu1km（已生成部分）
p2 <- file.path(PATH_COV(), "glo/lulc/hlu1km")
bases2 <- list.files(p2, pattern = "_prop\\.tif$", recursive = TRUE, full.names = TRUE)
cat(sprintf("\nhlu1km: %d 个比例基底层（目标 3,688）\n", length(bases2)))
if (length(bases2)) report("lulc/hlu1km", head(bases2, 4))

# 值域检查
cat("\n=== 值域检查 ===\n")
chk_range <- function(f, lo, hi, lab) {
  if (!file.exists(f)) { cat(sprintf("  %-46s 缺\n", lab)); return(invisible()) }
  st <- raster_stats(f)
  ok <- st$min >= lo - 1e-6 && st$max <= hi + 1e-6
  cat(sprintf("  %-46s [%.4g, %.4g] %s\n", lab, st$min, st$max, ifelse(ok, "OK", "OUT OF RANGE")))
}
hf <- list.files(file.path(PATH_COV(), "glo/anthro/hfp"), pattern = "^glo_anthro_hfp_2000.*\\.tif$",
                 recursive = TRUE, full.names = TRUE)
for (f in hf) chk_range(f, 0, 50, basename(f))
