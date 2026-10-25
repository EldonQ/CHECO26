# =============================================================================
# R/03_ingest_static.R  --  静态主题入库
#
# 与早期 Python 版 02_ingest_static.py 逐项对齐（该脚本已归档于交付树的 archive/removed_python_pipeline_20261025/）
#   本脚本负责的基底（不含焦点、不含派生统计）：
#     bioclim 28  (0.01° WGS84 -> 1km Albers, bilinear)
#     soil   168  (28 属性 x 6 深度, 1km, int16, scale 见 units_scale)
#     topo     2  (elev, slope)
#     hydro   40  (h90m continuous 30 + categorical 10; 撤出变量跳过)
#     vege     3  (agb, ch, treecover)
#     合计   241
#
# 复现要点（与 Python 逐项对齐）：
#   * rule -> resampling 的映射全部来自 config.yaml:resampling
#   * src_nodata / scale 与 Python 任务清单逐项一致
#   * hydro 的 99999 哨兵必须先在源上清成 nodata 再聚合
#   * 幂等：目标已存在且四查通过则跳过（CHECO_FORCE=1 可强制重跑）
# =============================================================================

suppressPackageStartupMessages({ library(terra) })

source(file.path(Sys.getenv("CHECO_ROOT", Sys.getenv("CHECO_ROOT", getwd())), "R/_bootstrap.R"),
       encoding = "UTF-8")

# ---- 常量（与 Python 完全一致） --------------------------------------------
BIOCLIM_VARS <- c(sprintf("bio%02d", 1:23), "prec", "sunp", "tave", "tmax", "tmin")

SOIL_DEPTHS <- list(c("0-5", "0"), c("5-15", "5"), c("15-30", "15"),
                    c("30-60", "30"), c("60-100", "60"), c("100-200", "100"))

SOIL_ATTR_DIR <- c(
  AK = "ak", AN = "an", AP = "ap", BD = "bd", CEC = "cec",
  Dry_B = "dry-b", Dry_G = "dry-g", Dry_R = "dry-r",
  Dry_chroma = "dry-chroma", Dry_hue = "dry-hue", Dry_value = "dry-value",
  OC = "oc", SOCD = "socd", TK = "tk", TN = "tn", TP = "tp",
  Wet_B = "wet-b", Wet_G = "wet-g", Wet_R = "wet-r",
  Wet_chroma = "wet-chroma", Wet_hue = "wet-hue", Wet_value = "wet-value",
  clay = "clay", gravel = "gravel", pH = "ph", porosity = "porosity",
  sand = "sand", silt = "silt"
)

DIST_VARS <- c("stream_dist_proximity", "stream_dist_dw_near",
               "stream_dist_up_near", "stream_dist_up_farth")

# ---- 任务清单 --------------------------------------------------------------
build_manifest <- function() {
  cfg <- CFG(); us <- cfg$units_scale$soil_csdlv2
  hcfg <- cfg$hydro90m_vars
  scale_map <- if (is.null(hcfg$scale_by_var)) list() else hcfg$scale_by_var
  cm_exc    <- if (is.null(hcfg$scale_cm_exception)) list() else hcfg$scale_cm_exception
  sent_map  <- if (is.null(hcfg$src_sentinel)) list() else hcfg$src_sentinel
  withdrawn <- unlist(hcfg$withdrawn)
  tasks <- list()

  # bioclim 28
  for (v in BIOCLIM_VARS) {
    tasks[[length(tasks) + 1L]] <- list(
      parts = c("glo", "bioclim", "cnclim1km", "present", v),
      src = file.path(P("bioclim"), "cnclim1km/present/1991_2020", v,
                      sprintf("bioclim_cnclim1km_present_1991_2020_%s.tif", v)),
      rule = "continuous", scale = NULL, src_nodata = NULL, sentinel = NULL)
  }

  # soil 168
  for (attr in names(SOIL_ATTR_DIR)) {
    adir <- SOIL_ATTR_DIR[[attr]]
    sc <- if (!is.null(us[[attr]])) as.numeric(us[[attr]]) else as.numeric(us$default)
    for (dd in SOIL_DEPTHS) {
      dsrc <- dd[1]; dname <- dd[2]
      hits <- Sys.glob(file.path(P("soil_1km"), "GTiff", attr,
                                 sprintf("%s_%scm_1km*.tif", attr, dsrc)))
      hits <- hits[!grepl("\\.aux\\.xml$", hits)]
      if (length(hits) != 1L)
        stop(sprintf("soil source ambiguous/missing: %s %s -> %d hits", attr, dsrc, length(hits)))
      tasks[[length(tasks) + 1L]] <- list(
        parts = c("glo", "soil", "csdlv2", adir, dname),
        src = hits[[1]], rule = "continuous", scale = sc,
        src_nodata = -32768, sentinel = NULL)
    }
  }

  # topo 2
  tasks[[length(tasks) + 1L]] <- list(
    parts = c("glo", "topo", "chinadem", "elev"),
    src = "E:/CHECO26/DEM/China_DEM_1km/Albers_105/DEM/chdem_105.tif",
    rule = "continuous", scale = NULL, src_nodata = -32768, sentinel = NULL)
  tasks[[length(tasks) + 1L]] <- list(
    parts = c("glo", "topo", "chinadem", "slope"),
    src = "E:/CHECO26/DEM/China_DEM_1km/Albers_105/TIFF/chdem_Slope.tif",
    rule = "continuous", scale = NULL, src_nodata = NULL, sentinel = NULL)

  # hydro 40
  for (v in c(unlist(hcfg$categorical), unlist(hcfg$continuous))) {
    if (v %in% withdrawn) next
    src <- file.path(P("hydro_final"), v, sprintf("%s_china.tif", v))
    is_cat <- v %in% unlist(hcfg$categorical)
    parts <- if (v %in% DIST_VARS) {
      c("glo", "dist", "h90m", gsub("_", "-", v))
    } else c("glo", "hydro", "h90m", gsub("_", "-", v))
    sc <- NULL
    if (!is.null(cm_exc[[v]])) sc <- as.numeric(cm_exc[[v]])
    else if (!is.null(scale_map[[v]])) sc <- as.numeric(scale_map[[v]])
    tasks[[length(tasks) + 1L]] <- list(
      parts = parts, src = src,
      rule = if (is_cat) "downscale_categorical" else "downscale_continuous",
      scale = sc,
      sentinel = if (!is.null(sent_map[[v]])) as.numeric(sent_map[[v]]) else NULL,
      src_nodata = if (is_cat) NULL else -9999)
  }

  # vege 3
  tasks[[length(tasks) + 1L]] <- list(
    parts = c("glo", "vege", "agb2019", "agb"),
    src = file.path(P("agb"), "China_Forest_AGB_2019.tif"),
    rule = "downscale_continuous", scale = NULL, src_nodata = NULL, sentinel = NULL)
  tasks[[length(tasks) + 1L]] <- list(
    parts = c("glo", "vege", "ch2019", "ch"),
    src = file.path(P("canopy_height"), "China_Forest_Canopy_Height_2019.tif"),
    rule = "downscale_continuous", scale = as.numeric(CFG()$units_scale$canopy_height),
    src_nodata = 65535, sentinel = NULL)
  tasks[[length(tasks) + 1L]] <- list(
    parts = c("glo", "vege", "catcd", "treecover"),
    src = P("catcd"), rule = "downscale_continuous", scale = NULL,
    src_nodata = -128, sentinel = NULL)

  tasks
}

