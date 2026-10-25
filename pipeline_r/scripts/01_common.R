# =============================================================================
# R/01_common.R  --  通用工具：模板、掩膜、重投影、焦点、原子写、四查
#
# 与早期 common.py 的对应关系（该脚本已归档）（逐函数）：
#   grid_spec      -> GRID()             （00_config.R）
#   china_mask     -> china_mask()
#   apply_china_mask -> apply_china_mask()
#   layer_path     -> layer_path()
#   atomic_write_raster -> atomic_write_raster()
#   warp_to_template -> warp_to_template()
#   focal_mean     -> focal_mean()       （语义见下，与 scipy 版逐点等价）
#   check_alignment -> check_alignment()
#
# 与 Python 版刻意不同的**一处**（缺陷修复，已记录）：
#   Python 的 atomic_write_raster 直接 arr.astype(dtype)，NaN 保持 NaN，而文件头
#   声明 nodata=-9999，造成"821 层用 NaN、779 层用 −9999"的双编码（D7）。
#   本实现把无效值统一写成 NODATA(=−9999)，读回时只有一种无效编码。
# =============================================================================

suppressPackageStartupMessages({
  library(terra)
})

# ---- 中国掩膜 --------------------------------------------------------------
.mask_cache <- new.env(parent = emptyenv())

#' 读取中国掩膜（1=境内），返回 SpatRaster（与模板同几何）
china_mask <- function() {
  if (is.null(.mask_cache$v)) {
    m <- terra::rast(PATH_MASK())
    # 掩膜层允许 0/1 或 1/NA；统一成逻辑：>0 且非 NA 视为境内
    .mask_cache$v <- !is.na(m) & (m > 0)
  }
  .mask_cache$v
}

#' 把境外像元置为指定填充值（默认 NA）
apply_china_mask <- function(x, fill = NA) {
  m <- china_mask()
  terra::mask(x, m, maskvalue = FALSE, updatevalue = fill)
}

# ---- 路径构造 --------------------------------------------------------------
#' 与 Python common.layer_path 等价
#'
#' 输出根可被环境变量 CHECO_OUT_ROOT 重定向（测试用）：
#'   置空时写正式交付树 PATH_COV()；置为某目录时写该目录下的同构子树。
#' 这样测试永远不会覆盖交付数据。
#' @param parts 目录层级，如 c("glo","anthro","hfp","2020","hfp")
#' @param suffix 文件名后缀，如 ""、"_prop"、"_f5000"
layer_path <- function(parts, suffix = "") {
  ov <- Sys.getenv("CHECO_OUT_ROOT", "")
  base <- if (nzchar(ov)) ov else PATH_COV()
  dir <- do.call(file.path, as.list(c(base, parts)))
  stem <- paste(parts, collapse = "_")
  file.path(dir, paste0(stem, suffix, ".tif"))
}

# ---- 原子写 ----------------------------------------------------------------
#' 数据类型映射：用户侧用 GDAL 习惯名，terra 侧用其自有代号
.dtype_map <- c(
  float32 = "FLT4S", float64 = "FLT8S",
  uint8 = "INT1U", int8 = "INT1S",
  int16 = "INT2S", uint16 = "INT2U",
  int32 = "INT4S"
)

#' 写 GeoTIFF：DEFLATE、256x256 分块、nodata=-9999
#' 无效值（NA / NaN）统一写成 nodata（修复 Python 版 NaN/-9999 双编码的缺陷）
atomic_write_raster <- function(dst, x, dtype = "float32") {
  ensure_dir(dirname(dst))
  dt <- .dtype_map[[dtype]]
  if (is.null(dt)) stop("unsupported dtype: ", dtype)
  nd <- if (dtype %in% c("float32", "float64")) NODATA() else NODATA_CAT()

  if (!inherits(x, "SpatRaster")) x <- terra::rast(x)
  if (dtype %in% c("float32", "float64")) {
    x <- terra::ifel(is.na(x), nd, x)
    terra::NAflag(x) <- nd
  } else {
    x <- terra::ifel(is.na(x), as.integer(nd), x)
    terra::NAflag(x) <- as.integer(nd)
  }

  # 临时文件必须保留 .tif 扩展名，否则 terra 无法推断格式
  tmp <- paste0(sub("\\.tif$", "", dst), ".tmp.tif")
  # NAflag 必须显式传给 writeRaster：只设 terra::NAflag(x) 在部分路径上不落到文件头，
  # 结果 nodata 被写成 NaN，−9999 被当数据读回（2026-10-19 实测）。
  terra::writeRaster(x, tmp, overwrite = TRUE, datatype = dt, NAflag = nd,
                     gdal = c("COMPRESS=DEFLATE", "TILED=YES",
                              "BLOCKXSIZE=256", "BLOCKYSIZE=256",
                              "PREDICTOR=3", "BIGTIFF=IF_SAFER"))
  if (file.exists(dst)) file.remove(dst)
  ok <- file.rename(tmp, dst)
  if (!ok) stop("atomic rename failed: ", dst)
  invisible(dst)
}

