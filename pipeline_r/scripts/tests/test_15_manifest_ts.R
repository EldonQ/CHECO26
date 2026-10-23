# R/tests/test_15_manifest_ts.R -- 校验 04_ingest_timeseries.R 的任务清单
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/04_ingest_timeseries.R"), envir = .ing)
tasks <- .ing$build_manifest()

cat(sprintf("=== 时序清单 ===\n总任务数: %d\n\n", length(tasks)))

kind <- vapply(tasks, function(t) t$kind, "")
cat("按 kind:\n"); print(table(kind))

grp <- vapply(tasks, function(t) paste(t$parts[2], t$parts[3], sep = "/"), "")
cat("\n按 theme/dataset（含焦点）:\n"); print(table(grp))

base <- Filter(function(t) t$kind != "focal", tasks)
cat(sprintf("\n基底任务: %d\n", length(base)))
cat("  按 dataset:\n")
print(table(vapply(base, function(t) paste(t$parts[2], t$parts[3], sep = "/"), "")))

cat("\n=== 目标文件名唯一性 ===\n")
nm <- vapply(tasks, function(t) basename(layer_path(t$parts, t$suffix)), "")
cat(sprintf("  唯一: %s ; 重复 %d\n", !anyDuplicated(nm), sum(duplicated(nm))))
if (anyDuplicated(nm)) print(head(nm[duplicated(nm)], 10))

cat("\n=== 源文件存在性（仅 warp/smod）===\n")
ws <- Filter(function(t) t$kind %in% c("warp", "smod"), tasks)
ex <- file.exists(vapply(ws, function(t) t$src, ""))
cat(sprintf("  存在 %d / %d\n", sum(ex), length(ex)))
if (any(!ex)) for (s in unique(vapply(ws[!ex], function(t) t$src, ""))) cat("    缺:", s, "\n")

cat("\n=== 焦点基底层是否已存在于磁盘 ===\n")
fb <- unique(vapply(Filter(function(t) t$kind == "focal", tasks),
                    function(t) layer_path(t$base, ""), ""))
cat(sprintf("  焦点基底共 %d 个；磁盘已存在 %d 个\n", length(fb), sum(file.exists(fb))))
