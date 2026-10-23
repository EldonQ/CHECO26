# =============================================================================
# R/00_config.R  --  CHEco26 v2.0 参数加载
#
# 设计原则：scripts/config.yaml 仍是**唯一**参数来源。
# 本文件只负责读入与派生，不含任何硬编码的网格/窗口/比例参数。
# 代码里出现的字面量必须是"格式"而非"参数"（如 "float32"、"deflate"）。
# =============================================================================

suppressPackageStartupMessages({
  library(yaml)
  library(terra)
})

# ---- 仓库根 ----------------------------------------------------------------
# 优先级：环境变量 CHECO_ROOT > 脚本所在目录的上一级 > 本机默认
.checo_root <- function() {
  e <- Sys.getenv("CHECO_ROOT", "")
  if (nzchar(e)) return(normalizePath(e, mustWork = FALSE))
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit) == 1L) {
    f <- normalizePath(sub("^--file=", "", hit), mustWork = FALSE)
    return(normalizePath(file.path(dirname(f), ".."), mustWork = FALSE))
  }
  normalizePath(Sys.getenv("CHECO_ROOT", getwd()), mustWork = FALSE)
}

CHECO_ROOT <- .checo_root()

# ---- 配置读取（带缓存） ----------------------------------------------------
.cfg_cache <- new.env(parent = emptyenv())

#' 读取 config.yaml（缓存）
#' @param reload TRUE 时强制重读
CFG <- function(reload = FALSE) {
  if (reload || is.null(.cfg_cache$v)) {
    p <- file.path(CHECO_ROOT, "scripts", "config.yaml")
    if (!file.exists(p)) stop("config.yaml not found: ", p)
    .cfg_cache$v <- yaml::read_yaml(p)
  }
  .cfg_cache$v
}

#' 取配置中的一个路径（统一成 / 分隔、去掉结尾斜杠）
P <- function(key) {
  v <- CFG()$paths[[key]]
  if (is.null(v)) stop("paths.", key, " not defined in config.yaml")
  sub("/+$", "", gsub("\\\\", "/", v))
}

# ---- 网格规格（由 config 派生，不硬编码） ----------------------------------
#' @return list(rast=<模板 SpatRaster>, res, xmin, ymin, xmax, ymax, width, height, crs)
#'
#' CRS 权威来源说明（2026-10-19 核实）：
#'   config.yaml 的 crs_wkt 与 data/template_albers1km.tif 的 CRS **proj4 完全相同**
#'   （+proj=aea +lat_0=0 +lon_0=105 +lat_1=25 +lat_2=47 +x_0=0 +y_0=0 +datum=WGS84
#'    +units=m +no_defs），仅 WKT 文本的 AUTHORITY/AXIS 元数据节点不同。
#'   为保证新层与既有 1,600 层的 WKT 逐字节一致，**优先采用模板文件的 CRS**；
#'   模板不存在时才回退到 config 的 WKT。
GRID <- function() {
  g <- CFG()$grid
  res <- as.numeric(g$resolution)
  xmin <- as.numeric(g$xmin); ymin <- as.numeric(g$ymin)
  xmax <- as.numeric(g$xmax); ymax <- as.numeric(g$ymax)
  width  <- as.integer(round((xmax - xmin) / res))
  height <- as.integer(round((ymax - ymin) / res))

  tpl_path <- file.path(dirname(P("covariates")), "template_albers1km.tif")
  crs_use <- if (file.exists(tpl_path)) terra::crs(terra::rast(tpl_path)) else g$crs_wkt

  list(
    res = res, xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax,
    width = width, height = height,
    crs = crs_use,
    rast = terra::rast(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
                       resolution = res, crs = crs_use)
  )
}

# ---- 焦点窗口（由 config 派生） --------------------------------------------
#' @return data.frame(radius_km, radius_cells, size, suffix)
FOCAL_SPEC <- function() {
  radii <- as.integer(unlist(CFG()$focal$radii_km))
  res   <- as.numeric(CFG()$grid$resolution)
  data.frame(
    radius_km    = radii,
    radius_cells = as.integer(round(radii * 1000 / res)),
    size         = 2L * as.integer(round(radii * 1000 / res)) + 1L,
    suffix       = sprintf("_f%d", radii * 1000L),
    stringsAsFactors = FALSE
  )
}

# ---- nodata 常量 -----------------------------------------------------------
NODATA <- function() as.numeric(CFG()$nodata$float)
NODATA_CAT <- function() as.integer(CFG()$nodata$uint8_categorical)

# ---- 常用路径 --------------------------------------------------------------
PATH_COV     <- function() P("covariates")
PATH_DOCS    <- function() P("docs")
PATH_LOGS    <- function() P("logs")
PATH_SCRATCH <- function() P("scratch")
PATH_ARCHIVE <- function() P("archive")
# 网格模板与中国掩膜放在 data/ 下（covariates 的上一级）
PATH_DATA    <- function() dirname(PATH_COV())
PATH_MASK    <- function() file.path(PATH_DATA(), "mask_china.tif")
PATH_TEMPLATE<- function() file.path(PATH_DATA(), "template_albers1km.tif")

#' 确保目录存在
ensure_dir <- function(p) {
  if (!dir.exists(p)) dir.create(p, recursive = TRUE, showWarnings = FALSE)
  invisible(p)
}

# ---- 自检：启动时打印关键网格信息 ------------------------------------------
#' 打印网格规格，便于日志留痕
print_grid <- function() {
  g <- GRID()
  cat(sprintf("网格: %d x %d @ %.0f m | x[%.0f, %.0f] y[%.0f, %.0f]\n",
              g$width, g$height, g$res, g$xmin, g$xmax, g$ymin, g$ymax))
  fs <- FOCAL_SPEC()
  cat("焦点窗口:", paste(sprintf("%dkm(%dx%d)%s", fs$radius_km, fs$size, fs$size,
                                 fs$suffix), collapse = "  "), "\n")
  cat(sprintf("nodata: 连续=%.0f  分类=%d\n", NODATA(), NODATA_CAT()))
  invisible(NULL)
}
