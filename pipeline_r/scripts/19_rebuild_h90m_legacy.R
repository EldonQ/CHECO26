# Reproduce the legacy h90m exports directly from pinned native tiles.
suppressPackageStartupMessages(library(terra))
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

h90m_legacy_manifest <- function() {
  cfg <- CFG()
  hydro <- cfg$hydro90m_vars
  vars <- setdiff(c(unlist(hydro$categorical), unlist(hydro$continuous)),
                  c(unlist(hydro$withdrawn), "channel_elv_up_cel"))
  ans <- lapply(vars, function(v) {
    theme <- if (startsWith(v, "stream_dist_")) "dist" else "hydro"
    method <- if (v %in% unlist(hydro$categorical)) "mode" else "average"
    extras <- if (v %in% unlist(cfg$hydro_stats_addon$minmax)) c("min", "max")
              else if (v %in% unlist(cfg$hydro_stats_addon$maxonly)) "max"
    list(var = v, parts = c("reg", theme, "h90m", gsub("_", "-", v)),
         methods = c(method, extras), scale = hydro$scale_by_var[[v]])
  })
  setNames(ans, vars)
}

h90m_inventory <- function() {
  file <- file.path(PATH_DOCS(), "H90M_SOURCE_MANIFEST.csv")
  if (!file.exists(file)) stop("Missing h90m input inventory: ", file)
  read.csv(file, stringsAsFactors = FALSE)
}

verify_h90m_inputs <- function(paths, expected) {
  sizes <- file.info(paths)$size
  if (anyNA(sizes) || !all(sizes == expected$bytes))
    stop("Missing file or byte count mismatch in pinned h90m inputs: ",
         paste(paths[is.na(sizes) | sizes != expected$bytes], collapse = "; "))
  if (identical(Sys.getenv("CHECO_VERIFY_H90M_SOURCE"), "1")) {
    hashes <- vapply(paths, function(p) digest::digest(file = p, algo = "sha256"), "")
    if (!all(hashes == expected$sha256)) stop("SHA-256 mismatch in pinned h90m inputs")
  }
}

h90m_native_inputs <- function(raw_root, variable) {
  expected <- h90m_inventory()
  expected <- expected[expected$kind == "native" & expected$variable == variable, ]
  ids <- as.character(unlist(CFG()$hydro90m_vars$tile_ids))
  if (length(ids) != 20L || nrow(expected) != length(ids) || !setequal(ids, expected$tile))
    stop("Missing pinned h90m tile inventory for ", variable)
  expected <- expected[match(ids, expected$tile), ]
  paths <- file.path(raw_root, sub("^China_Hydrography90m/Raw/", "",
                                   expected$path_relative_to_h90m_root))
  verify_h90m_inputs(paths, expected)
  paths
}

h90m_boundary <- function(boundary_file) {
  ref <- h90m_inventory()
  ref <- ref[ref$kind == "boundary", ]
  ext <- tools::file_ext(ref$path_relative_to_h90m_root)
  stopifnot(nrow(ref) == 4L, setequal(ext, c("shp", "shx", "dbf", "prj")))
  files <- paste0(tools::file_path_sans_ext(boundary_file), ".", ext)
  verify_h90m_inputs(files, ref)
  terra::vect(boundary_file)
}

h90m_existing_output <- function(path) {
  file.exists(path) && !identical(Sys.getenv("CHECO_FORCE"), "1") && check_alignment(path)
}

rebuild_h90m_legacy <- function(variables = character(), only_methods = NULL,
                                raw_root = Sys.getenv("CHECO_H90M_RAW", "E:/h90m/China_Hydrography90m/Raw"),
                                boundary_file = Sys.getenv("CHECO_H90M_BOUNDARY", "E:/h90m/china/china.shp")) {
  tasks <- h90m_legacy_manifest()
  if (length(variables)) {
    if (!all(variables %in% names(tasks))) stop("Unknown legacy h90m variable")
    tasks <- tasks[variables]
  }
  base <- boundary <- NULL
  for (task in tasks) {
    methods <- task$methods
    suffix <- ifelse(methods %in% c("min", "max"), paste0("_", methods), "")
    paths <- vapply(suffix, function(x) layer_path(task$parts, x), "")
    pending <- !vapply(paths, h90m_existing_output, TRUE)
    if (!is.null(only_methods)) pending <- pending & methods %in% only_methods
    if (!any(pending)) next
    if (is.null(base)) {
      base <- normalizePath(ensure_dir(Sys.getenv("CHECO_H90M_WORK", PATH_SCRATCH())),
                            winslash = "/", mustWork = TRUE)
      boundary <- h90m_boundary(boundary_file)
    }
    files <- h90m_native_inputs(raw_root, task$var)
    rebuild_h90m_variable(task, files, boundary, base, methods[pending], paths[pending])
  }
  invisible(tasks)
}

h90m_clip_native <- function(files, boundary, tmp) {
  vrt <- terra::vrt(files, filename = file.path(tmp, "source.vrt"))
  if (!terra::same.crs(vrt, boundary)) boundary <- terra::project(boundary, terra::crs(vrt))
  src <- file.path(tmp, "china.tif")
  # On the legacy source grid, include cells whose centres are in the old China boundary.
  encoding <- terra::datatype(terra::rast(files[1]))
  options <- list(datatype = encoding,
                  gdal = c("COMPRESS=DEFLATE", "TILED=YES", "BIGTIFF=IF_SAFER", "NUM_THREADS=4"))
  # The uint32 default fill value cannot survive conversion to float32.
  # Native basin, segment and sub-catchment use 0 as their declared NoData.
  if (identical(encoding, "INT4U")) options$NAflag <- 0
  terra::crop(vrt, boundary, mask = TRUE, touches = FALSE, filename = src, wopt = options)
  src
}

rebuild_h90m_variable <- function(task, files, boundary, base, methods, paths) {
  tmp <- tempfile("h90m_legacy_", tmpdir = base)
  if (!dir.create(tmp)) stop("Cannot create h90m working directory")
  tmp <- normalizePath(tmp, winslash = "/", mustWork = TRUE)
  stopifnot(identical(dirname(tmp), base))
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  src <- h90m_clip_native(files, boundary, tmp)
  for (i in seq_along(methods)) {
    warp_to_template(src, paths[i], method = methods[i], scale = task$scale)
    if (!check_alignment(paths[i])) stop("h90m alignment failed: ", paths[i])
    cat(task$var, methods[i], paths[i], "\n")
    flush.console()
  }
}

main <- function(variables = character()) rebuild_h90m_legacy(variables)
if (sys.nframe() == 0L) main(commandArgs(trailingOnly = TRUE))
