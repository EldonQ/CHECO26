# =============================================================================
# R/05_derive_lulc.R  --  LULC 派生（第一阶段：GLULC / glu1km 540 层）
#
# 对应 Python: scripts/04_derive_lulc.py
#
# 每个快照 54 层：
#   6 类比例  x (1 + 4 focal)            = 30
#   Shannon   x 4 focal                  =  4   （无基底：由 6 个焦点比例算出）
#   边缘密度  x (1 + 4 focal)            =  5
#   斑块密度/平均斑块大小 x 2 口径 x 4 半径 = 15
#     （exception: patchdensity-all_f1000 为常量层，不产出 -> 实际 47 焦点 + 7 基底）
#   快照 = history_2020 + ssp126/245/585 x 2030/2050/2100 = 10 个
#
# 与 Python 逐项对齐的关键点：
#   * 分类层 warp 用 resampling.categorical = nearest，src_nodata=0，dtype uint8
#   * 掩膜后 valid = (1..6)；境外与非 1..6 一律置 255
#   * 比例 = one-hot 的焦点均值（方形窗，分母为窗口内有效像元）
#   * Shannon = -sum(p*ln p) 由 6 个焦点比例算出（自然对数）
#   * 边缘 = 与 4 邻域任一有效像元类别不同
#   * 斑块指标 = 4 邻域连通、锚点=扫描序首像元、圆盘窗、面积 πr²、自属补丁补计
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", Sys.getenv("CHECO_ROOT", getwd())), "R/_bootstrap.R"),
       encoding = "UTF-8")

SNAPSHOTS <- local({
  # (year_dir, ssp_dir, src_file)
  s <- list(list(y = "2020", ssp = NA_character_, f = "history_2020.tif"))
  for (p in list(c("ssp126", "ssp1_26"), c("ssp245", "ssp2_45"), c("ssp585", "ssp5_85"))) {
    for (yy in c(2030, 2050, 2100))
      s[[length(s) + 1L]] <- list(y = as.character(yy), ssp = p[1],
                                  f = sprintf("%s_%d.tif", p[2], yy))
  }
  s
})

snapshot_parts <- function(snap, extra = character()) {
  if (is.na(snap$ssp)) c("glo", "lulc", "glu1km", snap$y, extra)
  else c("glo", "lulc", "glu1km", "scenario", snap$y, snap$ssp, extra)
}

# ---- 4 邻域边缘指示 --------------------------------------------------------
#' 与任一 4 邻域有效像元类别不同即为边缘；仅对有效像元定义
edge_indicator <- function(cls, valid) {
  # cls/valid: SpatRaster（valid 为 0/1）
  e <- terra::rast(cls); terra::values(e) <- 0
  shift <- list(c(-1, 0), c(1, 0), c(0, -1), c(0, 1))
  cls_m <- terra::as.matrix(cls, wide = TRUE)
  val_m <- terra::as.matrix(valid, wide = TRUE)
  nr <- nrow(cls_m); nc <- ncol(cls_m)
  em <- matrix(FALSE, nr, nc)
  for (s in shift) {
    dy <- s[1]; dx <- s[2]
    r0 <- max(1, 1 + dy):min(nr, nr + dy)
    c0 <- max(1, 1 + dx):min(nc, nc + dx)
    r1 <- max(1, 1 - dy):min(nr, nr - dy)
    c1 <- max(1, 1 - dx):min(nc, nc - dx)
    nb  <- cls_m[r0, c0, drop = FALSE]
    nbv <- val_m[r0, c0, drop = FALSE]
    em[r1, c1] <- em[r1, c1] | (nbv == 1 & nb != cls_m[r1, c1])
  }
  em <- em & (val_m == 1)
  terra::values(e) <- as.vector(t(em))
  e
}

