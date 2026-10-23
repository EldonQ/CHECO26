# =============================================================================
# R/02b_hydro_stats.R  --  hydro 精选统计增补（窗口极值）
#
# 对应 Python: scripts/02b_hydro_stats_addon.py
#
# 产出 18 层（config hydro_stats_addon，撤出变量已排除）：
#   minmax 组  8 变量 x (min,max) = 16
#     stream_dist_proximity / stream_dist_dw_near / stream_dist_up_near
#     stream_dist_up_farth / channel_elv_dw_cel / channel_elv_dw_seg
#     channel_elv_up_cel / channel_elv_up_seg
#   maxonly 组 2 变量 x max = 2   （spi, sti；cti 已撤出）
#
# 口径：
#   * 重采样 = config.resampling.downscale_min / downscale_max（GDAL min/max）
#   * src_nodata = -9999，scale 取 hydro90m_vars.scale_by_var
#   * **必须掩膜源哨兵**：Python 版 worker 虽构造了 sentinel 字段却未使用，
#     交付层的实际值是 2026-10-18 r13 修复后重生成的干净结果；
#     本脚本显式掩膜，保证与交付层一致（channel_elv_up_cel_max 应 ~986 m 而非 ~1e5）
#   * 入库前方差筛查：相对跨度 < 1e-6 视为常量层并拒绝
#   * stream_dist_* 归 dist 主题，其余归 hydro 主题（与 03 一致）
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", Sys.getenv("CHECO_ROOT", getwd())), "R/_bootstrap.R"),
       encoding = "UTF-8")

DIST_VARS <- c("stream_dist_proximity", "stream_dist_dw_near",
               "stream_dist_up_near", "stream_dist_up_farth")

build_manifest <- function() {
  cfg <- CFG()
  addon <- cfg$hydro_stats_addon
  smap <- if (is.null(cfg$hydro90m_vars$scale_by_var)) list() else cfg$hydro90m_vars$scale_by_var
  sent <- if (is.null(cfg$hydro90m_vars$src_sentinel)) list() else cfg$hydro90m_vars$src_sentinel
  withdrawn <- unlist(cfg$hydro90m_vars$withdrawn)
  tasks <- list()
  add <- function(v, st) {
    if (v %in% withdrawn) return(invisible())
    parts <- if (v %in% DIST_VARS) c("glo", "dist", "h90m", gsub("_", "-", v))
             else c("glo", "hydro", "h90m", gsub("_", "-", v))
    tasks[[length(tasks) + 1L]] <<- list(
      parts = parts, suffix = paste0("_", st), var = v, stat = st,
      src = file.path(P("hydro_final"), v, sprintf("%s_china.tif", v)),
      scale = if (!is.null(smap[[v]])) as.numeric(smap[[v]]) else NULL,
      sentinel = if (!is.null(sent[[v]])) as.numeric(sent[[v]]) else NULL)
  }
  for (v in unlist(addon$minmax)) { add(v, "min"); add(v, "max") }
  for (v in unlist(addon$maxonly)) add(v, "max")
  tasks
}

run_task <- function(t) {
  cfg <- CFG()
  dst <- layer_path(t$parts, t$suffix)
  if (file.exists(dst) && !identical(Sys.getenv("CHECO_FORCE"), "1") && check_alignment(dst))
    return(list(status = "skip", dst = dst, var = t$var, stat = t$stat))
  if (!file.exists(t$src))
    return(list(status = "error", dst = dst, var = t$var, stat = t$stat, note = "src missing"))

  src <- t$src
  if (!is.null(t$sentinel))
    src <- mask_source_sentinel(src, t$sentinel, sub("\\.tif$", "", basename(dst)))

  method <- cfg$resampling[[paste0("downscale_", t$stat)]]
  warp_to_template(src, dst, method = method, src_nodata = -9999, scale = t$scale)
  if (!check_alignment(dst))
    return(list(status = "error", dst = dst, var = t$var, stat = t$stat, note = "alignment"))

  st <- raster_stats(dst)
  if (st$n == 0) return(list(status = "error", dst = dst, var = t$var, stat = t$stat, note = "empty"))
  span <- st$max - st$min
  rel <- span / max(abs(st$max), 1e-9)
  if (rel < 1e-6)
    return(list(status = "error", dst = dst, var = t$var, stat = t$stat,
                note = sprintf("near-constant rejected [%.6g, %.6g]", st$min, st$max)))
  list(status = "ok", dst = dst, var = t$var, stat = t$stat, n = st$n,
       vmin = st$min, vmax = st$max)
}

main <- function(shard = 1L, nshard = 1L) {
  print_grid()
  tasks <- build_manifest()
  if (nshard > 1L) tasks <- tasks[seq.int(shard, length(tasks), by = nshard)]
  cat(sprintf("hydro stats addon: 本片 %d 任务（总 %d 应为 18）\n",
              length(tasks), length(build_manifest())))
  t0 <- Sys.time(); nok <- 0L; nskip <- 0L; nerr <- 0L
  for (t in tasks) {
    r <- tryCatch(run_task(t), error = function(e) list(status = "error", note = conditionMessage(e),
                                                        var = t$var, stat = t$stat))
    if (identical(r$status, "ok")) { nok <- nok + 1L
      cat(sprintf("  ok   %-24s %-3s n=%s [%.4g, %.4g]\n", r$var, r$stat,
                  format(r$n, big.mark = ","), r$vmin, r$vmax))
    } else if (identical(r$status, "skip")) { nskip <- nskip + 1L
      cat(sprintf("  skip %-24s %-3s\n", r$var, r$stat))
    } else { nerr <- nerr + 1L
      cat(sprintf("  ERR  %-24s %-3s %s\n", r$var, r$stat, r$note)) }
  }
  cat(sprintf("\n汇总: ok=%d skip=%d err=%d, %.0f 秒\n", nok, nskip, nerr,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  invisible(list(ok = nok, skip = nskip, err = nerr))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) as.integer(a[1]) else 1L,
       if (length(a) >= 2) as.integer(a[2]) else 1L)
}
