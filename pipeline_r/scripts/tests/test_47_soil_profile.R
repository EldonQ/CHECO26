# R/tests/test_47_soil_profile.R -- 土壤剖面加权验证（输入取正式树，输出写 scratch）
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
OUT <- "E:/CHECO26/N-SDM/scratch/r_topo_test"
Sys.setenv(CHECO_OUT_ROOT = OUT)
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/08_derive_topo_vege.R", envir = .ing)

cat("=== soil profile 抽样验证 ===\n")
npass <- 0; ntot <- 0
for (adir in c("clay", "ph", "socd", "sand", "an")) {
  dst <- file.path(OUT, sprintf("soil_%s_profile.tif", adir))
  t0 <- Sys.time()
  r <- .ing$soil_profile(adir, dst = dst, src_root = PATH_COV())
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (!identical(r$status, "ok")) { cat(sprintf("  %-6s %s : %s\n", adir, r$status, r$note)); next }
  ref <- file.path(PATH_COV(), sprintf("glo/soil/csdlv2/%s/glo_soil_csdlv2_%s_profile.tif", adir, adir))
  if (!file.exists(ref)) { cat(sprintf("  %-6s 参照不存在\n", adir)); next }
  cm <- compare_layers(read_clean(dst), read_clean(ref))
  ntot <- ntot + 1; npass <- npass + cm$pass
  cat(sprintf("  %-6s %s (%.1f 秒) | %s\n", adir, ifelse(cm$pass, "PASS", "FAIL"), el, fmt_cmp(cm)))
}
cat(sprintf("\n=== %d / %d 通过 ===\n", npass, ntot))