# ---- 斑块密度 / 平均斑块大小（圆盘窗，锚点近似 + 自属补丁补计）--------------
#' 与 Python 04_derive_lulc.patch_metric 逐项对齐：
#'   1) 4 邻域连通标记 —— 用自实现 ccl4，**不用 terra::patches**
#'      （后者在本库规模触发栈溢出 0xC00000FD；实测 600x600 即崩溃）
#'   2) 每斑块锚点 = 扫描序（行主序）首像元
#'   3) 窗口 = 圆盘 (dx^2+dy^2 <= r^2)，面积 pi*r^2
#'   4) 像元在本斑块内但自属锚点在窗外 -> 补计 1 个斑块与其面积
#'   5) density = cnt/(pi r^2)*100 个/100km2 ; msize = asum/cnt km2
patch_metric <- function(binary, radius_cells) {
  nr <- nrow(binary); nc <- ncol(binary)
  bm <- terra::as.matrix(binary, wide = TRUE)
  bin <- !is.na(bm) & bm == 1

  mk_na <- function() { r <- terra::rast(binary); terra::values(r) <- NA_real_; r }
  if (!any(bin)) return(list(density = mk_na(), msize = mk_na()))

  cc <- ccl4(bin)
  if (cc$n == 0L) return(list(density = mk_na(), msize = mk_na()))
  labm <- cc$labels                       # 0 = 背景，1..n
  n_patch <- cc$n

  # 每斑块面积（像元数）
  areas <- tabulate(labm[labm > 0L], nbins = n_patch)

  # 锚点 = 行主序首个像元（ccl4 已按首次出现顺序编号，故 first 的顺序即 1..n）
  flat <- as.vector(t(labm))
  nz <- which(flat > 0L)
  lab_nz <- flat[nz]
  first <- !duplicated(lab_nz)
  anc_cell <- nz[first]
  anc_row  <- ((anc_cell - 1L) %/% nc) + 1L
  anc_col  <- ((anc_cell - 1L) %%  nc) + 1L

  # 锚点栅格 / 斑块面积栅格
  anchor <- integer(nr * nc); anchor[anc_cell] <- 1L
  parea  <- integer(nr * nc); parea[nz] <- areas[lab_nz]
  anchor_r <- terra::rast(binary); terra::values(anchor_r) <- as.numeric(anchor)
  parea_r  <- terra::rast(binary); terra::values(parea_r)  <- as.numeric(parea)

  # 圆盘核
  d <- 2L * radius_cells + 1L
  off <- -radius_cells:radius_cells
  yy <- matrix(rep(off, each = d), d, d)
  xx <- matrix(rep(off, times = d), d, d)
  kern <- ifelse((xx^2 + yy^2) <= radius_cells^2, 1, 0)

  cnt_r  <- terra::focal(anchor_r, w = kern, fun = "sum", na.policy = "all", na.rm = TRUE)
  asum_r <- terra::focal(anchor_r * parea_r, w = kern, fun = "sum", na.policy = "all", na.rm = TRUE)
  cnt_m  <- round(terra::as.matrix(cnt_r,  wide = TRUE))
  asum_m <- round(terra::as.matrix(asum_r, wide = TRUE))

  # 自属补丁：像元在斑块内但自属锚点在窗外 -> 补计 1 个斑块与其面积
  #
  # 关键实现细节（2026-10-19 踩过）：labm 含 0（背景），而 R 的 x[0] 返回**空向量**
  # 而非 NA，直接用 anc_row[labm] 会造成长度不匹配 + 循环补齐，把补计算错。
  # 故把标签整体右移一位并补一个 NA 占位。
  inside <- labm > 0L
  if (any(inside)) {
    idx_pad    <- labm + 1L
    anc_row_p  <- c(NA_integer_, anc_row)
    anc_col_p  <- c(NA_integer_, anc_col)
    areas_p    <- c(NA_integer_, as.integer(areas))
    dy <- row(labm) - anc_row_p[idx_pad]
    dx <- col(labm) - anc_col_p[idx_pad]
    own_out <- inside & !is.na(dy) & ((dy^2 + dx^2) > radius_cells^2)
    cnt_m[own_out]  <- cnt_m[own_out]  + 1
    asum_m[own_out] <- asum_m[own_out] + areas_p[idx_pad][own_out]
  }

  area_km2 <- pi * radius_cells^2
  ok <- !is.na(cnt_m) & cnt_m >= 1
  dens <- rep(NA_real_, nr * nc); msz <- rep(NA_real_, nr * nc)
  dens[ok] <- cnt_m[ok] / area_km2 * 100
  msz[ok]  <- asum_m[ok] / cnt_m[ok]

  # 必须从**数值矩阵**新建浮点栅格：
  # 若用 terra::rast(binary) 再赋值，会继承 binary 的整数类型（INT1U），
  # 浮点值被截断（1.2732 -> 1），msize 这类大值（达 941 万）直接溢出成 NA，
  # 并使后续掩膜/写盘的有效域错乱（2026-10-19 实测：9,490,149 -> 5,283,720）。
  ex <- terra::ext(binary); cr <- terra::crs(binary)
  dr <- terra::rast(matrix(dens, nr, nc), extent = ex, crs = cr)
  mr <- terra::rast(matrix(msz,  nr, nc), extent = ex, crs = cr)
  list(density = dr, msize = mr)
}

