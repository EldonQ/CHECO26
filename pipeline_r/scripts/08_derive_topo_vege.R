# =============================================================================
# R/08_derive_topo_vege.R  --  topo 坡向/TRI + 土壤剖面加权
#
# 对应 Python: scripts/06_derive_topo_vege.py
#
# 产出（30 层）：
#   topo/chinadem/aspect   1 层   Horn (1981) 坡向，度 0-360（北=0，顺时针）
#   topo/chinadem/tri      1 层   Riley et al. (1999) 3x3 高差 RMS
#   soil/csdlv2/<attr>_profile  28 层   0-100cm 层厚加权均值（权重 5/10/15/30/40 cm）
#
# 口径要点：
#   * aspect/tri 必须基于 **02 掩膜后的 elev 层**（境外高程不参与邻域）
#   * 边界用 np.pad(mode="edge") 等价的复制填充
#   * tri 的 NaN 差值按 0 计（np.nan_to_num）
#   * profile 的分母是"有效层的权重之和"，不是固定 100
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

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
PROFILE_DEPTHS  <- c("0", "5", "15", "30", "60")
PROFILE_WEIGHTS <- c(5, 10, 15, 30, 40)   # 层厚 cm，合计 100

# ---- 边界复制填充（等价 np.pad(mode="edge")）--------------------------------
pad_edge <- function(m) {
  nr <- nrow(m); nc <- ncol(m)
  out <- matrix(NA_real_, nr + 2L, nc + 2L)
  out[2:(nr + 1L), 2:(nc + 1L)] <- m
  out[1L, ] <- out[2L, ]
  out[nr + 2L, ] <- out[nr + 1L, ]
  out[, 1L] <- out[, 2L]
  out[, nc + 2L] <- out[, nc + 1L]
  out
}

# ---- Horn (1981) 坡向 ------------------------------------------------------
horn_aspect <- function(elev, res) {
  valid <- !is.na(elev)
  z <- elev
  zp <- pad_edge(z)
  nr <- nrow(z); nc <- ncol(z)
  a <- zp[1:nr, 1:nc];            b <- zp[1:nr, 2:(nc + 1L)];  cc <- zp[1:nr, 3:(nc + 2L)]
  d <- zp[2:(nr + 1L), 1:nc];                                  f  <- zp[2:(nr + 1L), 3:(nc + 2L)]
  g <- zp[3:(nr + 2L), 1:nc];     h <- zp[3:(nr + 2L), 2:(nc + 1L)]; i <- zp[3:(nr + 2L), 3:(nc + 2L)]
  dzdx <- ((cc + 2 * f + i) - (a + 2 * d + g)) / (8 * res)
  dzdy <- ((g + 2 * h + i) - (a + 2 * b + cc)) / (8 * res)
  asp <- atan2(dzdy, -dzdx) * 180 / pi
  out <- ifelse(asp < 0, 90 - asp, 450 - asp) %% 360
  flat <- (dzdx == 0) & (dzdy == 0)
  out[flat | !valid] <- NA
  out
}

# ---- Riley et al. (1999) TRI ----------------------------------------------
riley_tri <- function(elev) {
  valid <- !is.na(elev)
  z <- elev
  zp <- pad_edge(z)
  nr <- nrow(z); nc <- ncol(z)
  acc <- matrix(0, nr, nc)
  for (dr in 0:2) for (dc in 0:2) {
    if (dr == 1L && dc == 1L) next
    seg <- zp[(dr + 1L):(dr + nr), (dc + 1L):(dc + nc)]
    diff <- seg - z
    diff[is.na(diff)] <- 0          # np.nan_to_num
    acc <- acc + diff^2
  }
  out <- sqrt(acc / 8)
  out[!valid] <- NA
  out
}

