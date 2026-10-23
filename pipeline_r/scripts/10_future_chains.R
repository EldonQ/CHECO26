# =============================================================================
# R/10_future_chains.R  --  bioclim 未来情景链（504 层）
#
# 对应 Python: scripts/07_future_chains.py
#
# 目录口径（N-SDM 2.0.1 要求）：
#   glo/bioclim/cnclim1km-<chain>/scenario/<cyear>/<ssp>/<var>/
#   即 scenario=倒数第 2 级、year=倒数第 3 级
#
# 组合：2 链 × 3 时段 × 3 SSP × 28 变量 = 504
#   链   : ensmean, bcc_csm2_mr
#   时段 : 2030 -> 2021_2040 ; 2055 -> 2041_2070 ; 2085 -> 2071_2100
#   SSP  : ssp126 / ssp245 / ssp585
#
# 源路径：
#   <bioclim>/cnclim1km_<chain>/future/<speriod>/<ssp>/<var>/
#       bioclim_cnclim1km_<chain>_future_<speriod>_<ssp>_<var>.tif
# 重采样：config resampling.continuous = bilinear，src_nodata 用源自带，无缩放
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

BIOCLIM_VARS <- c(sprintf("bio%02d", 1:23), "prec", "sunp", "tave", "tmax", "tmin")

build_manifest <- function() {
  clim <- CFG()$climate
  chains <- as.character(unlist(clim$chains))
  ssps   <- as.character(unlist(clim$ssps))
  per    <- clim$periods
  cyears <- names(per)
  tasks <- list()
  for (chain in chains) {
    dsname <- paste0("cnclim1km-", gsub("_", "-", chain))
    for (cy in cyears) {
      speriod <- as.character(per[[cy]])
      for (ssp in ssps) for (v in BIOCLIM_VARS) {
        src <- file.path(P("bioclim"), paste0("cnclim1km_", chain), "future", speriod, ssp, v,
                         sprintf("bioclim_cnclim1km_%s_future_%s_%s_%s.tif", chain, speriod, ssp, v))
        tasks[[length(tasks) + 1L]] <- list(
          parts = c("glo", "bioclim", dsname, "scenario", cy, ssp, v),
          src = src, chain = chain, cyear = cy, speriod = speriod, ssp = ssp, v = v)
      }
    }
  }
  tasks
}

run_task <- function(t) {
  cfg <- CFG()
  dst <- layer_path(t$parts)
  if (file.exists(dst) && !identical(Sys.getenv("CHECO_FORCE"), "1") && check_alignment(dst))
    return(list(status = "skip", dst = dst))
  if (!file.exists(t$src)) return(list(status = "error", dst = dst, note = paste("missing", t$src)))
  warp_to_template(t$src, dst, method = cfg$resampling$continuous,
                   src_nodata = NULL, scale = NULL)
  if (!check_alignment(dst)) return(list(status = "error", dst = dst, note = "alignment"))
  list(status = "ok", dst = dst)
}

main <- function(shard = 1L, nshard = 1L) {
  print_grid()
  tasks <- build_manifest()
  if (nshard > 1L) tasks <- tasks[seq.int(shard, length(tasks), by = nshard)]
  cat(sprintf("shard=%d/%d 本片任务 %d（总 %d 应为 504）\n",
              shard, nshard, length(tasks), length(build_manifest())))
  t0 <- Sys.time(); nok <- 0L; nskip <- 0L; nerr <- 0L
  for (i in seq_along(tasks)) {
    r <- tryCatch(run_task(tasks[[i]]), error = function(e) list(status = "error", note = conditionMessage(e)))
    if (identical(r$status, "ok")) nok <- nok + 1L
    else if (identical(r$status, "skip")) nskip <- nskip + 1L
    else { nerr <- nerr + 1L; cat(sprintf("  ERR %s : %s\n", basename(r$dst), r$note)) }
    if (i %% 20 == 0 || i == length(tasks))
      cat(sprintf("  %3d/%d ok=%d skip=%d err=%d %.0f 秒\n", i, length(tasks), nok, nskip, nerr,
                  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
  invisible(list(ok = nok, skip = nskip, err = nerr))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) as.integer(a[1]) else 1L,
       if (length(a) >= 2) as.integer(a[2]) else 1L)
}