# ---- 源哨兵清理 ------------------------------------------------------------
#' 把源中 >= sentinel 的值改成 nodata，再交给聚合。
#' （Hydrography90m 的 channel_elv_up_cel 用 99999 标记出口像元，但该哨兵被 GRASS
#'  累加扩散，实测 >50000 的像元区间为 [99,838, 105,245]，故阈值取 50,000 下界）
#'
#' 缓存键包含阈值：阈值一变必须重算，否则会命中旧缓存（2026-10-19 踩过）。
mask_source_sentinel <- function(src, sentinel, tag) {
  if (is.null(sentinel) || is.na(sentinel)) return(src)
  dst <- file.path(PATH_SCRATCH(), "sentinel_masked",
                   sprintf("%s__ge%.0f.tif", tag, sentinel))
  if (file.exists(dst)) return(dst)
  ensure_dir(dirname(dst))
  r <- terra::rast(src)
  v <- terra::values(r, mat = FALSE)
  nd <- terra::NAflag(r)
  bad <- !is.na(v) & v >= sentinel
  n <- sum(bad)
  if (n > 0) v[bad] <- if (is.na(nd)) NODATA() else nd
  terra::values(r) <- v
  if (is.na(nd)) { terra::NAflag(r) <- NODATA() }
  terra::writeRaster(r, dst, overwrite = TRUE,
                     datatype = .dtype_map[[if (terra::is.int(r)) "int32" else "float32"]])
  cat(sprintf("  sentinel %.8g masked in %d source pixels -> %s\n", sentinel, n, basename(dst)))
  dst
}

# ---- 单任务 ----------------------------------------------------------------
run_task <- function(t) {
  cfg <- CFG()
  dst <- layer_path(t$parts)
  method <- cfg$resampling[[t$rule]]
  force <- identical(Sys.getenv("CHECO_FORCE"), "1")
  if (file.exists(dst) && !force && check_alignment(dst)) {
    return(list(status = "skip", dst = dst))
  }
  src <- t$src
  if (!is.null(t$sentinel)) src <- mask_source_sentinel(src, t$sentinel,
                                                       sub("\\.tif$", "", basename(dst)))
  if (!file.exists(src)) return(list(status = "error", dst = dst, note = paste("src missing:", src)))
  warp_to_template(src, dst, method = method, src_nodata = t$src_nodata,
                   scale = t$scale)
  if (!check_alignment(dst)) return(list(status = "error", dst = dst, note = "alignment failed"))
  st <- raster_stats(dst)
  list(status = "ok", dst = dst, n = st$n, vmin = st$min, vmax = st$max)
}

main <- function(only = NULL) {
  print_grid()
  tasks <- build_manifest()
  cat(sprintf("\nmanifest: %d 层\n", length(tasks)))
  names_ <- vapply(tasks, function(t) basename(layer_path(t$parts)), "")
  if (anyDuplicated(names_)) stop("duplicate target filenames!")
  if (!is.null(only)) tasks <- tasks[grepl(only, names_)]

  res <- vector("list", length(tasks))
  t0 <- Sys.time()
  for (i in seq_along(tasks)) {
    r <- tryCatch(run_task(tasks[[i]]),
                  error = function(e) list(status = "error", dst = layer_path(tasks[[i]]$parts),
                                           note = conditionMessage(e)))
    res[[i]] <- r
    if (i %% 20 == 0 || i == length(tasks)) {
      el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
      cat(sprintf("  %4d / %d  (%.0fs)\n", i, length(tasks), el))
    }
  }
  st <- table(vapply(res, function(r) r$status, ""))
  cat("\n=== 汇总 ===\n"); print(st)
  errs <- Filter(function(r) identical(r$status, "error"), res)
  if (length(errs)) {
    cat("失败项:\n")
    for (e in head(errs, 20)) cat("  ", e$dst, "|", e$note, "\n")
  }
  invisible(res)
}

if (sys.nframe() == 0L) main()