# ---- 土壤剖面加权 ----------------------------------------------------------
#' @param adir 属性目录名
#' @param dst  输出路径；NULL 时用 layer_path（受 CHECO_OUT_ROOT 控制）
#' @param src_root 输入层根目录；NULL 时用 PATH_COV()
#'   注意：输入与输出必须能分别定位。测试时若用 CHECO_OUT_ROOT 重定向输出，
#'   输入仍在正式树里，故需显式传 src_root=PATH_COV()。
soil_profile <- function(adir, dst = NULL, src_root = NULL) {
  root_in <- if (is.null(src_root)) PATH_COV() else src_root
  in_path <- function(parts, suffix = "") {
    d <- do.call(file.path, as.list(c(root_in, parts)))
    file.path(d, paste0(paste(parts, collapse = "_"), suffix, ".tif"))
  }
  if (is.null(dst)) dst <- layer_path(c("glo", "soil", "csdlv2", adir), "_profile")
  if (file.exists(dst) && !identical(Sys.getenv("CHECO_FORCE"), "1") && check_alignment(dst))
    return(list(status = "skip", dst = dst))

  num <- NULL; den <- NULL
  for (k in seq_along(PROFILE_DEPTHS)) {
    p <- in_path(c("glo", "soil", "csdlv2", adir, PROFILE_DEPTHS[k]))
    if (!file.exists(p)) return(list(status = "error", dst = dst, note = paste("missing", p)))
    m <- terra::as.matrix(read_clean_r(p), wide = TRUE)
    if (is.null(num)) { num <- matrix(0, nrow(m), ncol(m)); den <- num }
    ok <- !is.na(m)
    w <- PROFILE_WEIGHTS[k]
    num <- num + ifelse(ok, m * w, 0)
    den <- den + ifelse(ok, w, 0)
  }
  out <- matrix(NA_real_, nrow(num), ncol(num))
  ok <- den > 0
  out[ok] <- num[ok] / den[ok]
  g <- GRID()
  rr <- terra::rast(out, extent = terra::ext(g$rast), crs = g$crs)
  atomic_write_raster(dst, rr, dtype = "float32")
  if (!check_alignment(dst)) return(list(status = "error", dst = dst, note = "alignment"))
  list(status = "ok", dst = dst)
}

#' 读层并把 nodata 归一为 NA（本脚本内部用）
read_clean_r <- function(path) {
  r <- terra::rast(path)
  nd <- terra::NAflag(r)
  v <- terra::values(r, mat = FALSE)
  if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
  v[is.nan(v)] <- NA
  terra::values(r) <- v
  r
}

# ---- 主流程 --------------------------------------------------------------
main <- function(which = c("topo", "profile")) {
  which <- match.arg(which)
  print_grid()

  if (which == "topo") {
    ep <- layer_path(c("glo", "topo", "chinadem", "elev"))
    if (!file.exists(ep)) stop("elev 层不存在，请先跑 03_ingest_static.R")
    elev <- terra::as.matrix(read_clean_r(ep), wide = TRUE)
    res <- as.numeric(CFG()$grid$resolution)
    cat(sprintf("  elev: %d x %d, 有效 %s\n", nrow(elev), ncol(elev),
                format(sum(!is.na(elev)), big.mark = ",")))
    g <- GRID()

    t0 <- Sys.time()
    asp <- horn_aspect(elev, res)
    d1 <- layer_path(c("glo", "topo", "chinadem", "aspect"))
    atomic_write_raster(d1, terra::rast(asp, extent = terra::ext(g$rast), crs = g$crs), dtype = "float32")
    cat(sprintf("  aspect: %.1f 秒, 值域 [%.2f, %.2f]\n",
                as.numeric(difftime(Sys.time(), t0, units = "secs")),
                min(asp, na.rm = TRUE), max(asp, na.rm = TRUE)))

    t0 <- Sys.time()
    tri <- riley_tri(elev)
    d2 <- layer_path(c("glo", "topo", "chinadem", "tri"))
    atomic_write_raster(d2, terra::rast(tri, extent = terra::ext(g$rast), crs = g$crs), dtype = "float32")
    cat(sprintf("  tri   : %.1f 秒, 值域 [%.2f, %.2f]\n",
                as.numeric(difftime(Sys.time(), t0, units = "secs")),
                min(tri, na.rm = TRUE), max(tri, na.rm = TRUE)))
    cat(sprintf("  四查 aspect=%s tri=%s\n", check_alignment(d1), check_alignment(d2)))
  } else {
    t0 <- Sys.time(); nok <- 0L; nskip <- 0L; nerr <- 0L
    for (adir in unname(SOIL_ATTR_DIR)) {
      r <- tryCatch(soil_profile(adir), error = function(e) list(status = "error", note = conditionMessage(e)))
      if (identical(r$status, "ok")) nok <- nok + 1L
      else if (identical(r$status, "skip")) nskip <- nskip + 1L
      else { nerr <- nerr + 1L; cat(sprintf("  ERR %s: %s\n", adir, r$note)) }
    }
    cat(sprintf("  土壤剖面: ok=%d skip=%d err=%d, %.0f 秒\n", nok, nskip, nerr,
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
  invisible(NULL)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) a[1] else "topo")
}
