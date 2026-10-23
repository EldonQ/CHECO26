# R/tests/test_51_osm.R -- 单独验证 osm_trail 距离面
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
Sys.setenv(CHECO_OUT_ROOT = "E:/CHECO26/N-SDM/scratch/r_dist_osm")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/09_derive_dist.R", envir = .ing)

cat("=== osm_trail 单独验证 ===\n")
t0 <- Sys.time()
r <- tryCatch(.ing$run_task("osm_trail"), error = function(e) list(status="error", note=conditionMessage(e)))
cat(sprintf("  状态: %s %s  用时 %.0f 秒\n", r$status,
            if (is.null(r$note)) "" else paste0("[", r$note, "]"),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
if (identical(r$status, "ok")) {
  cat(sprintf("  nfeat=%s 值域 [%.1f, %.1f]\n", format(r$nfeat, big.mark=","), r$vmin, r$vmax))
  ref <- file.path(PATH_COV(), "glo/dist/osm/trail/glo_dist_osm_trail.tif")
  cm <- compare_layers(read_clean(r$dst), read_clean(ref))
  cat(sprintf("  比对: %s | %s\n", ifelse(cm$pass,"PASS","FAIL"), fmt_cmp(cm)))
}
