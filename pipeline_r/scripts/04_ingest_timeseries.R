# =============================================================================
# R/04_ingest_timeseries.R  --  时序主题入库 + 全部焦点窗口
#
# 对应 Python: scripts/03_ingest_timeseries.py
#
# 相对早期 Python 版的变更：
#   * footHII（100 层）**不再生成**，改由 anthro/hfp（Mu 版 HFP 2000-2024，125 层）承担
#     —— 依据：footHII 非开源可再分发风险 + 两套 HFP 标度并存；见 LICENCE_MATRIX.md
#   * 新增 hfp：Mollweide 1km float32 -> 1km Albers，average，无缩放
#
# 本脚本产出：
#   anthro/hfp     25 年 x (1 + 4 focal) = 125
#   anthro/smod    12 epoch x 1          =  12   （城市化比例，无焦点，与 Python 一致）
#   vege/glassndvi  3 年 x (1 + 4 focal) =  15
#   vege 静态 3 变量的焦点               =  12   （agb/ch/treecover x 4）
#   合计 164
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", Sys.getenv("CHECO_ROOT", getwd())), "R/_bootstrap.R"),
       encoding = "UTF-8")

# ---- 焦点任务：由基底层派生 ----
#' 返回 list(parts, base, suffix)；parts 与 base 相同（焦点层与基底同目录），
#' 但两者分开保留，便于 run_task 统一用 layer_path(parts, suffix) 定位目标文件。
focal_tasks <- function(base_parts) {
  fs <- FOCAL_SPEC()
  lapply(seq_len(nrow(fs)), function(i)
    list(parts = base_parts, base = base_parts, suffix = fs$suffix[i]))
}

build_manifest <- function() {
  # 注意：不要在这里定义名为 P 的局部函数——会遮蔽 00_config.R 的 P() 并造成无限递归
  cfg <- CFG()
  tasks <- list()
  add <- function(x) tasks[[length(tasks) + 1L]] <<- x

  # ---- anthro/hfp 2000-2024：基底 + 4 焦点 ----
  # 源：archive/hfp/HFP-2000-2018/16571064/hfpYYYY/hfpYYYY.tif
  hfp_root <- file.path(PATH_ARCHIVE(), "hfp", "HFP-2000-2018", "16571064")
  years <- 2000:2024
  for (y in years) {
    src <- file.path(hfp_root, sprintf("hfp%d", y), sprintf("hfp%d.tif", y))
    parts <- c("glo", "anthro", "hfp", as.character(y), "hfp")
    add(list(kind = "warp", parts = parts, suffix = "", src = src,
             rule = "downscale_continuous", scale = NULL, src_nodata = NULL))
    for (f in focal_tasks(parts)) add(list(kind = "focal", parts = f$parts, base = f$base, suffix = f$suffix))
  }

  # ---- anthro/smod 12 epoch：城市化比例（无焦点）----
  for (y in as.integer(unlist(cfg$smod_epochs))) {
    d <- sprintf("GHS_SMOD_E%d_GLOBE_R2023A_4326_30ss_V2_0", y)
    add(list(kind = "smod",
             parts = c("glo", "anthro", "smod", as.character(y), "urbanprop"),
             suffix = "", src = file.path(P("smod_ghs"), d, paste0(d, ".tif"))))
  }

  # ---- vege/glassndvi 2020-2022：基底 + 4 焦点 ----
  for (y in as.integer(unlist(cfg$ndvi_years))) {
    src <- file.path(P("ndvi_30m"), as.character(y), sprintf("NDVImax%d.tif", y))
    parts <- c("glo", "vege", "glassndvi", as.character(y), "ndvimax")
    add(list(kind = "warp", parts = parts, suffix = "", src = src,
             rule = "downscale_continuous",
             scale = as.numeric(cfg$units_scale$ndvi), src_nodata = 32767))
    for (f in focal_tasks(parts)) add(list(kind = "focal", parts = f$parts, base = f$base, suffix = f$suffix))
  }

  # ---- vege 静态 3 变量的焦点（基底由 03 生产）----
  for (bp in list(c("glo", "vege", "catcd", "treecover"),
                  c("glo", "vege", "ch2019", "ch"),
                  c("glo", "vege", "agb2019", "agb"))) {
    for (f in focal_tasks(bp)) add(list(kind = "focal", parts = f$parts, base = f$base, suffix = f$suffix))
  }
  tasks
}

