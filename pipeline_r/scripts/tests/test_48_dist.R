# R/tests/test_48_dist.R -- 距离面验证（逐层与 Python 原层比对）
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
OUT <- "E:/CHECO26/N-SDM/scratch/r_dist_test"
Sys.setenv(CHECO_OUT_ROOT = OUT)
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/09_derive_dist.R", envir = .ing)

cat("=== 距离面验证 ===\n")
npass <- 0; ntot <- 0
for (tag in .ing$TASKS) {
  t0 <- Sys.time()
  r <- tryCatch(.ing$run_task(tag), error = function(e) list(status = "error", note = conditionMessage(e)))
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (!identical(r$status, "ok")) {
    cat(sprintf("  %-16s %s : %s\n", tag, r$status, r$note)); next
  }
  ref <- file.path(PATH_COV(), switch(tag,
    grip4_road      = "glo/dist/grip4/road/glo_dist_grip4_road.tif",
    grip4_majorroad = "glo/dist/grip4/majorroad/glo_dist_grip4_majorroad.tif",
    osm_trail       = "glo/dist/osm/trail/glo_dist_osm_trail.tif",
    smod_urban      = "glo/dist/smod/urban/glo_dist_smod_urban.tif",
    gsw_water       = "glo/dist/gsw/water/glo_dist_gsw_water.tif"))
  if (!file.exists(ref)) { cat(sprintf("  %-16s 参照不存在\n", tag)); next }
  cm <- compare_layers(read_clean(r$dst), read_clean(ref))
  ntot <- ntot + 1; npass <- npass + cm$pass
  cat(sprintf("  %-16s %s (%.0f 秒, nfeat=%s) | %s\n", tag, ifelse(cm$pass, "PASS", "FAIL"),
              el, format(r$nfeat, big.mark = ","), fmt_cmp(cm)))
}
cat(sprintf("\n=== %d / %d 通过 ===\n", npass, ntot))
