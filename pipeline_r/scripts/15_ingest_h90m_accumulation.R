# R/15_ingest_h90m_accumulation.R
# 【结论：该方案已试并被否决，脚本保留作为证据】
#
# 2026-10-21 实施结果：生成了 5 层候选数据，质量检查 19/19 通过，
# 但装入交付树前发现两个致命问题，因此已全部回滚：
#
#   1) 该变量已于 2026-10-17 被本项目主动撤下（归档于
#      archive/withdrawn_source_defective/hydro/h90m/accumulation/），理由写在
#      USAGE_NOTES_AND_LIMITATIONS.md：“accumulation 源含负值
#      （最小 −244,806），汇流面积不可能为负”。
#      本脚本重建后同样发现负值（已置 NoData），但这不等于解决了问题。
#
#   2) 与归档的旧版逐格对比：中位数比值 1.0000、Spearman 0.9988（更多细节一致），
#      但河道峰值被系统性压低——例如 lon 131.6 / lat 47.7 附近，
#      原始 90 m 峰值 804,373 km2，旧版 1 km 得 536,753，本脚本得 85,984（低 6.2 倍）。
#      原因未查清，因此不能把它当作可交付层。
#
# 保留本脚本的用途：记录“为什么这条路走不通”，以及复现验证过程。
# 当前交付仍使用 HydroSHEDS 累积流（5 层，标为 RESTRICTED）。
#
# 以下为原始脚本。
#
# 用 Hydrography90m 的 90 m 流量累积替换受限的 HydroSHEDS 版本
#
# 背景（2026-10-21）：
#   交付树里的 5 个 `hydro/hydrosheds/accumulation` 图层来自 HydroSHEDS Core v1.1，
#   其许可含再分发限制，因此被标为 RESTRICTED，无法随 Zenodo 公开发布。
#   `hydro/h90m`（Hydrography90m，CC BY-NC 4.0）**本身提供 90 m 流量累积**，
#   与其余 39 个水文变量同源，可再分发。
#
# 变量含义的差异（必须记录）：
#   HydroSHEDS ACC = 上游 3 弧秒**格数**（计数）
#   Hydrography90m accumulation = 上游**汇水面积 km²**（物理量，与分辨率无关）
#   后者更有意义，但数值口径不同，不能与旧层直接混用。
#
# 处理链：
#   11 个 0.000833° 瓦片 → 逐瓦片裁到中国 bbox → project 到 1 km Albers（average）
#   → 合并 → 掩膜到国界 → 写基底 → 4 个焦点变体
#
# 用法：
#   Rscript R/15_ingest_h90m_accumulation.R check   # 只检查瓦片与覆盖，不生成
#   Rscript R/15_ingest_h90m_accumulation.R make    # 生成到 scratch（默认）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
suppressMessages(library(terra))

SRC   <- "E:/h90m/China_Hydrography90m/Raw"
OUT   <- file.path(PATH_SCRATCH(), "h90m_accum_candidate")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
TMP   <- file.path(OUT, "_tile_cache")
dir.create(TMP, showWarnings = FALSE, recursive = TRUE)

# 中国 bbox（略放宽，保证边缘不切）
CN_BBOX <- c(xmin = 73.0, xmax = 135.5, ymin = 17.5, ymax = 54.0)

tiles_needed <- function() {
  all <- list.dirs(SRC, recursive = FALSE, full.names = FALSE)
  keep <- character(0)
  for (t in all) {
    f <- file.path(SRC, t, "r.watershed/accumulation_tiles20d",
                   sprintf("accumulation_%s.tif", t))
    if (!file.exists(f)) next
    r <- rast(f); e <- as.vector(ext(r))
    if (e[2] <= CN_BBOX[1] || e[1] >= CN_BBOX[2]) next
    if (e[4] <= CN_BBOX[3] || e[3] >= CN_BBOX[4]) next
    keep <- c(keep, t)
  }
  keep
}

