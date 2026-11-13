# =============================================================================
# R/10_future_chains.R  --  bioclim 未来情景链（CHELSA v2.1，1,188 层）
#
# 2026-11-12 起改用 CHELSA v2.1，替代 cnclim1km（旧版 bio02/03/05/06/07 为月极值
# 口径，非标准；CHELSA 为标准 BioClim 口径，CC BY 4.0）。
#
# 目录口径（N-SDM 2.0.1）：
#   reg/bioclim/chelsa21-<chain>/scenario/<cyear>/<ssp>/<var>/
#
# 组合：6 链 × 3 时段 × 3 SSP × 22 变量 = 1,188
#   链   : gfdl-esm4 / ipsl-cm6a-lr / mpi-esm1-2-hr / mri-esm2-0 / ukesm1-0-ll / ensmean
#   时段 : 2025 -> 2011-2040 ; 2055 -> 2041-2070 ; 2085 -> 2071-2100
#   SSP  : ssp126 / ssp370 / ssp585
#   变量 : bio01..bio19 + gdd0/gdd5/gdd10
#
# 源路径（CHELSA 桶 os.unil.cloud.switch.ch/chelsa02，本地镜像 P("chelsa")）：
#   <chelsa>/bioclim/<var>/<speriod>/<GCM大写>/<ssp>/
#       CHELSA_<gcm小写>_<ssp>_<var>_<speriod>_V.2.1.tif
#
# 口径：
#   * 重采样 = config resampling.continuous = bilinear；投影前裁到 crop_lonlat 窗口
#   * terra 自动施加 CHELSA scale/offset → 物理单位（°C / mm / 度日）
#   * bio03 额外 ×bio03_scale(=100)：CHELSA 原生分数(0-1) → WorldClim 百分数
#   * ensmean = 5 个已交付 GCM 层的逐像元等权算术平均（后处理，非独立降尺度），
#     因此必须在 5 个 GCM 链全部产出后运行；保证 ensmean 与交付 GCM 层严格一致
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

bioclim_vars <- function() {
  clim <- CFG()$climate
  c(sprintf("bio%02d", 1:as.integer(clim$n_bio)),
    as.character(unlist(clim$extra_vars)))
}

gcm_chains <- function() {
  ch <- as.character(unlist(CFG()$climate$chains))
  ch[ch != "ensmean"]
}

chain_parts <- function(chain, cyear, ssp, v) {
  dsname <- paste0(CFG()$climate$source, "-", chain)
  c("reg", "bioclim", dsname, "scenario", cyear, ssp, v)
}

build_manifest <- function() {
  clim <- CFG()$climate
  chains <- as.character(unlist(clim$chains))
  ssps   <- as.character(unlist(clim$ssps))
  per    <- clim$periods
  cyears <- names(per)
  vars   <- bioclim_vars()
  cw     <- as.numeric(unlist(clim$crop_lonlat))
  crop   <- terra::ext(cw[1], cw[2], cw[3], cw[4])
  b03sc  <- as.numeric(clim$bio03_scale)
  tasks <- list()
  for (chain in chains) {
    is_ens <- chain == "ensmean"
    for (cy in cyears) {
      speriod <- as.character(per[[cy]])
      for (ssp in ssps) for (v in vars) {
        parts <- chain_parts(chain, cy, ssp, v)
        if (is_ens) {
          tasks[[length(tasks) + 1L]] <- list(
            kind = "ensmean", parts = parts, chain = chain,
            cyear = cy, speriod = speriod, ssp = ssp, v = v)
        } else {
          gcm_folder <- toupper(chain)
          src <- file.path(P("chelsa"), "bioclim", v, speriod, gcm_folder, ssp,
                           sprintf("CHELSA_%s_%s_%s_%s_V.2.1.tif", chain, ssp, v, speriod))
          tasks[[length(tasks) + 1L]] <- list(
            kind = "gcm", parts = parts, src = src, chain = chain,
            cyear = cy, speriod = speriod, ssp = ssp, v = v,
            scale = if (v == "bio03") b03sc else NULL, crop_ext = crop)
        }
      }
    }
  }
  tasks
}