# ---- SMOD 城市化比例 -------------------------------------------------------
#' 30 arc-sec 分类层 -> 城市类(21/22/23)=1 的指示层（截取中国窗口）-> average 聚合 = 比例
do_smod <- function(t) {
  cfg <- CFG()
  dst <- layer_path(t$parts, t$suffix)
  urban <- as.integer(unlist(cfg$smmod_urban_classes))
  win <- c(72.5, 17.0, 136.5, 55.5)   # 与 Python SMOD_WINDOW 一致

  r <- terra::rast(t$src)
  # 先按经纬度窗口裁切（源是全球 30 arc-sec，直接投影太慢）
  e <- terra::ext(win[1], win[3], win[2], win[4])
  sub <- terra::crop(r, e, snap = "out")
  v <- terra::values(sub, mat = FALSE)
  nd <- terra::NAflag(sub)
  ind <- rep(255L, length(v))
  valid <- !is.na(v)
  if (!is.na(nd)) valid <- valid & v != nd
  ind[valid] <- as.integer(v[valid] %in% urban)
  terra::values(sub) <- ind
  terra::NAflag(sub) <- 255

  tmp <- file.path(PATH_SCRATCH(), "smod_ind", paste0(sub("\\.tif$", "", basename(dst)), ".tif"))
  ensure_dir(dirname(tmp))
  terra::writeRaster(sub, tmp, overwrite = TRUE, datatype = "INT1U")

  warp_to_template(tmp, dst, method = cfg$resampling$downscale_continuous,
                   src_nodata = 255, scale = NULL)
  if (file.exists(tmp)) file.remove(tmp)
  dst
}

run_task <- function(t) {
  cfg <- CFG()
  dst <- layer_path(t$parts, t$suffix)
  force <- identical(Sys.getenv("CHECO_FORCE"), "1")
  if (file.exists(dst) && !force && check_alignment(dst))
    return(list(status = "skip", dst = dst))

  if (t$kind == "focal") {
    base <- layer_path(t$base, "")
    if (!file.exists(base)) return(list(status = "pending", dst = dst, note = "base not ready"))
    b <- terra::rast(base)
    # 基底层的无效值统一为 NA 后做焦点
    nd <- terra::NAflag(b)
    v <- terra::values(b, mat = FALSE)
    if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
    v[is.nan(v)] <- NA
    terra::values(b) <- v
    # 后缀是**米数**（_f1000 = 1 km），半径（格）= 米数 / 分辨率。
    # 曾经多除了一次 1000，导致 _f1000 -> 0.001 -> round 0 -> 1x1 窗口，
    # terra 报 "[focal] not a meanigful window"（2026-10-19）。
    rc <- as.integer(round(as.numeric(sub("_f", "", t$suffix)) /
                           as.numeric(cfg$grid$resolution)))
    if (is.na(rc) || rc < 1L)
      return(list(status = "error", dst = dst,
                  note = sprintf("bad focal suffix %s -> radius_cells %s", t$suffix, rc)))
    out <- focal_mean(b, rc)
    out <- apply_china_mask(out, NA)
    atomic_write_raster(dst, out, dtype = "float32")
  } else if (t$kind == "smod") {
    do_smod(t)
  } else {
    warp_to_template(t$src, dst, method = cfg$resampling[[t$rule]],
                     src_nodata = t$src_nodata, scale = t$scale)
  }
  if (!check_alignment(dst)) return(list(status = "error", dst = dst, note = "alignment failed"))
  st <- raster_stats(dst)
  list(status = "ok", dst = dst, n = st$n, vmin = st$min, vmax = st$max)
}

main <- function(only = NULL) {
  print_grid()
  tasks <- build_manifest()
  cat(sprintf("\nmanifest: %d 层\n", length(tasks)))
  nm <- vapply(tasks, function(t) basename(layer_path(t$parts, t$suffix)), "")
  if (anyDuplicated(nm)) stop("duplicate target filenames!")
  if (!is.null(only)) tasks <- tasks[grepl(only, nm)]

  # 两轮：先非焦点，再焦点（focal 依赖基底）
  ord <- c(which(vapply(tasks, function(t) t$kind != "focal", TRUE)),
           which(vapply(tasks, function(t) t$kind == "focal", TRUE)))
  tasks <- tasks[ord]

  res <- vector("list", length(tasks)); t0 <- Sys.time()
  for (i in seq_along(tasks)) {
    res[[i]] <- tryCatch(run_task(tasks[[i]]),
                         error = function(e) list(status = "error",
                                                  dst = layer_path(tasks[[i]]$parts, tasks[[i]]$suffix),
                                                  note = conditionMessage(e)))
    if (i %% 20 == 0 || i == length(tasks)) {
      cat(sprintf("  %4d / %d  (%.0fs)\n", i, length(tasks),
                  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    }
  }
  cat("\n=== 汇总 ===\n"); print(table(vapply(res, function(r) r$status, "")))
  errs <- Filter(function(r) identical(r$status, "error"), res)
  if (length(errs)) for (e in head(errs, 20)) cat("  ", e$dst, "|", e$note, "\n")
  invisible(res)
}

if (sys.nframe() == 0L) main()
