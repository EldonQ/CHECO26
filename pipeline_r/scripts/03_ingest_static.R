# =============================================================================
# R/03_ingest_static.R  --  静态主题入库
#
# 与早期 Python 版 02_ingest_static.py 逐项对齐（该脚本已归档于 archive/removed_python_pipeline_20261025/）
#   本脚本负责的基底（不含焦点、不含派生统计）：
#     bioclim 28  (0.01° WGS84 -> 1km Albers, bilinear)
#     soil   168  (28 属性 x 6 深度, 1km, int16, scale 见 units_scale)
#     topo     2  (elev, slope)
#     hydro  32  (legacy native source route, stage 19)
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

source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

# ---- 常量（与 Python 完全一致） --------------------------------------------
BIOCLIM_VARS <- c(sprintf("bio%02d", 1:as.integer(CFG()$climate$n_bio)),
                  as.character(unlist(CFG()$climate$extra_vars)))

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

# ---- 任务清单 --------------------------------------------------------------
build_manifest <- function() {
  cfg <- CFG(); us <- cfg$units_scale$soil_csdlv2
  tasks <- list()

  # bioclim 22 (CHELSA v2.1, 1981-2010, 30" WGS84 -> 1km Albers, bilinear)
  # terra 自动施加 CHELSA scale/offset → 物理单位；bio03 额外 ×bio03_scale 转百分数
  clim <- CFG()$climate
  bds <- as.character(clim$source)
  bpp <- as.character(clim$present_period)
  b03sc <- as.numeric(clim$bio03_scale)
  cw <- as.numeric(unlist(clim$crop_lonlat))
  bcrop <- terra::ext(cw[1], cw[2], cw[3], cw[4])
  for (v in BIOCLIM_VARS) {
    tasks[[length(tasks) + 1L]] <- list(
      parts = c("reg", "bioclim", bds, "present", v),
      src = file.path(P("chelsa"), "bioclim", v, bpp,
                      sprintf("CHELSA_%s_%s_V.2.1.tif", v, bpp)),
      rule = "continuous", scale = if (v == "bio03") b03sc else NULL,
      src_nodata = NULL, sentinel = NULL, crop_ext = bcrop)
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
        parts = c("reg", "soil", "csdlv2", adir, dname),
        src = hits[[1]], rule = "continuous", scale = sc,
        src_nodata = -32768, sentinel = NULL)
    }
  }

  # vege 3
  tasks[[length(tasks) + 1L]] <- list(
    parts = c("reg", "vege", "agb2019", "agb"),
    src = file.path(P("agb"), "China_Forest_AGB_2019.tif"),
    rule = "downscale_continuous", scale = NULL, src_nodata = NULL, sentinel = NULL)
  tasks[[length(tasks) + 1L]] <- list(
    parts = c("reg", "vege", "ch2019", "ch"),
    src = file.path(P("canopy_height"), "China_Forest_Canopy_Height_2019.tif"),
    rule = "downscale_continuous", scale = as.numeric(CFG()$units_scale$canopy_height),
    src_nodata = 65535, sentinel = NULL)
  tasks[[length(tasks) + 1L]] <- list(
    parts = c("reg", "vege", "catcd", "treecover"),
    src = P("catcd"), rule = "downscale_continuous", scale = NULL,
    src_nodata = -128, sentinel = NULL)

  tasks
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
  if (!file.exists(src)) return(list(status = "error", dst = dst, note = paste("src missing:", src)))
  warp_to_template(src, dst, method = method, src_nodata = t$src_nodata,
                   scale = t$scale, crop_ext = t$crop_ext)
  if (!check_alignment(dst)) return(list(status = "error", dst = dst, note = "alignment failed"))
  st <- raster_stats(dst)
  list(status = "ok", dst = dst, n = st$n, vmin = st$min, vmax = st$max)
}

main <- function(only = NULL, include_h90m = TRUE) {
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
  if (length(errs)) stop(length(errs), " static inputs failed")
  if (include_h90m) {
    legacy <- new.env(parent = globalenv())
    sys.source(file.path(R_DIR, "19_rebuild_h90m_legacy.R"), envir = legacy)
    available <- legacy$h90m_legacy_manifest()
    targets <- vapply(available, function(t) basename(layer_path(t$parts)), "")
    names <- names(available)
    if (!is.null(only)) names <- names[grepl(only, targets)]
    if (length(names)) legacy$rebuild_h90m_legacy(names, c("average", "mode"))
  }
  invisible(res)
}

if (sys.nframe() == 0L) main()
