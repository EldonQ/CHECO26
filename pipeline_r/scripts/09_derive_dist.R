# =============================================================================
# R/09_derive_dist.R  --  距离面（到最近要素的欧氏距离，米）
#
# 对应 Python: scripts/05_derive_dist.py
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
#' 与 Python dist_from_feature (scipy distance_transform_edt) 等价。
#'
#' **terra::distance 的语义（2026-10-19 最小用例实测确认）**：
#'   它算的是「到最近**非 NA** 像元」的距离。
#'   因此必须把要素之外的像元全部置 NA，要素保留为数值；
#'   若传 0/1 栅格（无 NA），结果毫无意义（实测中心反成 1000、其余全 0）。
#'   按正确用法，结果与解析值精确吻合：
#'     相邻 1000、对角 1000*sqrt(2)=1414.2、边角 1000*sqrt(50)=7071.1
dist_from_feature <- function(feat) {
  x <- terra::ifel(feat == 1, 1, NA)
  terra::distance(x, unit = "m")
}

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
  ep <- as.integer(unlist(CFG()$smod_epochs))[1]   # Python: SMOD_EPOCH 单值
  # 与 Python 一致：取 SMOD_EPOCH。config 里 smod_epochs 是列表，取最后一个（2020）
  ep <- tail(as.integer(unlist(CFG()$smod_epochs)), 1)
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
    grip4_road      = layer_path(c("glo", "dist", "grip4", "road")),
    grip4_majorroad = layer_path(c("glo", "dist", "grip4", "majorroad")),
    osm_trail       = layer_path(c("glo", "dist", "osm", "trail")),
    smod_urban      = layer_path(c("glo", "dist", "smod", "urban")),
    gsw_water       = layer_path(c("glo", "dist", "gsw", "water")))
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
