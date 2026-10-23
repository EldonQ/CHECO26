# =============================================================================
# R/07_derive_lulc_hlu1km.R  --  Harmonised land use 1960-2100 逐年八类比例
#
# 源：archive/harmonised/Harmonised-1960-2100/
#     SSP{1..5}_RCP{26,45,70,60,85}_country-f.tif
#     36,000 x 18,000, 141 波段 (1960-2100), float32, EPSG:4326, 0.01°
#     同名的 *_global-f.tif 是"全球统一参数"版本，**不使用**（已定：只用 country-f）
#
# 产出：
#   历史  lulc/hlu1km/<year>/<class>/glo_lulc_hlu1km_<year>_<class>_prop[_f<米>].tif
#   未来  lulc/hlu1km/scenario/<year>/<ssp>/<class>/glo_lulc_hlu1km_scenario_<year>_<ssp>_<class>_prop[_f<米>].tif
#   组合 = 历史 61 年 + 未来 80 年 x 5 情景 = 461
#   层数 = 461 x 8 类 x (1 + 4 focal) = 18,440
#
# 关键约定：
#   * 波段号 = year - 1959（band 1 = 1960, band 141 = 2100）
#   * 历史段五个文件逐像元相同（2020 年已实测 0 差异），固定从 SSP1_RCP26 读取
#   * 源码 0（海洋）-> NA；八类 = 11,22,33,55,66,77,441,442
#   * 比例用 one-hot 的 average 聚合（与 CLCD / GLULC 同口径）
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", Sys.getenv("CHECO_ROOT", getwd())), "R/_bootstrap.R"),
       encoding = "UTF-8")

HLU_DIR <- function() file.path(PATH_ARCHIVE(), "harmonised", "Harmonised-1960-2100")

# 情景映射：源文件前缀 -> 输出目录名
HLU_SCEN <- c(SSP1_RCP26 = "ssp126", SSP2_RCP45 = "ssp245", SSP3_RCP70 = "ssp370",
              SSP4_RCP60 = "ssp460", SSP5_RCP85 = "ssp585")

# 八类（源码 -> 变量名）
HLU_LEGEND <- c("11" = "urban",     "22" = "cropland", "33" = "pasture",
                "441" = "mngforest", "442" = "forest",  "55" = "grassshrub",
                "66" = "sparse",     "77" = "water")

HLU_HIST_YEARS <- 1960:2020
HLU_FUT_YEARS  <- 2021:2100
HLU_HIST_FILE  <- "SSP1_RCP26_country-f.tif"   # 历史段任取一个（五文件相同）

hlu_file <- function(scen_key) file.path(HLU_DIR(), sprintf("%s_country-f.tif", scen_key))

hlu_band <- function(year) as.integer(year) - 1959L

hlu_codes <- function() as.integer(names(HLU_LEGEND))

#' 类别名，**按码升序**排列
#'
#' 2026-10-19 修：`terra::segregate(classes = ...)` 输出的波段**按类别码升序**，
#' 与传入的 classes 向量顺序无关。原先用 `unname(HLU_LEGEND)`（未排序）配对波段，
#' 导致码 55/66/77/441/442 五个类的图层名错位：
#'   band4 实为 55 grassshrub，却被命名为 mngforest
#'   band5 实为 66 sparse，    却被命名为 forest
#'   band6 实为 77 water，     却被命名为 grassshrub
#'   band7 实为 441 mngforest，却被命名为 sparse
#'   band8 实为 442 forest，   却被命名为 water
#' （11/22/33 本就升序，故未受影响。最小复现见 R/tests/test_62_segregate_order.R。）
hlu_cnames <- function() {
  lg <- HLU_LEGEND[order(as.integer(names(HLU_LEGEND)))]
  unname(lg)
}
#' 与 hlu_cnames() 对应、已升序的类别码
hlu_codes_sorted <- function() sort(hlu_codes())

#' 目标目录层级
hlu_parts <- function(year, ssp, cls) {
  if (is.na(ssp)) c("glo", "lulc", "hlu1km", as.character(year), cls)
  else c("glo", "lulc", "hlu1km", "scenario", as.character(year), ssp, cls)
}

# China 窗口（经纬度，足够覆盖模板，留余量）
HLU_WIN <- c(70, 140, 12, 58)   # lon_min, lon_max, lat_min, lat_max

# ---- 读单波段（裁到 China 窗口）--------------------------------------------
read_band <- function(src, k, win = HLU_WIN) {
  r <- terra::rast(src)[[k]]
  terra::crop(r, terra::ext(win[1], win[2], win[3], win[4]), snap = "out")
}

