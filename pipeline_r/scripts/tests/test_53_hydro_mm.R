# R/tests/test_53_hydro_mm.R -- hydro min/max 增补层验证
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
OUT <- "E:/CHECO26/N-SDM/scratch/r_hydromm_test"
Sys.setenv(CHECO_OUT_ROOT = OUT)
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/02b_hydro_stats.R", envir = .ing)
tasks <- .ing$build_manifest()
cat(sprintf("=== 清单: %d 任务（应为 18）===\n", length(tasks)))
for (t in tasks) cat(sprintf("  %-24s %-3s sentinel=%s scale=%s\n",
                             t$var, t$stat,
                             if (is.null(t$sentinel)) "none" else format(t$sentinel),
                             if (is.null(t$scale)) "none" else format(t$scale)))

cat("\n=== 抽样验证 ===\n")
pick <- list(
  list(var="channel_elv_up_cel", stat="max"),   # 哨兵关键层
  list(var="channel_elv_up_cel", stat="min"),
  list(var="spi",                stat="max"),
  list(var="stream_dist_proximity", stat="max")
)
npass <- 0; ntot <- 0
for (p in pick) {
  k <- which(vapply(tasks, function(t) t$var == p$var && t$stat == p$stat, TRUE))
  if (!length(k)) { cat(sprintf("  %-24s %-3s 不在清单\n", p$var, p$stat)); next }
  t <- tasks[[k]]
  r <- tryCatch(.ing$run_task(t), error = function(e) list(status="error", note=conditionMessage(e)))
  if (!identical(r$status, "ok") && !identical(r$status, "skip")) {
    cat(sprintf("  %-24s %-3s %s : %s\n", p$var, p$stat, r$status, r$note)); next
  }
  ref <- file.path(PATH_COV(), do.call(file.path, as.list(t$parts)),
                   paste0(paste(t$parts, collapse="_"), t$suffix, ".tif"))
  if (!file.exists(ref)) { cat(sprintf("  %-24s %-3s 参照不存在\n", p$var, p$stat)); next }
  cm <- compare_layers(read_clean(r$dst), read_clean(ref))
  ntot <- ntot + 1; npass <- npass + cm$pass
  cat(sprintf("  %-24s %-3s %s | %s\n", p$var, p$stat, ifelse(cm$pass,"PASS","FAIL"), fmt_cmp(cm)))
}
cat(sprintf("\n=== %d / %d 通过 ===\n", npass, ntot))
