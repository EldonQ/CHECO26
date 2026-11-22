# Aggregate Copernicus GLO-90 EGM2008 heights and derive terrain on the delivery grid.
# The chinadem path is retained for compatibility and denotes this new source.
suppressPackageStartupMessages(library(terra))
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

ingest_copdem90 <- function(source_dir) {
  source_manifest <- read.csv(file.path(source_dir, "source_tiles.csv"),
                              stringsAsFactors = FALSE)
  tiles <- file.path(source_dir, source_manifest$filename)
  if (!length(tiles) || anyDuplicated(tiles) || !all(file.exists(tiles)))
    stop("Incomplete Copernicus GLO-90 input manifest")
  tmp <- tempfile("copdem90_", fileext = ".vrt")
  on.exit(unlink(tmp), add = TRUE)
  mosaic <- terra::vrt(tiles, tmp, options = c("-resolution", "highest"))
  topography <- c("reg", "topo", "chinadem")
  terrain_helpers <- new.env(parent = globalenv())
  sys.source(file.path(R_DIR, "08_derive_topo_vege.R"), envir = terrain_helpers)
  elev <- apply_china_mask(terra::project(mosaic, GRID()$rast, method = "average", align = FALSE), NA)
  atomic_write_raster(layer_path(c(topography, "elev")), elev)
  # Read the stored float32 elevation so source and derivatives agree bit for bit.
  elev <- terra::rast(layer_path(c(topography, "elev")))
  supported <- terra::focal(!is.na(elev), w = 3, fun = "sum", fillvalue = 0) == 9
  slope <- terra::terrain(elev, v = "slope", unit = "degrees", neighbors = 8)
  atomic_write_raster(layer_path(c(topography, "slope")), terra::ifel(supported, slope, NA))
  matrix <- terra::as.matrix(elev, wide = TRUE)
  for (product in c("aspect", "tri")) {
    values <- switch(product,
                     aspect = terrain_helpers$horn_aspect(matrix, terra::res(elev)[1]),
                     tri = terrain_helpers$riley_tri(matrix))
    raster <- terra::rast(values, extent = terra::ext(elev), crs = terra::crs(elev))
    atomic_write_raster(layer_path(c(topography, product)), terra::ifel(supported, raster, NA))
  }
  invisible(length(tiles))
}

main <- function() {
  ingest_copdem90(Sys.getenv("CHECO_COPDEM90_SRC", "E:/CHECO26/DEM/Copernicus_GLO90_2021"))
}

if (sys.nframe() == 0L) main()
