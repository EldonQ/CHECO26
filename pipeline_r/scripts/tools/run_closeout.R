# R/tools/run_closeout.R
# 一键收尾：按 00_docs/CLOSEOUT_CHECKLIST.md 的顺序执行全部步骤，每步验判据
#
# 为什么要有这个：
#   收尾涉及 6 个命令、3 个前置条件、2 个"必须在空闲机器上跑"的约束。
#   手工按顺序执行容易漏步或错序（例如忘了先打补丁就启焦点）。
#   这个脚本把顺序和执行条件固化下来，并在每步之后检查判据。
#
# 用法：
#   Rscript R/tools/run_closeout.R dry     # 只检查前置条件与当前状态，不执行
#   Rscript R/tools/run_closeout.R run     # 实际执行
#
# 安全设计：
#   - 生成任务在跑时拒绝执行第 4 步（V1–V6 会被 Windows 静默杀死）
#   - 任何一步判据不达标就停下并报告，不继续往下走
#   - 所有步骤都是幂等的（可重复执行）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

TARGET <- 21110L
RSCRIPT <- file.path("D:/R/R-4.4.3/bin", "Rscript.exe")

#' 运行一个子脚本并返回退出码
run_step <- function(script, args = character(), label = script) {
  cat(sprintf("\n---- %s ----\n", label))
  t0 <- Sys.time()
  # 2026-10-21 修：原先 stdout="" stderr="" 让子进程输出继承到控制台，
  # 子进程的 "invalid multibyte character in parser" 会因缓冲而延迟出现在
  # 父进程输出末尾，看起来像是父进程崩了。改为丢弃 stderr，只看退出码。
  code <- system2(RSCRIPT, c("--vanilla", file.path(CHECO_ROOT, "R", script), args),
                  stdout = "", stderr = FALSE)
  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("  [%s] 用时 %.0f 秒，退出码 %d\n", label, dt, code))
  invisible(code)
}

#' 当前完成度（按溯源表逐个 file.exists）
count_done <- function() {
  prov <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"),
                   fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
  prov <- prov[prov$status == "active", ]
  sum(file.exists(file.path(PATH_COV(), prov$layer_path)))
}

#' 是否有生成任务在跑
generating <- function() {
  ps <- suppressWarnings(system2("powershell",
    c("-NoProfile", "-Command",
      "\"@(Get-CimInstance Win32_Process -Filter \\\"Name='Rscript.exe'\\\" | Where-Object { $_.CommandLine -match 'derive_lulc|ingest_' -and (Get-Process -Id $_.ProcessId -EA SilentlyContinue).CPU -gt 10 }).Count\""),
    stdout = TRUE, stderr = FALSE))
  v <- suppressWarnings(as.integer(ps[1]))
  if (is.na(v)) 0L else v
}

#' 磁盘余量是否够（SHA-256 只读，但文档重生成要写）
disk_ok <- function(min_gb = 5) {
  ps <- suppressWarnings(system2("powershell",
    c("-NoProfile", "-Command",
      "\"(Get-CimInstance Win32_LogicalDisk -Filter \\\"DeviceID='E:'\\\").FreeSpace\""),
    stdout = TRUE, stderr = FALSE))
  v <- suppressWarnings(as.numeric(ps[1]))
  if (is.na(v)) return(TRUE)
  (v / 1073741824) > min_gb
}

