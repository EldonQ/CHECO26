# Rebuild all three 1-km statistics from one cleaned Hydrography90m source.
suppressPackageStartupMessages(library(terra))
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

rebuild_upstream_elevation <- function(raw_root, boundary_file) {
  tiles <- sort(list.files(raw_root, pattern = "^channel_elv_up_cel_h[0-9]+v[0-9]+[.]tif$",
                           full.names = TRUE, recursive = TRUE))
  if (!length(tiles)) stop("Hydrography90m upstream elevation tiles not found")
  tile_ids <- sub("^channel_elv_up_cel_", "", basename(tiles))
  if (anyDuplicated(tile_ids)) stop("Duplicate Hydrography90m source tiles")
  boundary <- terra::vect(boundary_file)
  parent <- normalizePath(ensure_dir(PATH_SCRATCH()), winslash = "/", mustWork = TRUE)
  scratch <- tempfile("h90m_upstream_", tmpdir = parent)
  dir.create(scratch, recursive = TRUE)
  scratch <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  stopifnot(identical(dirname(scratch), parent))
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)

  mosaic <- terra::vrt(tiles, filename = file.path(scratch, "source.vrt"))
  if (!terra::same.crs(mosaic, boundary)) boundary <- terra::project(boundary, terra::crs(mosaic))
  clipped <- terra::crop(mosaic, boundary, mask = TRUE, touches = TRUE,
                         filename = file.path(scratch, "china.tif"),
                         wopt = list(gdal = c("COMPRESS=DEFLATE", "TILED=YES")))
  sentinel <- as.numeric(CFG()$hydro90m_vars$src_sentinel$channel_elv_up_cel)
  clean <- terra::ifel(clipped >= sentinel, NA, clipped,
                       filename = file.path(scratch, "clean.tif"),
                       wopt = list(gdal = c("COMPRESS=DEFLATE", "TILED=YES")))
  parts <- c("reg", "hydro", "h90m", "channel-elv-up-cel")
  for (method in c("average", "min", "max")) {
    out <- layer_path(parts, switch(method, average = "", paste0("_", method)))
    warp_to_template(terra::sources(clean)[1], out, method = method)
    if (!check_alignment(out)) stop("Alignment check failed: ", out)
    cat(method, out, "\n")
  }
  invisible(tiles)
}

main <- function() {
  raw_root <- Sys.getenv("CHECO_H90M_RAW", "E:/h90m/China_Hydrography90m/Raw")
  boundary <- Sys.getenv("CHECO_H90M_BOUNDARY", "E:/h90m/china/china.shp")
  rebuild_upstream_elevation(raw_root, boundary)
}

if (sys.nframe() == 0L) main()