# ---- 单快照 ----------------------------------------------------------------
derive_snapshot <- function(snap, which_parts = c("prop", "shannon", "edge", "patch")) {
  cfg <- CFG()
  legend <- unlist(cfg$lulc_legend)          # names = 类别码, values = 名称
  legend <- legend[order(as.integer(names(legend)))]
  codes  <- as.integer(names(legend))
  cnames <- as.character(legend)
  fs <- FOCAL_SPEC()
  src <- file.path(P("lulc_raw"), snap$f)
  if (!file.exists(src)) return(list(status = "error", note = paste("missing src", src)))

  # 1) 分类层 warp（nearest, src_nodata=0, uint8）
  cls_tmp <- file.path(PATH_SCRATCH(), "glu1km_cls",
                       sprintf("cls_%s_%s.tif", ifelse(is.na(snap$ssp), "hist", snap$ssp), snap$y))
  ensure_dir(dirname(cls_tmp))
  r <- terra::rast(src)
  terra::NAflag(r) <- 0
  cls <- terra::project(r, GRID()$rast,
                        method = terra_method(cfg$resampling$categorical),
                        align = FALSE)
  # 国界掩膜 + 只保留 1..6
  m <- china_mask()
  v <- terra::values(cls, mat = FALSE)
  mm <- terra::values(m, mat = FALSE)
  v[is.na(mm) | mm != 1] <- 255
  v[!is.na(v) & !(v %in% codes)] <- 255
  terra::values(cls) <- v
  valid <- cls
  terra::values(valid) <- as.integer(!is.na(v) & v %in% codes)
  written <- character()

  wr <- function(extra, suffix, arr) {
    dst <- layer_path(snapshot_parts(snap, extra), suffix)
    out <- apply_china_mask(arr, NA)
    atomic_write_raster(dst, out, dtype = "float32")
    written <<- c(written, dst)
    dst
  }

  # 六类 one-hot 与边缘层共用同一个有效掩膜，故窗口分母只需按半径算一次
  # （可分离计数的开销约为一次 2D 卷积，省下 5 次重复计算）
  cnt <- vector("list", nrow(fs))
  for (k in seq_len(nrow(fs))) {
    if (2L * fs$radius_cells[k] + 1L >= 21L)
      cnt[[k]] <- focal_count_sep(valid, fs$radius_cells[k])
  }

  # 2) 六类比例 + 焦点
  #  one-hot 口径必须是 **1 / 0 / NA**（不是 1/NA）：
  #    1  = 属于该类
  #    0  = 有效但不属于该类     <- 关键：0 是合法比例，必须参与焦点归一
  #    NA = 无效（境外或非 1..6）
  #  若误写成 1/NA，焦点均值的分母只剩该类像元，比例恒为 1（2026-10-19 踩过，
  #  water_prop_f20000 偏差 +0.98、urban_prop 掩膜不一致 98.5%）。
  focal_props <- list()
  if ("prop" %in% which_parts) {
    for (i in seq_along(codes)) {
      onehot <- cls
      terra::values(onehot) <- ifelse(!is.na(v) & v %in% codes,
                                      as.integer(v == codes[i]), NA)
      wr(c(cnames[i]), "_prop", onehot)
      for (k in seq_len(nrow(fs))) {
        fp <- focal_mean(onehot, fs$radius_cells[k], count = cnt[[k]])
        wr(c(cnames[i]), paste0("_prop", fs$suffix[k]), fp)
        focal_props[[fs$suffix[k]]][[cnames[i]]] <- fp
      }
    }
  }

  # 3) Shannon（由焦点比例算出，无基底）
  if ("shannon" %in% which_parts) {
    for (k in seq_len(nrow(fs))) {
      sfx <- fs$suffix[k]
      ps <- focal_props[[sfx]]
      if (is.null(ps)) next
      acc <- terra::rast(cls); terra::values(acc) <- 0
      anyp <- terra::rast(cls); terra::values(anyp) <- 0
      for (nm in names(ps)) {
        p <- ps[[nm]]
        pm <- terra::as.matrix(p, wide = TRUE)
        acc  <- acc + terra::ifel(is.na(p), 0, terra::ifel(p > 0, p * log(p), 0))
        anyp <- anyp + terra::ifel(is.na(p), 0, 1)
      }
      out <- terra::ifel(anyp > 0, -acc, NA)
      wr(character(), paste0("_shannon", sfx), out)
    }
  }

  # 4) 边缘密度（Python: e[~valid] = nan）
  if ("edge" %in% which_parts) {
    e <- edge_indicator(cls, valid)
    e <- terra::ifel(valid == 1, e, NA)
    wr(character(), "_edge", e)
    for (k in seq_len(nrow(fs)))
      wr(character(), paste0("_edge", fs$suffix[k]), focal_mean(e, fs$radius_cells[k], count = cnt[[k]]))
  }

  # 5) 斑块指标
  #    binary 必须是 0/1（无 NA）：Python 传的是布尔数组
  #      all    = valid                （中国内 1，境外 0）
  #      forest = (cls == 2)           （森林 1，其余含境外 0）
  if ("patch" %in% which_parts) {
    for (scope in c("all", "forest")) {
      binary <- cls
      terra::values(binary) <- if (scope == "all") {
        as.integer(!is.na(v) & v %in% codes)
      } else {
        as.integer(!is.na(v) & v == codes[which(cnames == "forest")])
      }
      # 若找不到 forest，退化为第一个类名含 forest 的类
      if (scope == "forest" && !any(cnames == "forest"))
        stop("legend 中找不到 forest 类")
      for (k in seq_len(nrow(fs))) {
        rc <- fs$radius_cells[k]
        pm <- patch_metric(binary, rc)
        if (!(scope == "all" && k == 1L))
          wr(character(), sprintf("_patchdensity-%s%s", scope, fs$suffix[k]), pm$density)
        wr(character(), sprintf("_patchsize-%s%s", scope, fs$suffix[k]), pm$msize)
        cat(sprintf("    %s r=%dkm done\n", scope, fs$radius_km[k]))
      }
    }
  }

  list(status = "ok", n = length(written), files = written)
}

main <- function(snap_idx = 1, which_parts = c("prop", "shannon", "edge", "patch")) {
  print_grid()
  s <- SNAPSHOTS[[snap_idx]]
  cat(sprintf("snapshot %d: year=%s ssp=%s src=%s\n", snap_idx, s$y,
              ifelse(is.na(s$ssp), "(hist)", s$ssp), s$f))
  t0 <- Sys.time()
  r <- derive_snapshot(s, which_parts)
  cat(sprintf("  %s : %d 层, %.0f 秒\n", r$status, r$n %||% 0,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  invisible(r)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

if (sys.nframe() == 0L) main()