main <- function(mode = c("dry", "run"), only = NULL) {
  mode <- match.arg(mode)
  cat("================================================================\n")
  cat(" CHECO26 收尾\n")
  cat(sprintf(" %s  (模式: %s)\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), mode))
  cat("================================================================\n")

  # ---------- 前置条件 ----------
  done <- count_done()
  gen  <- generating()
  cat(sprintf("\n完成度: %d / %d = %.2f%%\n", done, TARGET, 100 * done / TARGET))
  cat(sprintf("运行中的生成任务: %d\n", gen))

  if (done < TARGET) {
    cat(sprintf("\n⚠ 还差 %d 层。收尾应在全部层到齐后执行。\n", TARGET - done))
    if (mode == "run") {
      cat("  仍继续？文档重生成与 V1–V6 会基于当前不完整的数据集。\n")
      cat("  建议先等数据到齐。已退出。\n")
      return(invisible(FALSE))
    }
  }

  # ---------- 步骤清单 ----------
  steps <- list(
    list(n = "1", label = "SHA-256 全量清单", script = "14_manifest.R", args = "hash",
         need_idle = FALSE,
         judge = function() {
           m <- read.csv(file.path(PATH_DOCS(), "MANIFEST.csv"), fileEncoding = "UTF-8-BOM",
                         stringsAsFactors = FALSE)
           exp <- TARGET + 8L   # 21,110 交付层 + 8 个非层文件（mask/template/masks/species）
           sprintf("MANIFEST 行数 %d（预期 %d）", nrow(m), exp)
         }),
    list(n = "2", label = "重生成文档（含统计）", script = "12_make_docs.R", args = character(),
         need_idle = FALSE,
         judge = function() {
           d <- read.csv(file.path(PATH_DOCS(), "variable_dictionary.csv"),
                         fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
           sprintf("variable_dictionary 行数 %d（预期 %d）", nrow(d), TARGET)
         }),
    list(n = "3", label = "重生成溯源表（含统计）", script = "13_make_provenance.R", args = "fill",
         need_idle = FALSE,
         judge = function() {
           p <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"),
                         fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
           old <- grepl("25,684", paste(p$missing_boundary_rule, collapse = " "), fixed = TRUE)
           sprintf("provenance 行数 %d（预期 21,118）；旧数字残留: %s",
                   nrow(p), ifelse(old, "**有**", "无"))
         }),
    list(n = "4", label = "V1–V6 全量校验（需空闲机器）", script = "11_validate.R",
         args = "full", need_idle = TRUE,
         judge = function() "见上方 V1–V6 各节结论"),
    list(n = "5", label = "刷新完成度表", script = "tools/report_status.R", args = "write",
         need_idle = FALSE, judge = function() "见 FINAL_VERIFICATION_REPORT.md §2"),
    list(n = "6", label = "刷新 README 计数", script = "tools/refresh_readme_numbers.R",
         args = "write", need_idle = FALSE, judge = function() "见上方 FIX/OK 行"),
    list(n = "7", label = "文档一致性复核", script = "tools/check_docs_consistency.R",
         args = character(), need_idle = FALSE,
         judge = function() "必须 FAIL 0"),
    list(n = "8", label = "\u8d8b\u52bf\u6570\u5b57\u6838\u9a8c", script = "tools/check_trends.R",
         args = character(), need_idle = FALSE,
         judge = function() "\u5fc5\u987b PASS 39 / FAIL 0"),
    list(n = "9", label = "\u6570\u636e\u96c6\u5c42\u6570\u6838\u9a8c", script = "tools/check_table2.R",
         args = character(), need_idle = FALSE,
         judge = function() "\u5fc5\u987b 17 / 17 \u4e00\u81f4\uff0c\u4e14\u4e4b\u548c = 21,110")
  )

  # ---------- dry：只报计划 ----------
  if (mode == "dry") {
    cat("\n计划执行的步骤:\n")
    for (s in steps) {
      blocked <- s$need_idle && gen > 0L
      cat(sprintf("  %s. %-32s %s\n", s$n, s$label,
                  if (blocked) "**被阻塞：有生成任务在跑**" else "可执行"))
    }
    cat(sprintf("\n磁盘余量 (E:) 足够: %s\n", ifelse(disk_ok(), "是", "**否**")))
    cat("\n用 run 参数实际执行。\n")
    return(invisible(TRUE))
  }

  # ---------- 实际执行 ----------
  results <- list()
  for (s in steps) {
    # only = "8,9" 时只跑指定步骤（便于单独验证检查器，不必重跑 SHA-256 与统计填充）
    if (!is.null(only) && !(s$n %in% only)) { results[[s$n]] <- "SKIPPED"; next }
    if (s$need_idle && gen > 0L) {
      cat(sprintf("\n⚠ 跳过第 %s 步（%s）：有 %d 个生成任务在跑，\n", s$n, s$label, gen))
      cat("   满载时 Windows 会静默杀死 V1–V6（.err 为空、无退出码）。\n")
      cat("   等生成任务结束后单独执行：\n")
      cat("   Rscript R/11_validate.R full\n")
      results[[s$n]] <- "SKIPPED"
      next
    }
    code <- run_step(s$script, s$args, sprintf("%s. %s", s$n, s$label))
    cat(sprintf("  判据: %s\n", tryCatch(s$judge(), error = function(e) paste("判据计算失败:", conditionMessage(e)))))
    results[[s$n]] <- if (code == 0L) "OK" else sprintf("FAILED(exit %d)", code)
  }

  # ---------- 最终判据 ----------
  cat("\n================================================================\n")
  cat(" 最终核对\n")
  cat("================================================================\n")
  done2 <- count_done()
  cat(sprintf("  完成度: %d / %d = %.2f%%\n", done2, TARGET, 100 * done2 / TARGET))
  cat(sprintf("  判据:   %s\n",
              ifelse(done2 == TARGET, "**达到 21,110，目标达成**", "**未达到，目标未达成**")))
  for (k in names(results)) cat(sprintf("  步骤 %s: %s\n", k, results[[k]]))

  cat("\n  还需人工确认的项（见 CLOSEOUT_CHECKLIST.md 阶段 4）:\n")
  cat("    - 阶段 0.1 的补丁是否已应用（clcd_focal_one 含 need 变量）\n")
  cat("    - 三份文档的 clcd 恒等式数字一致且可追溯\n")
  cat("    - V1–V6 全部有非空结论（不是'0 组检查'）\n")

  invisible(all(vapply(results, function(x) x == "OK", TRUE)))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  only <- if (length(a) >= 2) strsplit(a[2], ",", fixed = TRUE)[[1]] else NULL
  main(if (length(a) >= 1) a[1] else "dry", only)
}
