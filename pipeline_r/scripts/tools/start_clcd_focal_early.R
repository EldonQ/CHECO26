# R/tools/start_clcd_focal_early.R
# 在基底**尚未全部完成**时，提前用空闲 worker 跑已就绪年份的焦点层
#
# 为什么需要它：
#   26 年分给 6 个分片，其中 c1/c2 各 5 年、c3–c6 各 4 年。
#   所以 c3–c6 会先收工（约 05:20），而基底要到 08:40 才全部完成。
#   那 3 小时有 4 个核闲着，可以先把已完成年份的焦点层做掉。
#
# 为什么不能更早启动：
#   提交量（commit）在 6 个基底 worker 运行时已达 182/204 GB（89%）。
#   再加 4 个焦点 worker（各约 6 GB 提交）会突破上限，触发 bad_alloc。
#   必须等 c3–c6 退出、提交量回落之后再启动。
#
# 关键设计：**不修改正在运行的主脚本**
#   主脚本 06_derive_lulc_clcd.R 被运行中的 c1/c2 锁定（Windows 文件锁），
#   所以复制一份、在副本上打缺陷 44 的补丁、用副本跑焦点。
#
# 用法：
#   Rscript R/tools/start_clcd_focal_early.R check    # 只检查条件是否满足
#   Rscript R/tools/start_clcd_focal_early.R start <nshard>
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

CLCD_DIR <- function() file.path(PATH_COV(), "glo", "lulc", "clcd")
RSCRIPT  <- "D:/R/R-4.4.3/bin/Rscript.exe"
COPY     <- file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd_focal.R")

#' 完整年份数（9 层齐）
n_complete_years <- function() {
  d <- list.dirs(CLCD_DIR(), recursive = FALSE, full.names = TRUE)
  sum(vapply(d, function(x) {
    length(list.files(x, pattern = "_prop\\.tif$", recursive = TRUE)) >= 9
  }, TRUE))
}

#' 已有焦点层数
n_focal <- function() {
  length(list.files(CLCD_DIR(), pattern = "_prop_f[0-9]+\\.tif$", recursive = TRUE))
}

#' 仍在跑的 clcd 基底 worker 数（CPU > 10 s 的才算，启动器包装层 CPU 为 0）
n_base_workers <- function() {
  ps <- suppressWarnings(system2("powershell",
    c("-NoProfile", "-Command",
      "\"@(Get-CimInstance Win32_Process -Filter \\\"Name='Rscript.exe'\\\" | Where-Object { $_.CommandLine -like '*06_derive_lulc_clcd*' -and $_.CommandLine -notlike '*focal*' -and (Get-Process -Id $_.ProcessId -EA SilentlyContinue).CPU -gt 10 }).Count\""),
    stdout = TRUE, stderr = FALSE))
  v <- suppressWarnings(as.integer(ps[1])); if (is.na(v)) 0L else v
}

#' 提交量占用率（%）
commit_pct <- function() {
  ps <- suppressWarnings(system2("powershell",
    c("-NoProfile", "-Command",
      "\"$o=Get-CimInstance Win32_OperatingSystem; [math]::Round(100*(($o.TotalVirtualMemorySize-$o.FreeVirtualMemory)/$o.TotalVirtualMemorySize)) \""),
    stdout = TRUE, stderr = FALSE))
  v <- suppressWarnings(as.numeric(ps[1])); if (is.na(v)) 100 else v
}

#' 真正在跑的 focal worker 数（CPU > 10 s，排除启动器包装层）
n_focal_workers <- function() {
  ps <- suppressWarnings(system2("powershell",
    c("-NoProfile", "-Command",
      "\"@(Get-CimInstance Win32_Process -Filter \\\"Name='Rscript.exe'\\\" | Where-Object { $_.CommandLine -like '*_focal*' -and (Get-Process -Id $_.ProcessId -EA SilentlyContinue).CPU -gt 10 }).Count\""),
    stdout = TRUE, stderr = FALSE))
  v <- suppressWarnings(as.integer(ps[1])); if (is.na(v)) 0L else v
}

