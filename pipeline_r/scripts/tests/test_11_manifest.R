# R/tests/test_11_manifest.R -- 校验 03_ingest_static.R 的任务清单与源文件
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

# 在独立环境里 source，避免其内部变量污染本测试；sys.nframe()!=0 故 main() 不执行
.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/03_ingest_static.R"), envir = .ing)
tasks <- .ing$build_manifest()

cat(sprintf("=== 任务清单 ===\n总任务数: %d   （Python 版为 241）\n\n", length(tasks)))

theme <- vapply(tasks, function(t) t$parts[2], "")
ds    <- vapply(tasks, function(t) t$parts[3], "")
cat("按 theme 统计:\n"); print(table(theme))
cat("\n按 theme/dataset 统计:\n"); print(table(paste(theme, ds, sep = "/")))

cat("\n按 rule 统计:\n")
print(table(vapply(tasks, function(t) t$rule, "")))
cat("\n按解析后的 method 统计:\n")
print(table(vapply(tasks, function(t) CFG()$resampling[[t$rule]], "")))

cat("\n按 scale 统计:\n")
sc <- vapply(tasks, function(t) if (is.null(t$scale)) "none" else format(t$scale), "")
print(table(sc))

cat("\n按 src_nodata 统计:\n")
ndv <- vapply(tasks, function(t) if (is.null(t$src_nodata)) "NULL(源自带)" else format(t$src_nodata), "")
print(table(ndv))

cat("\n=== 目标文件名唯一性 ===\n")
nm <- vapply(tasks, function(t) basename(layer_path(t$parts)), "")
cat(sprintf("  唯一: %s ; 重复数: %d\n", !anyDuplicated(nm), sum(duplicated(nm))))

cat("\n=== 源文件存在性 ===\n")
srcs <- vapply(tasks, function(t) t$src, "")
ex <- file.exists(srcs)
cat(sprintf("  存在 %d / %d\n", sum(ex), length(ex)))
if (any(!ex)) {
  cat("  缺失的源:\n")
  for (s in unique(srcs[!ex])) cat("    ", s, "\n")
}

cat("\n=== 哨兵任务 ===\n")
sent <- Filter(function(t) !is.null(t$sentinel), tasks)
if (length(sent)) {
  for (t in sent) cat(sprintf("  %-52s sentinel=%.0f\n", basename(layer_path(t$parts)), t$sentinel))
} else cat("  无\n")
