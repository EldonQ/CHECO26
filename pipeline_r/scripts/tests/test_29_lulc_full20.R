# R/tests/test_29_lulc_full20.R -- 2020 快照四段全跑 + 15 层比对（含 patch）
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
OUT <- "E:/CHECO26/N-SDM/scratch/r_lulc_full"
Sys.setenv(CHECO_OUT_ROOT = OUT)
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

REF <- file.path(PATH_COV(), "glo/lulc/glu1km/2020")
#' shannon/edge/patch 层直接位于快照根；只有 *_prop 层按类别分子目录

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/05_derive_lulc.R", envir = .ing)
snap <- .ing$SNAPSHOTS[[1]]

cat(sprintf("输出根: %s\n快照: year=%s\n\n", OUT, snap$y))
t0 <- Sys.time()
r <- .ing$derive_snapshot(snap, c("prop", "shannon", "edge", "patch"))
cat(sprintf("\n[全部四段] %s : %d 层, %.0f 秒\n\n", r$status, r$n,
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

ref_path <- function(p) {
  rest <- sub("^glo_lulc_glu1km_2020_", "", p)
  if (grepl("^[a-z]+_prop", rest)) file.path(REF, sub("_.*$", "", rest), p)
  else file.path(REF, p)
}

checks <- list(
  list(f = "glo_lulc_glu1km_2020_urban_prop.tif",              cat = TRUE,  tag = "prop base urban"),
  list(f = "glo_lulc_glu1km_2020_cropland_prop_f1000.tif",     cat = FALSE, tag = "prop f1000"),
  list(f = "glo_lulc_glu1km_2020_cropland_prop_f20000.tif",    cat = FALSE, tag = "prop f20000"),
  list(f = "glo_lulc_glu1km_2020_shannon_f1000.tif",           cat = FALSE, tag = "shannon f1000"),
  list(f = "glo_lulc_glu1km_2020_shannon_f5000.tif",           cat = FALSE, tag = "shannon f5000"),
  list(f = "glo_lulc_glu1km_2020_shannon_f10000.tif",          cat = FALSE, tag = "shannon f10000"),
  list(f = "glo_lulc_glu1km_2020_shannon_f20000.tif",          cat = FALSE, tag = "shannon f20000"),
  list(f = "glo_lulc_glu1km_2020_edge.tif",                    cat = FALSE, tag = "edge base"),
  list(f = "glo_lulc_glu1km_2020_edge_f1000.tif",              cat = FALSE, tag = "edge f1000"),
  list(f = "glo_lulc_glu1km_2020_edge_f5000.tif",              cat = FALSE, tag = "edge f5000"),
  list(f = "glo_lulc_glu1km_2020_edge_f10000.tif",             cat = FALSE, tag = "edge f10000"),
  list(f = "glo_lulc_glu1km_2020_edge_f20000.tif",             cat = FALSE, tag = "edge f20000"),
  list(f = "glo_lulc_glu1km_2020_patchdensity-all_f5000.tif",  cat = FALSE, tag = "patchdensity-all f5000"),
  list(f = "glo_lulc_glu1km_2020_patchsize-all_f5000.tif",     cat = FALSE, tag = "patchsize-all f5000"),
  list(f = "glo_lulc_glu1km_2020_patchdensity-all_f20000.tif", cat = FALSE, tag = "patchdensity-all f20000"),
  list(f = "glo_lulc_glu1km_2020_patchsize-all_f20000.tif",    cat = FALSE, tag = "patchsize-all f20000"),
  list(f = "glo_lulc_glu1km_2020_patchdensity-forest_f5000.tif", cat = FALSE, tag = "patchdensity-forest f5000"),
  list(f = "glo_lulc_glu1km_2020_patchsize-forest_f5000.tif",    cat = FALSE, tag = "patchsize-forest f5000"),
  list(f = "glo_lulc_glu1km_2020_patchdensity-forest_f20000.tif",cat = FALSE, tag = "patchdensity-forest f20000"),
  list(f = "glo_lulc_glu1km_2020_patchsize-forest_f20000.tif",   cat = FALSE, tag = "patchsize-forest f20000")
)
npass <- 0; ntot <- 0
for (c in checks) {
  got <- r$files[basename(r$files) == c$f]
  ref <- ref_path(c$f)
  if (!length(got) || !file.exists(ref)) {
    cat(sprintf("  %-26s %-46s 跳过(生成%d/参照%d)\n", c$tag, c$f,
                length(got), file.exists(ref))); next
  }
  ntot <- ntot + 1
  if (c$cat) {
    cm <- compare_categorical(read_clean(got[1]), read_clean(ref)); npass <- npass + cm$pass
    cat(sprintf("  %-26s %s | %s\n", c$tag, ifelse(cm$pass, "PASS", "FAIL"), fmt_cat(cm)))
  } else {
    cm <- compare_layers(read_clean(got[1]), read_clean(ref)); npass <- npass + cm$pass
    cat(sprintf("  %-26s %s | %s\n", c$tag, ifelse(cm$pass, "PASS", "FAIL"), fmt_cmp(cm)))
  }
}
cat(sprintf("\n=== %d / %d 通过 ===\n", npass, ntot))