run_gcm <- function(t) {
  cfg <- CFG()
  dst <- layer_path(t$parts)
  force <- identical(Sys.getenv("CHECO_FORCE"), "1")
  if (file.exists(dst) && !force && check_alignment(dst))
    return(list(status = "skip", dst = dst))
  if (!file.exists(t$src)) return(list(status = "error", dst = dst, note = paste("missing", t$src)))
  warp_to_template(t$src, dst, method = cfg$resampling$continuous,
                   src_nodata = NULL, scale = t$scale, crop_ext = t$crop_ext)
  if (!check_alignment(dst)) return(list(status = "error", dst = dst, note = "alignment"))
  list(status = "ok", dst = dst)
}

run_ensmean <- function(t) {
  dst <- layer_path(t$parts)
  force <- identical(Sys.getenv("CHECO_FORCE"), "1")
  if (file.exists(dst) && !force && check_alignment(dst))
    return(list(status = "skip", dst = dst))
  srcs <- vapply(gcm_chains(), function(ch)
    layer_path(chain_parts(ch, t$cyear, t$ssp, t$v)), "")
  if (!all(file.exists(srcs)))
    return(list(status = "pending", dst = dst, note = "GCM layers not all ready"))
  stk <- terra::rast(srcs)
  m <- terra::mean(stk, na.rm = TRUE)        # 逐像元等权平均（5 模式）
  m <- apply_china_mask(m, NA)
  atomic_write_raster(dst, m, dtype = "float32")
  if (!check_alignment(dst)) return(list(status = "error", dst = dst, note = "alignment"))
  list(status = "ok", dst = dst)
}

run_task <- function(t) {
  if (t$kind == "ensmean") run_ensmean(t) else run_gcm(t)
}

main <- function(shard = 1L, nshard = 1L) {
  print_grid()
  tasks <- build_manifest()
  ngcm <- sum(vapply(tasks, function(t) t$kind == "gcm", TRUE))
  nens <- sum(vapply(tasks, function(t) t$kind == "ensmean", TRUE))
  cat(sprintf("总任务 %d（GCM %d + ensmean %d；应为 1188 = 990 + 198）\n",
              length(tasks), ngcm, nens))
  # 两轮：先全部 GCM，再 ensmean（ensmean 依赖 5 个 GCM 交付层）
  gcm_tasks <- Filter(function(t) t$kind == "gcm", tasks)
  ens_tasks <- Filter(function(t) t$kind == "ensmean", tasks)
  if (nshard > 1L) {
    gcm_tasks <- gcm_tasks[seq.int(shard, length(gcm_tasks), by = nshard)]
    ens_tasks <- ens_tasks[seq.int(shard, length(ens_tasks), by = nshard)]
  }
  t0 <- Sys.time(); nok <- 0L; nskip <- 0L; nerr <- 0L; npend <- 0L
  run_pass <- function(ts, label) {
    cat(sprintf("\n== %s：%d 任务 ==\n", label, length(ts)))
    for (i in seq_along(ts)) {
      r <- tryCatch(run_task(ts[[i]]),
                    error = function(e) list(status = "error", dst = layer_path(ts[[i]]$parts),
                                             note = conditionMessage(e)))
      if (identical(r$status, "ok")) nok <<- nok + 1L
      else if (identical(r$status, "skip")) nskip <<- nskip + 1L
      else if (identical(r$status, "pending")) npend <<- npend + 1L
      else { nerr <<- nerr + 1L; cat(sprintf("  ERR %s : %s\n", basename(r$dst), r$note)) }
      if (i %% 20 == 0 || i == length(ts))
        cat(sprintf("  %3d/%d ok=%d skip=%d pend=%d err=%d %.0f 秒\n",
                    i, length(ts), nok, nskip, npend, nerr,
                    as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    }
  }
  run_pass(gcm_tasks, "GCM 链")
  run_pass(ens_tasks, "ensmean")
  cat(sprintf("\n汇总 ok=%d skip=%d pending=%d err=%d\n", nok, nskip, npend, nerr))
  invisible(list(ok = nok, skip = nskip, pending = npend, err = nerr))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) as.integer(a[1]) else 1L,
       if (length(a) >= 2) as.integer(a[2]) else 1L)
}