# ---- 重投影到模板 ----------------------------------------------------------
#' config.yaml 的重采样名 -> terra::project 的方法名
#' 关键差异：config 用 GDAL/rasterio 的 "nearest"，terra 只认 "near"。
TERRA_METHOD <- c(nearest = "near", near = "near", bilinear = "bilinear",
                  average = "average", mode = "mode", min = "min", max = "max",
                  cubic = "cubic", cubicspline = "cubicspline", lanczos = "lanczos")

terra_method <- function(m) {
  out <- TERRA_METHOD[[m]]
  if (is.null(out)) stop("unsupported resampling method: ", m,
                         " (known: ", paste(names(TERRA_METHOD), collapse = ", "), ")")
  unname(out)
}

#' @param src 源文件路径
#' @param dst 目标路径
#' @param method config 的重采样名（"nearest"/"bilinear"/"average"/"mode"/"min"/"max"）
#' @param src_nodata 源 nodata（NULL 表示用源文件自带）
#' @param scale 数值缩放（NULL 表示不缩放）
#' @param apply_mask 是否套中国掩膜（默认 TRUE）
warp_to_template <- function(src, dst, method, src_nodata = NULL,
                             scale = NULL, apply_mask = TRUE,
                             dtype = "float32") {
  r <- terra::rast(src)
  if (!is.null(src_nodata)) terra::NAflag(r) <- src_nodata
  tmpl <- GRID()$rast
  out <- terra::project(r, tmpl, method = terra_method(method), align = FALSE)
  if (!is.null(scale)) out <- out * as.numeric(scale)
  if (apply_mask) out <- apply_china_mask(out, NA)
  atomic_write_raster(dst, out, dtype = dtype)
  dst
}

# ---- 焦点均值 --------------------------------------------------------------
#' 方形窗的 2D 盒滤波可分离：行方向 1D 再列方向 1D，复杂度 O(k) 而非 O(k^2)。
#' 实测（19.7M 像元）：3x3 略慢（两次 pass 开销），11x11 持平，21x21 快 1.9x，
#' 41x41 快 4.7x；与完整卷积版本**逐位相同**（max|d| = 0，掩膜差异 0）。
focal_sum_sep <- function(x, radius_cells) {
  rc <- as.integer(radius_cells)
  size <- 2L * rc + 1L
  xv <- terra::ifel(is.na(x), 0, x)
  wh <- matrix(1, nrow = 1, ncol = size)
  wv <- matrix(1, nrow = size, ncol = 1)
  terra::focal(terra::focal(xv, wh, fun = "sum", na.policy = "all", na.rm = TRUE),
               wv, fun = "sum", na.policy = "all", na.rm = TRUE)
}

#' 窗口内有效像元计数（可分离）
focal_count_sep <- function(valid, radius_cells) {
  rc <- as.integer(radius_cells)
  size <- 2L * rc + 1L
  vv <- terra::ifel(is.na(valid), 0, terra::ifel(valid > 0, 1, 0))
  wh <- matrix(1, nrow = 1, ncol = size)
  wv <- matrix(1, nrow = size, ncol = 1)
  terra::focal(terra::focal(vv, wh, fun = "sum", na.policy = "all", na.rm = TRUE),
               wv, fun = "sum", na.policy = "all", na.rm = TRUE)
}

#' 等权焦点均值，与 Python common.focal_mean 等价
#'
#' Python 语义（scipy.ndimage.uniform_filter，mode="constant", cval=0）：
#'   size   = 2*radius_cells + 1           方形窗
#'   s      = 窗口内 (有效值, 无效记 0) 的均值
#'   c      = 窗口内 有效掩膜 的均值
#'   ok     = c >= 0.5/size^2  等价于「窗口内至少 1 个有效像元」
#'   out    = s/c  (ok)，否则 NA
#'
#' **terra 参数选择说明（2026-10-19 实测纠正）**：
#'   na.policy 必须用 "all"。取 "omit" 时 terra 是「中心像元为 NA 就不算」，
#'   而 Python 是「窗口内 ≥1 个有效像元就算」，两者在中国境内 0.18% 的像元上分歧
#'   （实测 vege/ch2019 的 f5000：16,971 元 R 给 NA 而 Python 有值）。
#'
#' @param x SpatRaster（单层）
#' @param radius_cells 半径（格）
#' @param count 可选：预先算好的分母（同窗口的有效像元计数 SpatRaster）。
#'              批量处理同类 one-hot 时只算一次分母，可省一半时间。
focal_mean <- function(x, radius_cells, count = NULL) {
  rc <- as.integer(radius_cells)
  size <- 2L * rc + 1L
  if (size >= 21L) {
    s <- focal_sum_sep(x, rc)
    c <- if (is.null(count)) focal_count_sep(terra::ifel(is.na(x), NA, 1), rc) else count
    return(terra::ifel(c >= 0.5, s / c, NA))
  }
  w <- matrix(1, nrow = size, ncol = size)
  out <- terra::focal(x, w = w, fun = "mean", na.policy = "all", na.rm = TRUE)
  terra::ifel(is.nan(out), NA, out)
}