main <- function(mode = c("check", "start"), nshard = 4L) {
  mode <- match.arg(mode)
  ny <- n_complete_years(); nf <- n_focal(); nw <- n_base_workers()
  cp <- commit_pct()

  cat("=== clcd 焦点提前启动条件 ===\n")
  cat(sprintf("  完整年份:       %d / 26\n", ny))
  cat(sprintf("  已有焦点层:     %d / 936\n", nf))
  cat(sprintf("  运行中的基分片: %d\n", nw))
  cat(sprintf("  提交量占用:     %.0f%%\n", cp))

  # 条件：至少有一个分片收工（nw < 6）且提交量 < 80%
  ok <- nw > 0L && nw < 6L && cp < 80
  cat(sprintf("  判定: %s\n",
              if (ok) "可以启动" else
                if (nw == 0L) "基底已全部完成——直接跑正式焦点，无需提前启动"
                else if (nw >= 6L) "**不可**：6 个基分片仍在跑，提交量会超限"
                else "**不可**：提交量仍高于 80%"))

  if (mode == "check" || !ok) return(invisible(ok))

  # ---- 1) 复制主脚本并打补丁 ----
  src <- file.path(CHECO_ROOT, "R", "06_derive_lulc_clcd.R")
  if (!file.exists(COPY)) {
    file.copy(src, COPY, overwrite = FALSE)
    cat(sprintf("\n  已复制主脚本 -> %s\n", basename(COPY)))
  }
  Sys.setenv(CHECO_PATCH_TARGET = COPY)
  code <- system2(RSCRIPT, c("--vanilla",
                 file.path(CHECO_ROOT, "R/tools/patch_clcd_focal_skip.R"), "apply"),
                  stdout = "", stderr = "")
  cat(sprintf("  补丁退出码: %d\n", code))
  if (code != 0L) { cat("  补丁失败，中止\n"); return(invisible(FALSE)) }

  # ---- 2) 启焦点分片（tempdir 必须在 D:）----
  wt <- "D:/checo_tmp"
  if (!dir.exists(wt)) dir.create(wt, recursive = TRUE)
  Sys.setenv(TEMP = wt, TMP = wt, TMPDIR = wt)
  # 2026-10-21 修：原来用 system2("powershell", ...) 调 Start-Process，
  # **只有第 1 个分片真正启动，后 3 个静默失败**（e_f2/e_f3/e_f4 日志根本没创建）。
  # 原因：把整条 Start-Process 命令塞进 system2 的参数里，引号层层转义后失效。
  # 改为把启动命令写成 .ps1 文件再执行，避免转义问题；并逐个验证进程真的起来了。
  ps1 <- file.path(PATH_SCRATCH(), "launch_focal.ps1")
  lines <- c(sprintf("$env:TEMP='%s'; $env:TMP='%s'; $env:TMPDIR='%s'", wt, wt, wt),
             vapply(seq_len(nshard), function(i) sprintf(
               "Start-Process '%s' -ArgumentList @('--vanilla','%s','focal','%d','%d') -RedirectStandardOutput '%s/logs/e_f%d.log' -RedirectStandardError '%s/logs/e_f%d.err' -WindowStyle Hidden",
               RSCRIPT, COPY, i, nshard, CHECO_ROOT, i, CHECO_ROOT, i), ""))
  writeLines(lines, ps1, useBytes = TRUE)
  system2("powershell", c("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1))
  Sys.sleep(30)

  # 验证：数一下真正在跑的 focal worker（CPU > 10 s，排除启动器包装层）
  n_ok <- n_focal_workers()
  cat(sprintf("  启动后检测到 %d / %d 个焦点 worker 在跑\n", n_ok, nshard))
  if (n_ok < nshard) {
    cat("  \u26a0 不足！请手动补齐：\n")
    for (i in seq_len(nshard))
      cat(sprintf("  Start-Process '%s' -ArgumentList @('--vanilla','%s','focal','%d','%d') -RedirectStandardOutput 'logs/e_f%d.log' -RedirectStandardError 'logs/e_f%d.err' -WindowStyle Hidden\n",
                  RSCRIPT, COPY, i, nshard, i, i))
  }
  cat(sprintf("\n  注意：未完成年份会返回 pending，属正常。\n"))
  cat(sprintf("  基底全部完成后需再跑一次正式焦点补齐。\n"))
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) a[1] else "check",
       if (length(a) >= 2) as.integer(a[2]) else 4L)
}
