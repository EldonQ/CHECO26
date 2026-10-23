# =============================================================================
# R/02_template.R  --  生成 template_albers1km.tif 与 mask_china.tif
#
# 对应 Python: scripts/01_template.py
#   template: 与模板网格同几何、全 1
#   mask    : china.shp 按 all_touched 口径栅格化（1=境内）
# 两者均为 uint8 且**不设 nodata**（与 Python 版一致；Python 传 nodata=None）
# =============================================================================

suppressPackageStartupMessages({ library(terra) })

source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

#' 写 uint8 GeoTIFF 且不设 nodata（模板/掩膜专用）
write_uint8_nodata_none <- function(dst, r) {
  ensure_dir(dirname(dst))
  tmp <- paste0(sub("\\.tif$", "", dst), ".tmp.tif")
  terra::writeRaster(r, tmp, overwrite = TRUE, datatype = "INT1U",
                     gdal = c("COMPRESS=DEFLATE", "TILED=YES",
                              "BLOCKXSIZE=256", "BLOCKYSIZE=256",
                              "BIGTIFF=IF_SAFER"))
  if (file.exists(dst)) file.remove(dst)
  if (!file.rename(tmp, dst)) stop("rename failed: ", dst)
  invisible(dst)
}

main <- function() {
  g <- GRID()
  data_dir <- PATH_DATA()
  ensure_dir(data_dir)
  cat(sprintf("grid: %d cols x %d rows @ %.0f m\n", g$width, g$height, g$res))

  # ---- template（全 1）----
  tpl <- file.path(data_dir, "template_albers1km.tif")
  t <- g$rast
  terra::values(t) <- 1
  write_uint8_nodata_none(tpl, t)
  cat("written:", tpl, "\n")

  # ---- china.shp -> mask ----
  shp <- P("china_shp")
  if (!file.exists(shp)) stop("china.shp not found: ", shp)
  v <- terra::vect(shp)
  v <- terra::project(v, terra::crs(g$rast))
  n_feat <- nrow(v)
  cat(sprintf("china.shp: %d 要素, 投影后 extent %s\n", n_feat,
              paste(sprintf("%.0f", as.vector(terra::ext(v))), collapse = ", ")))

  all_touched <- isTRUE(CFG()$mask$all_touched)
  m <- terra::rasterize(v, g$rast, field = 1, touches = all_touched,
                        background = 0, filename = "")
  msk <- file.path(data_dir, "mask_china.tif")
  write_uint8_nodata_none(msk, m)
  n_valid <- as.integer(terra::global(m, "sum", na.rm = TRUE)[1, 1])
  cat(sprintf("written: %s | valid cells: %d (%.1f km2)\n",
              msk, n_valid, n_valid * g$res^2 / 1e6))

  # ---- 自检 ----
  ok_t <- check_alignment(tpl)
  ok_m <- check_alignment(msk)
  cat(sprintf("alignment: template=%s mask=%s\n", ok_t, ok_m))
  stopifnot(ok_t, ok_m)

  b <- as.vector(terra::ext(v))
  inside <- b[1] >= g$xmin && b[3] >= g$ymin && b[2] <= g$xmax && b[4] <= g$ymax
  cat(sprintf("china.shp 在模板范围内: %s\n", inside))
  stopifnot(inside)

  append_log(file.path(PATH_LOGS(), "r_lineage.csv"),
             list(relpath = "../data/template_albers1km.tif", source = shp,
                  script = "R/02_template.R", note = "template value=1"))
  append_log(file.path(PATH_LOGS(), "r_lineage.csv"),
             list(relpath = "../data/mask_china.tif", source = shp,
                  script = "R/02_template.R",
                  note = sprintf("all_touched=%s, valid=%d", all_touched, n_valid)))
  cat("R/02_template.R DONE\n")
}

main()
