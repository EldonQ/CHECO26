# R/tests/test_17_lulc.R -- 分段验证 05_derive_lulc.R（历史 2020 快照，输出重定向到 scratch）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
OUT <- file.path(Sys.getenv("CHECO_ROOT", getwd()), "scratch/r_lulc_test")
Sys.setenv(CHECO_OUT_ROOT = OUT)
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/tests/_helpers.R"), encoding = "UTF-8")

cat(sprintf("输出根（重定向）: %s\n", Sys.getenv("CHECO_OUT_ROOT")))
cat(sprintf("参照根（只读）  : %s\n\n", PATH_COV()))

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/05_derive_lulc.R"), envir = .ing)

snap <- .ing$SNAPSHOTS[[1]]
cat(sprintf("快照: year=%s ssp=%s src=%s\n\n", snap$y,
            ifelse(is.na(snap$ssp), "(hist)", snap$ssp), snap$f))

run_part <- function(part) {
  t0 <- Sys.time()
  r <- .ing$derive_snapshot(snap, which_parts = part)
  cat(sprintf("[%s] %s : %d 层, %.0f 秒\n", part, r$status, r$n %||% 0,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  r
}
`%||%` <- function(a, b) if (is.null(a)) b else a

r_prop <- run_part("prop")

cat("\n=== prop 抽样比对 ===\n")
probe <- c("glo_lulc_glu1km_2020_urban_prop.tif",
           "glo_lulc_glu1km_2020_cropland_prop_f5000.tif",
           "glo_lulc_glu1km_2020_water_prop_f20000.tif",
           "glo_lulc_glu1km_2020_forest_prop_f10000.tif")
for (p in probe) {
  got <- r_prop$files[basename(r_prop$files) == p]
  cls <- sub("^glo_lulc_glu1km_2020_", "", p); cls <- sub("_prop.*$", "", cls)
  ref <- file.path(PATH_COV(), "glo/lulc/glu1km/2020", cls, p)
  if (!length(got) || !file.exists(ref)) { cat(sprintf("  %-50s 跳过\n", p)); next }
  cmp <- compare_layers(read_clean(got[1]), read_clean(ref))
  cat(sprintf("  %-50s %s\n      %s\n", p, ifelse(cmp$pass, "PASS", "FAIL"), fmt_cmp(cmp)))
}
