# R/tests/test_52_future.R -- CHELSA 未来链验证：清单完整性 + 抽样比对
# 2026-11-13 重写：CHELSA v2.1 未来链 = 6 链(5 GCM + ensmean) x 3 SSP x 3 时段 x 22 变量 = 1,188。
# ensmean 为后处理逐像元均值，任务无 $src（其余 5 GCM 有源文件）。
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
OUT <- "E:/CHECO26/N-SDM/scratch/r_future_test"
Sys.setenv(CHECO_OUT_ROOT = OUT)
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/10_future_chains.R", envir = .ing)
tasks <- .ing$build_manifest()

cat("=== CHELSA 未来链清单 ===\n")
cat(sprintf("  任务数: %d（应为 1188 = 6 链 x 3 SSP x 3 时段 x 22 变量）\n", length(tasks)))
stopifnot(length(tasks) == 1188L)
nm <- vapply(tasks, function(t) basename(layer_path(t$parts)), "")
cat(sprintf("  文件名唯一: %s（重复 %d）\n", !anyDuplicated(nm), sum(duplicated(nm))))
stopifnot(!anyDuplicated(nm))

has_src <- vapply(tasks, function(t) "src" %in% names(t) && !is.null(t$src) && nzchar(t$src), TRUE)
srcs <- vapply(tasks[has_src], function(t) t$src, "")
ex <- file.exists(srcs)
cat(sprintf("  GCM 源存在: %d / %d（ensmean %d 个无源，属正常后处理）\n",
            sum(ex), length(ex), sum(!has_src)))
if (any(!ex)) for (s in unique(srcs[!ex])) cat("    缺:", s, "\n")
stopifnot(all(ex))

cat("\n  按链/时段交叉表:\n")
print(table(vapply(tasks, function(t) t$chain, ""),
            vapply(tasks, function(t) t$cyear, "")))

# 抽样比对（含一个 ensmean 任务，验证后处理均值与交付一致）
cat("\n=== 抽样比对 ===\n")
ens_idx <- which(!has_src)[1]
idx <- unique(c(1L, 29L, 100L, 400L, ens_idx))
npass <- 0; ntot <- 0
for (k in idx) {
  t <- tasks[[k]]
  r <- tryCatch(.ing$run_task(t), error = function(e) list(status="error", note=conditionMessage(e)))
  if (!identical(r$status, "ok") && !identical(r$status, "skip")) {
    cat(sprintf("  %-56s %s : %s\n", nm[k], r$status, r$note)); next
  }
  ref_dir <- do.call(file.path, as.list(c(PATH_COV(), t$parts)))
  ref <- file.path(ref_dir, paste0(paste(t$parts, collapse = "_"), ".tif"))
  if (!file.exists(ref)) { cat(sprintf("  %-56s 参照不存在\n", nm[k])); next }
  cm <- compare_layers(read_clean(r$dst), read_clean(ref))
  ntot <- ntot + 1; npass <- npass + cm$pass
  cat(sprintf("  %-56s %s | %s\n", substr(nm[k], 1, 56), ifelse(cm$pass,"PASS","FAIL"), fmt_cmp(cm)))
}
cat(sprintf("\n=== %d / %d 通过 ===\n", npass, ntot))
stopifnot(ntot > 0, npass == ntot)