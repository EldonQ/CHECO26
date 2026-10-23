# R/tests/test_25_lulc_nopatch.R -- 验证 prop / shannon / edge 三段（不含 patch）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
OUT <- file.path(Sys.getenv("CHECO_ROOT", getwd()), "scratch/r_lulc_nopatch")
Sys.setenv(CHECO_OUT_ROOT = OUT)
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/tests/_helpers.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/05_derive_lulc.R"), envir = .ing)
snap <- .ing$SNAPSHOTS[[1]]
cat(sprintf("输出根: %s\n快照: year=%s\n\n", OUT, snap$y))

t0 <- Sys.time()
r <- .ing$derive_snapshot(snap, c("prop", "shannon", "edge"))
cat(sprintf("\n[prop+shannon+edge] %s : %d 层, %.0f 秒\n\n", r$status, r$n,
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

REF <- file.path(PATH_COV(), "glo/lulc/glu1km/2020")
ref_path <- function(p) {
  cls <- sub("^glo_lulc_glu1km_2020_", "", p)
  cls <- sub("_(prop|shannon|edge|patchdensity|patchsize).*$", "", cls)
  file.path(REF, cls, p)
}

checks <- list(
  list(f = "glo_lulc_glu1km_2020_urban_prop.tif",          cat = TRUE,  tag = "prop 基底(urban)"),
  list(f = "glo_lulc_glu1km_2020_forest_prop.tif",         cat = TRUE,  tag = "prop 基底(forest)"),
  list(f = "glo_lulc_glu1km_2020_cropland_prop_f1000.tif", cat = FALSE, tag = "prop f1000"),
  list(f = "glo_lulc_glu1km_2020_cropland_prop_f5000.tif", cat = FALSE, tag = "prop f5000"),
  list(f = "glo_lulc_glu1km_2020_cropland_prop_f10000.tif",cat = FALSE, tag = "prop f10000"),
  list(f = "glo_lulc_glu1km_2020_cropland_prop_f20000.tif",cat = FALSE, tag = "prop f20000"),
  list(f = "glo_lulc_glu1km_2020_shannon_f1000.tif",       cat = FALSE, tag = "shannon f1000"),
  list(f = "glo_lulc_glu1km_2020_shannon_f5000.tif",       cat = FALSE, tag = "shannon f5000"),
  list(f = "glo_lulc_glu1km_2020_shannon_f20000.tif",      cat = FALSE, tag = "shannon f20000"),
  list(f = "glo_lulc_glu1km_2020_edge.tif",                cat = FALSE, tag = "edge 基底"),
  list(f = "glo_lulc_glu1km_2020_edge_f1000.tif",          cat = FALSE, tag = "edge f1000"),
  list(f = "glo_lulc_glu1km_2020_edge_f5000.tif",          cat = FALSE, tag = "edge f5000"),
  list(f = "glo_lulc_glu1km_2020_edge_f20000.tif",         cat = FALSE, tag = "edge f20000")
)
npass <- 0; ntot <- 0
for (c in checks) {
  got <- r$files[basename(r$files) == c$f]
  ref <- ref_path(c$f)
  if (!length(got) || !file.exists(ref)) { cat(sprintf("  %-24s %-48s 跳过\n", c$tag, c$f)); next }
  ntot <- ntot + 1
  if (c$cat) {
    cm <- compare_categorical(read_clean(got[1]), read_clean(ref)); npass <- npass + cm$pass
    cat(sprintf("  %-24s %s | %s\n", c$tag, ifelse(cm$pass, "PASS", "FAIL"), fmt_cat(cm)))
  } else {
    cm <- compare_layers(read_clean(got[1]), read_clean(ref)); npass <- npass + cm$pass
    cat(sprintf("  %-24s %s | %s\n", c$tag, ifelse(cm$pass, "PASS", "FAIL"), fmt_cmp(cm)))
  }
}
cat(sprintf("\n=== %d / %d 通过 ===\n", npass, ntot))
