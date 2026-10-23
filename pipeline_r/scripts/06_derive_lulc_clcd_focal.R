# =============================================================================
# R/06_derive_lulc_clcd.R  --  CLCD 年度土地覆盖 -> 1km 九类比例
#
# 数据：archive/clcd-albert/CLCD_v01_YYYY_albert.tif
#       161,378 x 135,079 @ 30 m, uint8, nodata=0, 与模板同 CRS（Albers），但 xmin 差 18,375 m
# 产出：lulc/clcd/<year>/<class>/glo_lulc_clcd_<year>_<class>_prop[_f<米>].tif
#       26 年 (2000-2025) x 9 类 x (1 + 4 focal) = 1,170 层
#
# 关键设计（按行带流式，避免物化 21.8 G 像元）：
#   1) 每个输出行带（默认 25 行）读取对应的 30 m 窗口（+1 个输出像元余量）
#   2) 在窗口内构造 9 层 one-hot（uint8），一次 project(average) 得到 9 个比例
#   3) GDAL 的 average 是**面积加权**的（2026-10-19 实测与 exactextractr 差 6e-08），
#      故 30m->1km 的错位半像元被正确处理
#
# 分两个阶段：
#   phase "base"  产出 9 个基底比例层
#   phase "focal" 由基底层派生 4 个焦点层（可并行）
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

CLCD_DIR <- function() file.path(PATH_ARCHIVE(), "clcd-albert")
CLCD_YEARS <- 2000:2025

# CLCD 原生 9 类（官方图例，与 README 一致）
CLCD_LEGEND <- c(
  "1" = "cropland", "2" = "forest",   "3" = "shrub",
  "4" = "grassland","5" = "water",    "6" = "snowice",
  "7" = "barren",   "8" = "impervious","9" = "wetland"
)

clcd_src <- function(year) file.path(CLCD_DIR(), sprintf("CLCD_v01_%d_albert.tif", year))

clcd_parts <- function(year, cls) c("glo", "lulc", "clcd", as.character(year), cls)

# ---- 行带窗口 --------------------------------------------------------------
#' 取模板的第 r0..r0+nr-1 行、全宽的子几何（返回 SpatRaster）
band_template <- function(r0, nr) {
  g <- GRID()
  x0 <- g$xmin
  x1 <- g$xmax
  y1 <- g$ymax - (r0 - 1) * g$res
  y0 <- y1 - nr * g$res
  terra::rast(xmin = x0, xmax = x1, ymin = y0, ymax = y1,
              resolution = g$res, crs = g$crs)
}

