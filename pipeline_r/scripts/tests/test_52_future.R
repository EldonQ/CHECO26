# R/tests/test_52_future.R -- 未来链验证：清单完整性 + 抽样比对
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
OUT <- file.path(Sys.getenv("CHECO_ROOT", getwd()), "scratch/r_future_test")
Sys.setenv(CHECO_OUT_ROOT = OUT)
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/tests/_helpers.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/10_future_chains.R"), envir = .ing)
tasks <- .ing$build_manifest()

cat("=== 未来链清单 ===\n")
cat(sprintf("  任务数: %d（应为 504）\n", length(tasks)))
nm <- vapply(tasks, function(t) basename(layer_path(t$parts)), "")
cat(sprintf("  文件名唯一: %s（重复 %d）\n", !anyDuplicated(nm), sum(duplicated(nm))))
srcs <- vapply(tasks, function(t) t$src, "")
ex <- file.exists(srcs)
cat(sprintf("  源存在: %d / %d\n", sum(ex), length(ex)))
if (any(!ex)) for (s in unique(srcs[!ex])) cat("    缺:", s, "\n")

cat("\n  按链/时段/SSP 交叉表:\n")
print(table(vapply(tasks, function(t) t$chain, ""),
            vapply(tasks, function(t) t$cyear, "")))

# 抽样 4 层比对
cat("\n=== 抽样比对 ===\n")
idx <- c(1L, 29L, 100L, 400L)
npass <- 0; ntot <- 0
for (k in idx) {
  t <- tasks[[k]]
  r <- tryCatch(.ing$run_task(t), error = function(e) list(status="error", note=conditionMessage(e)))
  if (!identical(r$status, "ok") && !identical(r$status, "skip")) {
    cat(sprintf("  %-56s %s : %s\n", nm[k], r$status, r$note)); next
  }
  # 参照 = 正式树中同一 parts 下的文件（layer_path 受 CHECO_OUT_ROOT 影响，故手工拼）
  ref_dir <- do.call(file.path, as.list(c(PATH_COV(), t$parts)))
  ref <- file.path(ref_dir, paste0(paste(t$parts, collapse = "_"), ".tif"))
  if (!file.exists(ref)) { cat(sprintf("  %-56s 参照不存在\n", nm[k])); next }
  cm <- compare_layers(read_clean(r$dst), read_clean(ref))
  ntot <- ntot + 1; npass <- npass + cm$pass
  cat(sprintf("  %-56s %s | %s\n", substr(nm[k], 1, 56), ifelse(cm$pass,"PASS","FAIL"), fmt_cmp(cm)))
}
cat(sprintf("\n=== %d / %d 通过 ===\n", npass, ntot))
