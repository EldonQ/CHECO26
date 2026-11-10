# =============================================================================
# R/09_derive_dist.R  --  距离面（到最近要素的欧氏距离，米）
#
# 与早期 Python 版 05_derive_dist.py 逐项对齐（该脚本已归档于交付树的 archive/removed_python_pipeline_20261025/）
#
# 产出 5 层：
#   dist/grip4/road       全部道路
#   dist/grip4/majorroad  仅 GP_RTP IN (1,2,3)（Highway/Primary/Secondary）
#   dist/osm/trail        OSM highway IN ('path','footway')
#   dist/smod/urban       GHS-SMOD 城市类 21/22/23（30 arc-sec，max 聚合到 1km）
#   dist/gsw/water        JRC GSW extent 42 片并集
#
# 口径（与 Python 逐项对齐）：
#   * 要素栅格化 all_touched -> terra::rasterize(touches=TRUE)
#   * 距离 = scipy distance_transform_edt(feat == 0) * res，即"到最近要素像元的距离，
#     要素像元本身 = 0" -> terra::distance(x, target = 0)（投影坐标下单位为米）
#   * **距离在全网格计算**（保留境外要素上下文，边界处距离才正确），落盘前才掩膜限回中国
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", Sys.getenv("CHECO_ROOT", getwd())), "R/_bootstrap.R"),
       encoding = "UTF-8")

TASKS <- c("grip4_road", "grip4_majorroad", "osm_trail", "smod_urban", "gsw_water")

# ---- 特征层 -> 距离 --------------------------------------------------------
# dist_from_feature() 定义在 01_common.R，工作示例与生产脚本共用同一实现

# ---- 各要素层 --------------------------------------------------------------
feat_grip4 <- function(major_only = FALSE) {
  src <- file.path(P("grip4_root"), "GRIP4_region6.shp")
  if (!file.exists(src)) stop("GRIP4 not found: ", src)
  v <- terra::vect(src)
  fld <- as.character(CFG()$grip4_field)
  if (major_only) {
    codes <- as.integer(unlist(CFG()$grip4_major_codes))
    # SpatVector 取列：v[[fld]] 可能返回 list，统一用 as.data.frame 取
    vals <- as.integer(as.data.frame(v)[[fld]])
    v <- v[!is.na(vals) & vals %in% codes, ]
  }
  v <- terra::project(v, terra::crs(GRID()$rast))
  m <- terra::rasterize(v, GRID()$rast, field = 1, touches = TRUE,
                        background = 0, filename = "")
  terra::ifel(m == 1, 1, 0)
}

feat_osm_trail <- function() {
  src <- P("osm_pbf")
  if (!file.exists(src)) stop("OSM pbf not found: ", src)
  wh <- as.character(CFG()$osm_trail_where)
  # OGR SQL 下推（等价 pyogrio 的 where=）
  q <- sprintf("SELECT * FROM lines WHERE %s", wh)
  v <- tryCatch(terra::vect(src, query = q), error = function(e) NULL)
  if (is.null(v) || nrow(v) == 0) {
    # 回退：整层读入后再过滤
    v <- terra::vect(src, layer = "lines")
    v <- v[v$highway %in% c("path", "footway"), ]
  }
  if (nrow(v) == 0) stop("OSM trail filter returned 0 features")
  v <- terra::project(v, terra::crs(GRID()$rast))
  m <- terra::rasterize(v, GRID()$rast, field = 1, touches = TRUE,
                        background = 0, filename = "")
  terra::ifel(m == 1, 1, 0)
}

