# The upstream-cell elevation trio uses the pinned source inventory and a separate sentinel rule.
root <- Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM")
stage <- new.env(parent = globalenv())
source(file.path(root, "R/19_rebuild_h90m_legacy.R"), local = stage, encoding = "UTF-8")
raw <- Sys.getenv("CHECO_H90M_RAW", "E:/h90m/China_Hydrography90m/Raw")
files <- stage$h90m_native_inputs(raw, "channel_elv_up_cel")
stopifnot(length(files) == 20L, !anyDuplicated(files))
stopifnot(CFG()$hydro90m_vars$src_sentinel$channel_elv_up_cel == 50000)
stopifnot(!"channel_elv_up_cel" %in% names(stage$h90m_legacy_manifest()))
layers <- list.files(file.path(PATH_COV(), "reg", "hydro", "h90m", "channel-elv-up-cel"),
                     pattern = "[.]tif$", full.names = TRUE)
stopifnot(length(layers) == 3L, all(vapply(layers, check_alignment, TRUE)))
values <- lapply(layers, raster_stats)
stopifnot(length(unique(vapply(values, function(x) x$n, 0))) == 1L,
          max(vapply(values, function(x) x$max, 0)) < 50000)
cat("Upstream elevation inputs, sentinel exclusion, and delivered grids verified\n")