main <- function(mode = c("make", "check")) {
  mode <- match.arg(mode)
  tl <- tiles_needed()
  cat(sprintf("需要 %d 个瓦片: %s\n", length(tl), paste(tl, collapse = " ")))
  if (mode == "check") {
    for (t in tl) {
      f <- file.path(SRC, t, "r.watershed/accumulation_tiles20d",
                     sprintf("accumulation_%s.tif", t))
      cat(sprintf("  %-8s %6.1f MB\n", t, file.size(f) / 1024^2))
    }
    return(invisible(tl))
  }

  tpl <- rast(PATH_TEMPLATE())
  msk <- rast(PATH_MASK())
  cat(sprintf("模板: %d x %d ; %s\n", ncol(tpl), nrow(tpl),
              paste(round(as.vector(ext(tpl))), collapse = " ")))

  # ---- 逐瓦片投影到 1 km ----
  pieces <- character(0)
  for (t in tl) {
    dst <- file.path(TMP, sprintf("%s_1km.tif", t))
    if (file.exists(dst)) { pieces <- c(pieces, dst); cat(sprintf("  跳过（已缓存）%s\n", t)); next }
    f <- file.path(SRC, t, "r.watershed/accumulation_tiles20d",
                   sprintf("accumulation_%s.tif", t))
    t0 <- Sys.time()
    r <- rast(f)
    e <- as.vector(ext(r))
    # 该瓦片与中国 bbox 的交集
    ce <- ext(max(e[1], CN_BBOX[1]), min(e[2], CN_BBOX[2]),
              max(e[3], CN_BBOX[3]), min(e[4], CN_BBOX[4]))
    w <- crop(r, ce)
    # project 做 CRS 变换 + 面积加权平均；resample 不做变换，会全 NA
    p <- project(w, tpl, method = "average")
    writeRaster(p, dst, overwrite = TRUE, datatype = "FLT4S",
                gdal = c("COMPRESS=DEFLATE", "TILED=YES", "BIGTIFF=YES"))
    rm(r, w, p); gc(verbose = FALSE)
    cat(sprintf("  %-8s 裁 %dx%d -> 1km %dx%d  %.0f 秒\n", t,
                ncol(crop(rast(f), ce)), nrow(crop(rast(f), ce)),
                ncol(rast(dst)), nrow(rast(dst)),
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    pieces <- c(pieces, dst)
  }

  # ---- 合并瓦片 ----
  cat("合并", length(pieces), "个瓦片 ...\n")
  srcs <- sprc(lapply(pieces, rast))
  # terra 的 mosaic 默认 na.rm = TRUE；显式传 na.rm 会被透传到写入器报错
  merged <- mosaic(srcs, fun = "mean")

  # ---- 掩膜 ----
  base <- mask(merged, msk, maskvalues = c(0, NA), updatevalue = NA)

  # ---- 负值 -> NoData ----
  # 2026-10-21 实测结论（珠江口为例）：
  #   负值不是符号翻转。同一批格上 order-strahler 也是坏的
  #   —— 出现 Strahler 11 级（51 格，正值格中一例也无），
  #   且负值格上的 "Strahler 1 级" 对应 5,785 km2 上游面积，物理上不可能。
  #   说明这些格是 DEM 流向在潮汐平坦河口失效的位置，
  #   两个变量同时崩坏。必须置 NoData，不能 abs()。
  n_neg <- sum(values(base, mat = FALSE) < 0, na.rm = TRUE)
  if (n_neg > 0) {
    base <- ifel(base < 0, NA, base)
    cat(sprintf("  负值 %s 格已置 NoData
", format(n_neg, big.mark = ",")))
  }

  # ---- 写基底 ----
  stem <- file.path(OUT, "glo_hydro_h90m_accumulation")
  writeRaster(base, paste0(stem, ".tif"), overwrite = TRUE, datatype = "FLT4S",
              gdal = c("COMPRESS=DEFLATE", "TILED=YES", "PREDICTOR=3"))
  cat("  已写基底\n")

  # ---- 统计 ----
  v <- values(base, mat = FALSE); nv <- sum(!is.na(v))
  vm <- values(msk, mat = FALSE); n_mask <- sum(vm == 1, na.rm = TRUE)
  cat(sprintf("  基底: 有效 %s / 掩膜 %s = %.2f%%\n",
              format(nv, big.mark = ","), format(n_mask, big.mark = ","),
              100 * nv / n_mask))
  cat(sprintf("         min %.6g  median %.6g  max %.6g\n",
              min(v, na.rm = TRUE), median(v, na.rm = TRUE), max(v, na.rm = TRUE)))

  # ---- 焦点变体（与交付树同口径：等权均值，半径 1/5/10/20 km）----
  for (rad in c(1L, 5L, 10L, 20L)) {
    k <- 2L * rad + 1L
    # 2026-10-21 修：terra 的 na.policy="omit" 是“窗口内无 NA 才计算”，
    # 与交付树里另四个焦点族的口径相反。
    # 交付树的焦点会从邻格填补 NoData（f20000 比底多 12,659 格）。
    # 改用 "all" 填补后再重新掩膜，保证不超出国界。
    f <- focal(base, w = matrix(1, k, k), fun = "mean", na.rm = TRUE,
               na.policy = "all")
    f <- mask(f, msk, maskvalues = c(0, NA), updatevalue = NA)
    fo <- sprintf("%s_f%d", stem, rad * 1000L)
    writeRaster(f, paste0(fo, ".tif"), overwrite = TRUE, datatype = "FLT4S",
                gdal = c("COMPRESS=DEFLATE", "TILED=YES", "PREDICTOR=3"))
    vf <- values(f, mat = FALSE)
    cat(sprintf("  焦点 %2d km (%dx%d): max %.4g ; 有效 %s\n", rad, k, k,
                max(vf, na.rm = TRUE), format(sum(!is.na(vf)), big.mark = ",")))
    rm(f); gc(verbose = FALSE)
  }
  cat("完成。输出目录:", OUT, "\n")
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) a[1] else "make")
}