# ---- 单行带：算 9 类比例 ---------------------------------------------------
#' @param tag 临时文件标识（通常传年份），避免并发时互相覆盖
band_props <- function(r, r0, nr, codes, margin_cells = 2L, tag = "x") {
  g <- GRID()
  sub <- band_template(r0, nr)
  # 源窗口：子模板外扩 margin 个输出像元，保证边缘完整覆盖
  win <- terra::ext(sub) + margin_cells * g$res
  src <- terra::crop(r, win, snap = "out")

  # nodata(0) 与超范围值置 NA —— 关键：
  #   若置 0 而非 NA，average 的分母会包含这些像元，使九类比例之和 < 1。
  #   置 NA 后 average 只除以有效像元数，和的恒等式成立。
  v <- terra::values(src, mat = FALSE)
  v[is.na(v) | !(v %in% codes)] <- NA
  terra::values(src) <- v

  # 用 segregate 一次生成 9 层 one-hot：
  #   实测比 9 次 ifel + rast(list) 快 3.6 倍（10.4 s vs 36.1 s），结果逐像元相同，
  #   且正确传播 NA（NA 数与源一致）。
  onehot <- terra::segregate(src, classes = codes, keep = FALSE, other = 0)

  # 2026-10-20 提速（实测 1.39×）：**优先在内存里直接 project，失败才落盘**。
  #
  # 历史：原实现一律落盘为 INT1U 再 project。原因是 segregate 返回 float64
  # （9 层 × 135 M px × 8 B = 9.7 GB），当时 10 个 hlu1km 焦点分片与 4 个 clcd
  # 分片并行、内存压到 16 GB，project 一次性分配内存数据集时报
  # "cannot allocate 1x8621458272 bytes"。
  #
  # 但那条落盘路径本身很贵：把 9.7 GB float64 逐值转成 INT1U 要 40.9 s，
  # 占单带 102.6 s 的 40%。实测（R/tests/test_68_clcd_speedup.R）：
  #   落盘   band=25 : 95.8 s/带  → 4.73 h/年/分片
  #   内存   band=25 : 75.0 s/带  → 3.39 h/年/分片   (1.39×)
  # 且两种实现逐像元相同（NA 结构一致，max|d| = 0.000e+00）。
  #
  # 所以改为：先试内存；若因内存压力失败，再退回落盘。这样既拿到提速，
  # 又保留在低内存环境下仍能跑完的鲁棒性。
  out <- tryCatch(
    terra::project(onehot, sub, method = terra_method("average"), align = FALSE),
    error = function(e) NULL)

  if (is.null(out)) {
    # 回退路径：落盘为 INT1U，让 GDAL 流式读取（原行为）
    tmp <- file.path(PATH_SCRATCH(), "clcd_onehot",
                     sprintf("oh_%s_%d_%d.tif", tag, r0, Sys.getpid()))
    ensure_dir(dirname(tmp))
    terra::writeRaster(onehot, tmp, overwrite = TRUE, datatype = "INT1U",
                       gdal = c("COMPRESS=DEFLATE", "TILED=YES", "BIGTIFF=IF_SAFER"))
    rm(onehot); gc(verbose = FALSE)

    oh <- terra::rast(tmp)
    out <- terra::project(oh, sub, method = terra_method("average"), align = FALSE)
    rm(oh); gc(verbose = FALSE)
    unlink(tmp)
  } else {
    rm(onehot); gc(verbose = FALSE)
  }
  # 行带不能套全图掩膜（extent 不匹配）；掩膜在写全图层时统一做
  out
}

# ---- 单年：产 9 个基底比例层 ----------------------------------------------
#' @param max_rows 仅处理前若干行（冒烟测试用；NULL = 全图 4,062 行）
clcd_year_base <- function(year, band_rows = 25L, overwrite = FALSE, max_rows = NULL) {
  g <- GRID()
  codes  <- as.integer(names(CLCD_LEGEND))
  cnames <- unname(CLCD_LEGEND)
  src <- clcd_src(year)
  if (!file.exists(src)) return(list(status = "error", note = paste("missing", src)))

  nrow_use <- if (is.null(max_rows)) g$height else min(as.integer(max_rows), g$height)

  dst_files <- vapply(cnames, function(cn) layer_path(clcd_parts(year, cn), "_prop"), "")
  if (!overwrite && is.null(max_rows) && all(file.exists(dst_files)) &&
      all(vapply(dst_files, check_alignment, TRUE)))
    return(list(status = "skip", n = length(dst_files)))

  r <- terra::rast(src)
  if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0

  # 9 个全图累加矩阵（double, 各 158 MB，合计约 1.4 GB）
  acc <- lapply(seq_along(codes), function(i) matrix(NA_real_, nrow_use, g$width))

  r0 <- 1L
  while (r0 <= nrow_use) {
    nr <- min(band_rows, nrow_use - r0 + 1L)
    p <- band_props(r, r0, nr, codes, tag = as.character(year))
    stopifnot(nrow(p) * ncol(p) == nr * g$width)
    for (i in seq_along(codes)) {
      v <- terra::values(p[[i]], mat = FALSE)
      acc[[i]][r0:(r0 + nr - 1L), ] <- matrix(v, nrow = nr, ncol = g$width, byrow = TRUE)
    }
    r0 <- r0 + nr
  }

  written <- character()
  for (i in seq_along(codes)) {
    if (is.null(max_rows)) {
      dst <- layer_path(clcd_parts(year, cnames[i]), "_prop")
      rr <- terra::rast(acc[[i]], extent = terra::ext(g$rast), crs = g$crs)
      atomic_write_raster(dst, apply_china_mask(rr, NA), dtype = "float32")
    } else {
      # 冒烟：只保留前 nrow_use 行，不套全图掩膜（extent 与全图掩膜不符）
      dst <- file.path(PATH_SCRATCH(), "clcd_smoke",
                       sprintf("smoke_%d_%s_prop.tif", year, cnames[i]))
      rr <- terra::rast(acc[[i]], extent = terra::ext(band_template(1L, nrow_use)), crs = g$crs)
      atomic_write_raster(dst, rr, dtype = "float32")
    }
    written <- c(written, dst)
  }
  rm(acc); gc(verbose = FALSE)
  list(status = "ok", n = length(written), files = written)
}

