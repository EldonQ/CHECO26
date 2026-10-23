# R/tests/test_31_patch_direct.R -- 只重算 2020 快照的 4 个 patch 层并比对（不重跑 prop）
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
OUT <- "E:/CHECO26/N-SDM/scratch/r_lulc_full"
Sys.setenv(CHECO_OUT_ROOT = OUT)
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/05_derive_lulc.R", envir = .ing)
snap <- .ing$SNAPSHOTS[[1]]
cfg <- CFG(); legend <- unlist(cfg$lulc_legend)
legend <- legend[order(as.integer(names(legend)))]
codes <- as.integer(names(legend)); cnames <- as.character(legend)
fs <- FOCAL_SPEC()

# 重建 cls（与 derive_snapshot 一致）
src <- file.path(P("lulc_raw"), snap$f)
r <- terra::rast(src); terra::NAflag(r) <- 0
cls <- terra::project(r, GRID()$rast, method = terra_method(cfg$resampling$categorical), align = FALSE)
m <- china_mask()
v <- terra::values(cls, mat = FALSE); mm <- terra::values(m, mat = FALSE)
v[is.na(mm) | mm != 1] <- 255
v[!is.na(v) & !(v %in% codes)] <- 255
terra::values(cls) <- v
valid <- cls; terra::values(valid) <- as.integer(!is.na(v) & v %in% codes)

REF <- file.path(PATH_COV(), "glo/lulc/glu1km/2020")
OUTD <- file.path(OUT, "glo/lulc/glu1km/2020")

cat("=== 重算 2020 快照 patch 层（已修 labm=0 索引 bug）===\n\n")
res <- list()
for (scope in c("all", "forest")) {
  binary <- cls
  terra::values(binary) <- if (scope == "all") as.integer(!is.na(v) & v %in% codes)
                           else as.integer(!is.na(v) & v == codes[which(cnames == "forest")])
  for (k in seq_len(nrow(fs))) {
    rc <- fs$radius_cells[k]; sfx <- fs$suffix[k]
    t0 <- Sys.time()
    pm <- .ing$patch_metric(binary, rc)
    el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    for (metric in c("patchdensity", "patchsize")) {
      fname <- sprintf("glo_lulc_glu1km_2020_%s-%s_f%d.tif", metric, scope, fs$radius_km[k] * 1000)
      ref <- file.path(REF, fname)
      if (!file.exists(ref)) next
      got_arr <- if (metric == "patchdensity") pm$density else pm$msize
      got_arr <- apply_china_mask(got_arr, NA)
      dst <- file.path(OUTD, fname)
      ensure_dir(dirname(dst)); atomic_write_raster(dst, got_arr, dtype = "float32")
      cm <- compare_layers(read_clean(dst), read_clean(ref))
      res[[fname]] <- cm$pass
      cat(sprintf("  %-46s %s | %s\n", fname, ifelse(cm$pass, "PASS", "FAIL"), fmt_cmp(cm)))
    }
    cat(sprintf("    (%s r=%dkm 计算 %.1fs)\n", scope, fs$radius_km[k], el))
  }
}
cat(sprintf("\n=== %d / %d 通过 ===\n", sum(unlist(res)), length(res)))