feat_smod_urban <- function() {
  # 该距离层的定义是"到 GHS-SMOD 2020 城市类 21/22/23 的距离"（见溯源表）。
  # smod_epochs 是逐年 urbanprop 层的全集（1975-2030），取末值会得到 2030，
  # 与图层定义不符（2026-11-10 修正）。改读专用键 dist_smod_epoch。
  ep <- as.integer(unlist(CFG()$dist_smod_epoch))[1]
  if (is.na(ep)) stop("config: dist_smod_epoch missing")
  d <- sprintf("GHS_SMOD_E%d_GLOBE_R2023A_4326_30ss_V2_0", ep)
  src <- file.path(P("smod_ghs"), d, paste0(d, ".tif"))
  if (!file.exists(src)) stop("SMOD not found: ", src)
  urban <- as.integer(unlist(CFG()$smmod_urban_classes))

  # 与 Python 一致：先按经纬度窗口裁切，再 max 聚合到 1km
  win <- c(72.5, 17.0, 136.5, 55.5)
  r <- terra::crop(terra::rast(src), terra::ext(win[1], win[3], win[2], win[4]), snap = "out")
  v <- terra::values(r, mat = FALSE)
  nd <- terra::NAflag(r)
  ind <- rep(NA_integer_, length(v))
  valid <- !is.na(v)
  if (!is.na(nd)) valid <- valid & v != nd
  ind[valid] <- as.integer(v[valid] %in% urban)
  terra::values(r) <- ind

  # 源特征栅格 -> 模板，Resampling.max（任一源像元为城市则目标=1）
  tmp <- file.path(PATH_SCRATCH(), "dist_feat", "smod_urban_src.tif")
  ensure_dir(dirname(tmp))
  terra::writeRaster(r, tmp, overwrite = TRUE, datatype = "INT1U")
  out <- terra::project(terra::rast(tmp), GRID()$rast,
                        method = terra_method("max"), align = FALSE)
  unlink(tmp)
  terra::ifel(out >= 1, 1, 0)
}

feat_gsw_water <- function() {
  invalid <- as.integer(CFG()$gsw_invalid_value)
  tiles <- sort(Sys.glob(file.path(P("gsw_extent"), "extent_*.tif")))
  if (length(tiles) != 42) stop("GSW extent tiles != 42: ", length(tiles))
  union <- GRID()$rast
  terra::values(union) <- 0
  for (t in tiles) {
    dst <- terra::project(terra::rast(t), GRID()$rast,
                          method = terra_method("nearest"), align = FALSE)
    v <- terra::values(dst, mat = FALSE)
    hit <- !is.na(v) & v > 0 & v != invalid
    terra::values(dst) <- as.integer(hit)
    union <- terra::ifel(terra::ifel(dst == 1, 1, 0) > terra::ifel(union == 1, 1, 0),
                         1, terra::ifel(union == 1, 1, 0))
  }
  union
}

# ---- 单任务 --------------------------------------------------------------
run_task <- function(tag) {
  dst <- switch(tag,
    grip4_road      = layer_path(c("reg", "dist", "grip4", "road")),
    grip4_majorroad = layer_path(c("reg", "dist", "grip4", "majorroad")),
    osm_trail       = layer_path(c("reg", "dist", "osm", "trail")),
    smod_urban      = layer_path(c("reg", "dist", "smod", "urban")),
    gsw_water       = layer_path(c("reg", "dist", "gsw", "water")))
  if (file.exists(dst) && !identical(Sys.getenv("CHECO_FORCE"), "1") && check_alignment(dst))
    return(list(status = "skip", dst = dst))

  t0 <- Sys.time()
  feat <- switch(tag,
    grip4_road      = feat_grip4(FALSE),
    grip4_majorroad = feat_grip4(TRUE),
    osm_trail       = feat_osm_trail(),
    smod_urban      = feat_smod_urban(),
    gsw_water       = feat_gsw_water())
  nfeat <- as.integer(terra::global(feat, "sum", na.rm = TRUE)[1, 1])
  if (nfeat == 0) return(list(status = "error", dst = dst, note = "feature raster empty"))

  d <- dist_from_feature(feat)
  d <- apply_china_mask(d, NA)
  atomic_write_raster(dst, d, dtype = "float32")
  if (!check_alignment(dst)) return(list(status = "error", dst = dst, note = "alignment"))
  st <- raster_stats(dst)
  list(status = "ok", dst = dst, nfeat = nfeat, vmin = st$min, vmax = st$max,
       sec = as.numeric(difftime(Sys.time(), t0, units = "secs")))
}

main <- function(only = NULL) {
  print_grid()
  tasks <- if (is.null(only)) TASKS else intersect(TASKS, only)
  for (tag in tasks) {
    r <- tryCatch(run_task(tag), error = function(e) list(status = "error", note = conditionMessage(e)))
    if (identical(r$status, "error")) cat(sprintf("  %-16s ERROR : %s\n", tag, r$note))
    else if (identical(r$status, "skip")) cat(sprintf("  %-16s skip\n", tag))
    else cat(sprintf("  %-16s ok   nfeat=%s  [%.1f, %.1f]  %.0f 秒\n",
                     tag, format(r$nfeat, big.mark = ","), r$vmin, r$vmax, r$sec))
  }
  invisible(NULL)
}

if (sys.nframe() == 0L) main()