# ---- 单层焦点 --------------------------------------------------------------
clcd_focal_one <- function(year, cls) {
  fs <- FOCAL_SPEC()
  parts <- clcd_parts(year, cls)
  base <- layer_path(parts, "_prop")
  if (!file.exists(base)) return(list(status = "pending"))

  # 2026-10-20 修（缺陷 44）：4 个目标全部存在则直接跳过，连基底都不读。
  # 与缺陷 42（hlu_focal_one）同类，是同一段模式复制到本脚本时一并带来的。
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
    out <- apply_china_mask(focal_mean(b, fs$radius_cells[k], count = cnt[[k]]), NA)
    atomic_write_raster(dsts[k], out, dtype = "float32")
    n <- n + 1L
  }
  list(status = "ok", n = n)
}

# ---- 主流程 ----------------------------------------------------------------
#' 并行策略：**分片多进程**，不用 future。
#'   原因：future::multisession 的工作进程里跑 project() 会 std::bad_alloc；
#'   且多进程并发时 terra 默认按 60% 物理内存规划会超额承诺。
#'   改为每片一个独立 Rscript，进程内顺序执行；terra memfrac 由 config 压低。
main <- function(phase = c("base", "focal"), shard = 1L, nshard = 1L, years = CLCD_YEARS) {
  phase <- match.arg(phase)
  print_grid()
  if (nshard > 1L) years <- years[seq.int(shard, length(years), by = nshard)]
  cat(sprintf("phase=%s shard=%d/%d 本片年份 %d: %s\n", phase, shard, nshard,
              length(years), paste(years, collapse = ",")))

  if (phase == "base") {
    for (y in years) {
      t0 <- Sys.time()
      # 重试 2 次：并发下偶发 std::bad_alloc / writeRaster 失败，重试通常可过
      r <- NULL
      for (attempt in 1:2) {
        r <- tryCatch(clcd_year_base(y, overwrite = identical(Sys.getenv("CHECO_FORCE"), "1")),
                      error = function(e) list(status = "error", note = conditionMessage(e)))
        if (!identical(r$status, "error")) break
        cat(sprintf("  %d 第 %d 次失败: %s；3 秒后重试\n", y, attempt, r$note))
        Sys.sleep(3); gc(verbose = FALSE)
      }
      cat(sprintf("  %d: %s (%s 层) %.0f 秒 %s\n", y, r$status, r$n %||% 0L,
                  as.numeric(difftime(Sys.time(), t0, units = "secs")),
                  if (identical(r$status, "error")) paste0("[", r$note, "]") else ""))
    }
  } else {
    cnames <- as.character(CLCD_LEGEND)
    for (y in years) for (cn in cnames) {
      r <- tryCatch(clcd_focal_one(y, cn),
                    error = function(e) list(status = "error", note = conditionMessage(e)))
      if (identical(r$status, "error")) cat(sprintf("  ERR %d %s : %s\n", y, cn, r$note))
    }
    cat("  焦点完成\n")
  }
  invisible(NULL)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  ph <- if (length(a) >= 1) a[1] else "base"
  sh <- if (length(a) >= 2) as.integer(a[2]) else 1L
  ns <- if (length(a) >= 3) as.integer(a[3]) else 1L
  main(ph, sh, ns)
}
