# R/tests/test_20_lulc_all.R -- 验证 GLULC 全部四段（prop / shannon / edge / patch）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
OUT <- file.path(Sys.getenv("CHECO_ROOT", getwd()), "scratch/r_lulc_test")
Sys.setenv(CHECO_OUT_ROOT = OUT)
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/tests/_helpers.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/05_derive_lulc.R"), envir = .ing)
snap <- .ing$SNAPSHOTS[[1]]

cat(sprintf("输出根: %s\n快照: year=%s ssp=%s\n\n", OUT, snap$y,
            ifelse(is.na(snap$ssp), "(hist)", snap$ssp)))

t0 <- Sys.time()
r <- .ing$derive_snapshot(snap, c("prop", "shannon", "edge", "patch"))
cat(sprintf("\n[全部] %s : %d 层, %.0f 秒\n\n", r$status, r$n,
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

REF <- file.path(PATH_COV(), "glo/lulc/glu1km/2020")
ref_path <- function(p) {
  cls <- sub("^glo_lulc_glu1km_2020_", "", p)
  cls <- sub("_(prop|shannon|edge|patchdensity|patchsize).*$", "", cls)
  file.path(REF, cls, p)
}

cat("=== 分段抽样比对 ===\n")
checks <- list(
  list(f = "glo_lulc_glu1km_2020_urban_prop.tif",            cat = TRUE,  tag = "prop 基底（分类）"),
  list(f = "glo_lulc_glu1km_2020_cropland_prop.tif",         cat = TRUE,  tag = "prop 基底（分类）"),
  list(f = "glo_lulc_glu1km_2020_cropland_prop_f1000.tif",   cat = FALSE, tag = "prop f1000"),
  list(f = "glo_lulc_glu1km_2020_cropland_prop_f5000.tif",   cat = FALSE, tag = "prop f5000"),
  list(f = "glo_lulc_glu1km_2020_cropland_prop_f20000.tif",  cat = FALSE, tag = "prop f20000"),
  list(f = "glo_lulc_glu1km_2020_shannon_f1000.tif",         cat = FALSE, tag = "shannon f1000"),
  list(f = "glo_lulc_glu1km_2020_shannon_f20000.tif",        cat = FALSE, tag = "shannon f20000"),
  list(f = "glo_lulc_glu1km_2020_edge.tif",                  cat = FALSE, tag = "edge 基底"),
  list(f = "glo_lulc_glu1km_2020_edge_f5000.tif",            cat = FALSE, tag = "edge f5000"),
  list(f = "glo_lulc_glu1km_2020_patchdensity-all_f5000.tif", cat = FALSE, tag = "patchdensity-all f5000"),
  list(f = "glo_lulc_glu1km_2020_patchsize-all_f20000.tif",  cat = FALSE, tag = "patchsize-all f20000"),
  list(f = "glo_lulc_glu1km_2020_patchdensity-forest_f5000.tif", cat = FALSE, tag = "patchdensity-forest f5000"),
  list(f = "glo_lulc_glu1km_2020_patchsize-forest_f20000.tif",   cat = FALSE, tag = "patchsize-forest f20000")
)
npass <- 0; ntot <- 0
for (c in checks) {
  got <- r$files[basename(r$files) == c$f]
  ref <- ref_path(c$f)
  if (!length(got) || !file.exists(ref)) {
    cat(sprintf("  %-34s %-58s 跳过\n", c$tag, c$f)); next
  }
  ntot <- ntot + 1
  if (c$cat) {
    cm <- compare_categorical(read_clean(got[1]), read_clean(ref))
    npass <- npass + cm$pass
    cat(sprintf("  %-34s %s\n      %s\n", c$tag, ifelse(cm$pass, "PASS", "FAIL"), fmt_cat(cm)))
  } else {
    cm <- compare_layers(read_clean(got[1]), read_clean(ref))
    npass <- npass + cm$pass
    cat(sprintf("  %-34s %s\n      %s\n", c$tag, ifelse(cm$pass, "PASS", "FAIL"), fmt_cmp(cm)))
  }
}
cat(sprintf("\n=== %d / %d 通过 ===\n", npass, ntot))