# ---- 单组合：产 8 个基底比例层 --------------------------------------------
hlu_combo <- function(year, ssp = NA_character_, overwrite = FALSE) {
  cfg <- CFG(); g <- GRID()
  codes <- hlu_codes_sorted(); cnames <- hlu_cnames()   # 两者均按码升序，与 segregate 输出对齐

  src <- if (is.na(ssp)) file.path(HLU_DIR(), HLU_HIST_FILE) else {
    key <- names(HLU_SCEN)[HLU_SCEN == ssp]
    if (!length(key)) return(list(status = "error", note = paste("unknown ssp", ssp)))
    hlu_file(key)
  }
  if (!file.exists(src)) return(list(status = "error", note = paste("missing", src)))

  dst_files <- vapply(cnames, function(cn) layer_path(hlu_parts(year, ssp, cn), "_prop"), "")
  if (!overwrite && all(file.exists(dst_files)) &&
      all(vapply(dst_files, check_alignment, TRUE)))
    return(list(status = "skip", n = length(dst_files)))

  k <- hlu_band(year)
  cs <- read_band(src, k)
  if (terra::nlyr(cs) > 1) cs <- cs[[1]]

  # 0（海洋）与超范围 -> NA；NA 使 average 只除以有效像元，比例之和 = 1
  v <- terra::values(cs, mat = FALSE)
  v[is.na(v) | !(v %in% codes)] <- NA
  terra::values(cs) <- v

  onehot <- terra::segregate(cs, classes = codes, keep = FALSE, other = 0)

  # **必须落盘为 INT1U 再 project**（与 CLCD 同一处理）：
  #   segregate 未声明数据类型时按 float64 组织（8 层 x 24.6 M px x 8 B = 1.6 GB），
  #   多进程并行时 project 需一次性分配内存数据集，实测触发 std::bad_alloc 全线中止。
  tmp <- file.path(PATH_SCRATCH(), "hlu_onehot",
                   sprintf("oh_%d_%s_%d.tif", year, ifelse(is.na(ssp), "hist", ssp), Sys.getpid()))
  ensure_dir(dirname(tmp))
  terra::writeRaster(onehot, tmp, overwrite = TRUE, datatype = "INT1U",
                     gdal = c("COMPRESS=DEFLATE", "TILED=YES", "BIGTIFF=IF_SAFER"))
  rm(onehot); gc(verbose = FALSE)

  oh <- terra::rast(tmp)
  out <- terra::project(oh, g$rast, method = terra_method("average"), align = FALSE)
  rm(oh); gc(verbose = FALSE)
  unlink(tmp)
  out <- apply_china_mask(out, NA)

  written <- character()
  for (i in seq_along(codes)) {
    dst <- layer_path(hlu_parts(year, ssp, cnames[i]), "_prop")
    atomic_write_raster(dst, out[[i]], dtype = "float32")
    written <- c(written, dst)
  }
  list(status = "ok", n = length(written), files = written)
}

# ---- 单层焦点 --------------------------------------------------------------
#' 计算某组合某类别的 4 个焦点层
#'
#' 2026-10-20 修（关键性能缺陷）：原实现**不做已存在检查**，无条件读基底
#' （19.7M 像元）+ 算 4 个 count 层（每个都是 19.7M 像元的 focal）+ 覆写 4 层。
#' 后果：组合里 8 个类哪怕只缺 1 层，8 次调用都各自全量重算；已完成的层被反复重写。
#' 这是焦点阶段速率从 35 层/分钟衰减到 4.5 的直接原因，也让整个阶段多花数小时。
#' 现在：先查 4 个目标是否已存在，全部存在直接返回 skip（连基底都不读）；
#' 只对缺失的尺度计算，count 层也只对需要的尺度准备。
hlu_focal_one <- function(year, ssp, cls) {
  fs <- FOCAL_SPEC()
  parts <- hlu_parts(year, ssp, cls)
  base <- layer_path(parts, "_prop")
  if (!file.exists(base)) return(list(status = "pending"))

  dsts <- layer_path(parts, paste0("_prop", fs$suffix))
  need <- !file.exists(dsts)
  if (!any(need)) return(list(status = "skip", n = 0L))

  b <- terra::rast(base)
  nd <- terra::NAflag(b); v <- terra::values(b, mat = FALSE)
  if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
  v[is.nan(v)] <- NA
  terra::values(b) <- v

  cnt <- lapply(seq_len(nrow(fs)), function(k) {
    if (!need[k]) return(NULL)
    rc <- fs$radius_cells[k]
    if (2L * rc + 1L >= 21L) focal_count_sep(terra::ifel(is.na(b), NA, 1), rc) else NULL
  })

  n <- 0L
  for (k in which(need)) {
    atomic_write_raster(dsts[k],
                        apply_china_mask(focal_mean(b, fs$radius_cells[k],
                                                    count = cnt[[k]]), NA),
                        dtype = "float32")
    n <- n + 1L
  }
  list(status = "ok", n = n)
}