#' 一次算完所有焦点半径，返回命名列表
focal_all <- function(x) {
  fs <- FOCAL_SPEC()
  setNames(lapply(fs$radius_cells, function(rc) focal_mean(x, rc)), fs$suffix)
}

# ---- 模板四查 --------------------------------------------------------------
#' 检查 CRS / 分辨率 / extent / 尺寸 与模板一致
#'
#' CRS 用 proj4 语义比较，而非 WKT 文本：config 的 WKT 与模板 WKT 仅元数据节点不同，
#' 文本比较会误判（2026-10-19 实测：proj4 完全相同但 WKT 字符串不同）。
check_alignment <- function(path) {
  if (!file.exists(path)) return(FALSE)
  r <- tryCatch(terra::rast(path), error = function(e) NULL)
  if (is.null(r)) return(FALSE)
  g <- GRID()
  same_crs <- identical(terra::crs(r, proj = TRUE), terra::crs(g$rast, proj = TRUE))
  same_res <- isTRUE(all.equal(terra::res(r), c(g$res, g$res)))
  same_ext <- isTRUE(all.equal(as.vector(terra::ext(r)),
                               as.vector(terra::ext(g$rast))))
  same_dim <- ncol(r) == g$width && nrow(r) == g$height
  isTRUE(same_crs && same_res && same_ext && same_dim)
}

# ---- 值域统计（写盘后自检用） ----------------------------------------------
raster_stats <- function(path) {
  r <- terra::rast(path)
  v <- terra::values(r, mat = FALSE)
  nd <- terra::NAflag(r)
  if (!is.na(nd)) v <- v[v != nd]
  v <- v[!is.na(v)]
  if (!length(v)) return(list(n = 0L, min = NA_real_, max = NA_real_))
  list(n = length(v), min = min(v), max = max(v))
}

# ---- 源哨兵清理 ------------------------------------------------------------
#' 把源中 >= sentinel 的值改成 nodata，再交给聚合/统计。
#'
#' 背景：Hydrography90m 的 channel_elv_up_cel 用 99999 标记出口像元，但该哨兵被
#' GRASS 累加扩散，实测 >50000 的像元共 30,739 个，取值区间 [99,838, 105,245]。
#' 阈值必须取该污染带以下的**下界**（50,000）；若按 99,999 掩膜会漏掉
#' [99,838, 99,998] 的 12 个像元，经 90m->1km 平均后仍把单像元放大到 ~800 m。
#'
#' 缓存键包含阈值：阈值一变必须重算，否则会命中旧缓存（2026-10-19 踩过）。
#'
#' **必须流式落盘**：90 m 全国源约 24 亿像元。任何"先生成中间栅格再写"的写法
#' （values() 整体读入、ifel 不给 filename）都会试图在内存中物化，
#' 实测直接 std::bad_alloc。故 ifel 必须带 filename，由 terra 分块写。
#' @param src 源栅格路径
#' @param sentinel 阈值（>= 该值的像元视为哨兵）
#' @param tag 缓存标识（通常用目标文件名去扩展名）
mask_source_sentinel <- function(src, sentinel, tag) {
  if (is.null(sentinel) || is.na(sentinel)) return(src)
  dst <- file.path(PATH_SCRATCH(), "sentinel_masked",
                   sprintf("%s__ge%.0f.tif", tag, sentinel))
  if (file.exists(dst)) return(dst)
  ensure_dir(dirname(dst))

  r <- terra::rast(src)
  nd <- terra::NAflag(r)
  if (is.na(nd)) nd <- NODATA()
  dt <- if (terra::is.int(r)) "INT4S" else "FLT4S"
  tmp <- paste0(sub("\\.tif$", "", dst), ".tmp.tif")
  out <- terra::ifel(r >= sentinel, nd, r, filename = tmp, overwrite = TRUE,
                     datatype = dt, NAflag = nd,
                     gdal = c("COMPRESS=DEFLATE", "TILED=YES", "BIGTIFF=IF_SAFER"))
  if (file.exists(dst)) file.remove(dst)
  if (!file.rename(tmp, dst)) stop("rename failed: ", dst)
  cat(sprintf("  sentinel %.8g masked -> %s\n", sentinel, basename(dst)))
  dst
}

# ---- 记录 ----------------------------------------------------------------
#' 追加一行 CSV 日志（自动建表头）
append_log <- function(path, row) {
  ensure_dir(dirname(path))
  df <- as.data.frame(row, stringsAsFactors = FALSE)
  write.table(df, path, sep = ",", row.names = FALSE,
              col.names = !file.exists(path), append = file.exists(path),
              quote = TRUE, fileEncoding = "UTF-8")
  invisible(path)
}