# ---- 清单 ----------------------------------------------------------------
hlu_manifest <- function() {
  combos <- list()
  for (y in HLU_HIST_YEARS) combos[[length(combos) + 1L]] <- list(y = y, ssp = NA_character_)
  for (sk in names(HLU_SCEN))
    for (y in HLU_FUT_YEARS) combos[[length(combos) + 1L]] <- list(y = y, ssp = HLU_SCEN[[sk]])
  combos
}

# ---- 主流程 --------------------------------------------------------------
#' 并行策略：**分片多进程**，不用 future。
#'   原因：future::multisession 的工作进程里跑 project() 会触发 std::bad_alloc
#'   （同一组合在主进程单独跑 130 秒正常完成）。改为每片一个独立 Rscript 进程，
#'   由外部启动器并发，进程内顺序执行，内存行为与单跑一致。
main <- function(phase = c("base", "focal"), shard = 1L, nshard = 1L, limit = NULL) {
  phase <- match.arg(phase)
  print_grid()
  combos <- hlu_manifest()
  if (!is.null(limit)) combos <- combos[seq_len(min(limit, length(combos)))]
  if (nshard > 1L) combos <- combos[seq.int(shard, length(combos), by = nshard)]

  cat(sprintf("phase=%s shard=%d/%d 本片组合 %d -> 基底 %d 层, 焦点 %d 层\n",
              phase, shard, nshard, length(combos),
              length(combos) * 8, length(combos) * 8 * 4))

  t0 <- Sys.time(); nok <- 0L; nskip <- 0L; nerr <- 0L
  if (phase == "base") {
    for (i in seq_along(combos)) {
      c_ <- combos[[i]]
      r <- tryCatch(hlu_combo(c_$y, c_$ssp, overwrite = identical(Sys.getenv("CHECO_FORCE"), "1")),
                    error = function(e) list(status = "error", note = conditionMessage(e)))
      if (identical(r$status, "ok")) nok <- nok + 1L
      else if (identical(r$status, "skip")) nskip <- nskip + 1L
      else { nerr <- nerr + 1L; cat(sprintf("  ERR y=%d ssp=%s : %s\n", c_$y, c_$ssp, r$note)) }
      if (i %% 5 == 0 || i == length(combos))
        cat(sprintf("  %3d/%d  ok=%d skip=%d err=%d  %.0f 秒\n", i, length(combos),
                    nok, nskip, nerr, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    }
  } else {
    cnames <- hlu_cnames()
    for (c_ in combos) for (cn in cnames) {
      r <- tryCatch(hlu_focal_one(c_$y, c_$ssp, cn),
                    error = function(e) list(status = "error", note = conditionMessage(e)))
      # 2026-10-20：必须同时认 "skip"（4 个焦点层都已存在）。
      # 原先只有 ok / pending 两个分支，新增的 skip 会落进 else 被当成错误——
      # 实测导致 367 个 skip 被报成 err（且 r$note 为 NULL 时 cat 不打印，故只有 1 条真 ERR）。
      if (identical(r$status, "ok")) nok <- nok + 1L
      else if (identical(r$status, "skip")) nskip <- nskip + 1L
      else if (identical(r$status, "pending")) nskip <- nskip + 1L
      else { nerr <- nerr + 1L
             cat(sprintf("  ERR y=%d ssp=%s %s : %s\n", c_$y, c_$ssp, cn,
                         if (is.null(r$note)) "(no message)" else r$note)) }
    }
    cat(sprintf("  焦点完成 ok=%d skip/pending=%d err=%d  %.0f 秒\n", nok, nskip, nerr,
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
  invisible(list(ok = nok, skip = nskip, err = nerr))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  ph <- if (length(a) >= 1) a[1] else "base"
  sh <- if (length(a) >= 2) as.integer(a[2]) else 1L
  ns <- if (length(a) >= 3) as.integer(a[3]) else 1L
  lim <- if (length(a) >= 4) as.integer(a[4]) else NULL
  main(ph, sh, ns, lim)
}
