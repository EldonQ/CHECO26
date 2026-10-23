# R/tools/monitor.R
# 一次性状态快照：完成度 + 进程存活 + 内存 + 速率，追加到 logs/monitor.csv
#
# 用法： Rscript R/tools/monitor.R
# 设计为可反复运行；每次追加一行，便于事后画曲线 / 判断速率衰减。
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

TARGET <- 21110L
LOG <- file.path(CHECO_ROOT, "logs", "monitor.csv")

#' 按溯源表逐个 file.exists（权威计数，不受 .tmp.tif 污染）
count_progress <- function() {
  prov <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"),
                   fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
  prov <- prov[prov$status == "active", ]
  ex <- file.exists(file.path(PATH_COV(), prov$layer_path))
  ds <- sub("^glo/[^/]+/([^/]+)/.*$", "\\1", prov$layer_path)
  theme <- sub("^glo/([^/]+)/.*$", "\\1", prov$layer_path)
  key <- paste(theme, ds, sep = "/")
  agg <- tapply(ex, key, function(v) c(have = sum(v), total = length(v)))
  tab <- data.frame(ds = names(agg),
                    have = as.integer(sapply(agg, "[", "have")),
                    total = as.integer(sapply(agg, "[", "total")),
                    row.names = NULL, stringsAsFactors = FALSE)
  tab$miss <- tab$total - tab$have
  list(total_have = sum(tab$have), tab = tab[order(-tab$miss), ])
}

#' 统计运行中的任务（Rscript 是启动器，CommandLine 里带脚本名）
count_procs <- function() {
  ps <- suppressWarnings(system2("powershell",
    c("-NoProfile", "-Command",
      "\"Get-CimInstance Win32_Process -Filter \\\"Name='Rscript.exe'\\\" | ForEach-Object { $_.CommandLine }\""),
    stdout = TRUE, stderr = FALSE))
  if (!length(ps)) return(c(base = 0L, focal = 0L, clcd = 0L, other = 0L))
  c(
    base  = sum(grepl("07_derive_lulc_hlu1km.*?base",  ps)),
    focal = sum(grepl("07_derive_lulc_hlu1km.*?focal", ps)),
    clcd  = sum(grepl("06_derive_lulc_clcd",            ps)),
    other = sum(!grepl("derive_lulc", ps))
  )
}

mem_free_gb <- function() {
  os <- suppressWarnings(system2("powershell",
    c("-NoProfile", "-Command",
      "\"(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory\""),
    stdout = TRUE, stderr = FALSE))
  v <- suppressWarnings(as.numeric(os[1]))
  if (is.na(v)) return(NA_real_)
  v / 1048576
}

#' 各磁盘可用空间（GB）。2026-10-20 事故后新增：
#' clcd 的 terra::project 会向 tempdir() 溢写，每个 worker 约 18.5 GB。
#' 当时 R 的 tempdir 在 C:，6 个 worker 把 C: 的 900 GB 写到只剩 1.9 GB，
#' 报 "_tiffWriteProc: No space left on device"，而**进程并未退出**——
#' 旧监控只看进程存活与内存，完全没覆盖这种情况。
disk_free_gb <- function() {
  ps <- suppressWarnings(system2("powershell",
    c("-NoProfile", "-Command",
      "\"Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { '{0}={1}' -f $_.DeviceID, $_.FreeSpace }\""),
    stdout = TRUE, stderr = FALSE))
  ps <- ps[nzchar(ps)]
  if (!length(ps)) return(numeric(0))
  out <- numeric(0)
  for (x in ps) {
    kv <- strsplit(x, "=", fixed = TRUE)[[1]]
    if (length(kv) == 2L) {
      v <- suppressWarnings(as.numeric(kv[2]))
      if (is.finite(v)) { out[kv[1]] <- v / 1073741824 }
    }
  }
  out
}

#' 提交量（commit）与 tempdir 体积。2026-10-20 第二次事故排查后新增：
#' terra 为每个 worker 预留约 33 GB **虚拟地址空间**（实际驻留仅 6-10 GB）。
#' Windows 按提交量而非驻留量决定页面文件大小 —— 6 个 worker 让 C: 上的
#' pagefile.sys 从 7 GB 扩张到 99 GB，C: 可用从 170 GB 掉到 144 GB。
#' 只看"物理内存空闲"会完全漏掉这件事，所以必须同时看 commit。
mem_commit <- function() {
  ps <- suppressWarnings(system2("powershell",
    c("-NoProfile", "-Command",
      "\"$o=Get-CimInstance Win32_OperatingSystem; $p=Get-CimInstance Win32_PageFileUsage | Select-Object -First 1; '{0}|{1}|{2}' -f $o.TotalVirtualMemorySize, $o.FreeVirtualMemory, $p.CurrentUsage\""),
    stdout = TRUE, stderr = FALSE))
  ps <- ps[nzchar(ps)]
  if (!length(ps)) return(c(limit = NA_real_, used = NA_real_, pf_used = NA_real_))
  v <- suppressWarnings(as.numeric(strsplit(ps[1], "|", fixed = TRUE)[[1]]))
  if (length(v) < 3) return(c(limit = NA_real_, used = NA_real_, pf_used = NA_real_))
  c(limit = v[1] / 1048576, used = (v[1] - v[2]) / 1048576, pf_used = v[3] / 1024)
}

#' 指定目录的总体积（GB）
dir_gb <- function(d) {
  if (!dir.exists(d)) return(0)
  f <- list.files(d, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  if (!length(f)) return(0)
  sum(file.info(f)$size, na.rm = TRUE) / 1073741824
}

main <- function() {
  p  <- count_progress()
  pr <- count_procs()
  mem <- mem_free_gb()
  now <- Sys.time()

  pct <- 100 * p$total_have / TARGET
  cat(sprintf("\n=== %s ===\n", format(now, "%Y-%m-%d %H:%M:%S")))
  cat(sprintf("  完成度: %d / %d = %.2f%%\n", p$total_have, TARGET, pct))
  cat(sprintf("  进程: 基底 %d | 焦点 %d | clcd %d | 其他 %d\n",
              pr[["base"]], pr[["focal"]], pr[["clcd"]], pr[["other"]]))
  cat(sprintf("  内存空闲: %.1f GB\n", mem))
  dk <- disk_free_gb()
  if (length(dk)) {
    cat(sprintf("  磁盘可用: %s\n",
                paste(sprintf("%s %.1f GB", names(dk), dk), collapse = " | ")))
  }
  mc <- mem_commit()
  if (all(is.finite(mc))) {
    cat(sprintf("  \u63d0\u4ea4\u91cf: %.1f / %.1f GB (%.0f%%) ; \u9875\u9762\u6587\u4ef6\u5df2\u7528 %.1f GB\n",
                mc[["used"]], mc[["limit"]], 100 * mc[["used"]] / mc[["limit"]], mc[["pf_used"]]))
  }
  # tempdir 体积：terra 溢写会写这里，必须盯着。
  # 注意：监控进程自己的 tempdir 与 worker 的不同——worker 启动时显式设了
  # TEMP=D:\checo_tmp。只报监控自己的会看到 2.7 GB 而误以为没问题。
  tdir <- Sys.getenv("TEMP", unset = tempdir())
  cat(sprintf("  tempdir(监控自身): %s = %.1f GB\n", tdir, dir_gb(tdir)))
  wt <- "D:/checo_tmp"
  if (dir.exists(wt))
    cat(sprintf("  tempdir(worker)  : %s = %.1f GB\n", wt, dir_gb(wt)))

  cat("\n  未完成的数据集:\n")
  todo <- p$tab[p$tab$miss > 0, ]
  if (!nrow(todo)) cat("    （无——全部完成）\n") else
    for (i in seq_len(nrow(todo)))
      cat(sprintf("    %-24s %6d / %6d  缺 %5d (%.1f%%)\n",
                  todo$ds[i], todo$have[i], todo$total[i], todo$miss[i],
                  100 * todo$have[i] / todo$total[i]))

  # ---- clcd 专项：层数不逐层增长，且 2026-10-20 起改走内存不落盘，
  #      临时文件已不复存在。改用**进程 CPU 时间**作进度代理。
  #
  # 依据（2026-10-20 实地标定，两次采样）：
  #   每分片 CPU 增长 580 s / 582 s 墙钟 = **99.7% 单核利用率**（纯 CPU-bound）
  #   单带 band=25 内存版实测 75.0 s，每年 163 带 → 12,225 s CPU/年
  #   （早期用 9,275 是按 76% 利用率估的，偏低，会高估进度）
  if (pr[["clcd"]] > 0) {
    CPU_PER_YEAR <- 12225
    cat("\n  clcd 进度（按年产出；不落盘后无临时文件，改看进程 CPU）:\n")
    base_clcd <- list.files(file.path(PATH_COV(), "glo/lulc/clcd"),
                            pattern = "_prop\\.tif$", recursive = TRUE, full.names = TRUE)
    cat(sprintf("    已完成年份: %.1f / 26\n", length(base_clcd) / 9))

    ps <- suppressWarnings(system2("powershell",
      c("-NoProfile", "-Command",
        paste0("\"Get-CimInstance Win32_Process -Filter \\\"Name='Rscript.exe'\\\" | ",
               "Where-Object { $_.CommandLine -like '*06_derive_lulc_clcd*' } | ",
               "ForEach-Object { '{0}|{1}' -f $_.ProcessId, ",
               "(Get-Process -Id $_.ProcessId).CPU }\"")),
      stdout = TRUE, stderr = FALSE))
    ps <- ps[nzchar(ps)]
    if (length(ps)) {
      rows <- do.call(rbind, strsplit(ps, "|", fixed = TRUE))
      cpu <- suppressWarnings(as.numeric(rows[, 2]))
      # 跳过 CPU < 10 s 的启动器包装进程（Rscript 会派生两层，
      # 外层是 launcher、内层才是 worker；只有 worker 的 CPU 会持续增长）
      keep <- is.finite(cpu) & cpu >= 10
      if (any(keep)) {
        tot <- 0
        for (i in which(keep)) {
          cat(sprintf("    pid %-7s CPU %6.0f s  ≈ %.2f 年\n", rows[i, 1], cpu[i], cpu[i] / CPU_PER_YEAR))
          tot <- tot + cpu[i] / CPU_PER_YEAR
        }
        cat(sprintf("    在跑 %d 个 worker，合计折 %.2f 年（另有 %.1f 年已落盘）\n",
                    sum(keep), tot, length(base_clcd) / 9))
      } else {
        cat("    （尚无 worker 累积到 10 s CPU）\n")
      }
    } else {
      cat("    （未取到 clcd 进程 CPU）\n")
    }
  }

  # ---- 基底 -> 焦点 的转换待办（2026-10-20 记）--------------------
  # clcd_focal_one 缺“已存在检查”，与已修复的 hlu_focal_one（缺陷 42）同类。
  # 基底阶段运行中不能改脚本（文件锁），故安排在基底完成后、焦点启动前修。
  if (pr[["clcd"]] > 0) {
    n_base <- length(list.files(file.path(PATH_COV(), "glo/lulc/clcd"),
                                pattern = "_prop\\.tif$", recursive = TRUE))
    n_focal <- length(list.files(file.path(PATH_COV(), "glo/lulc/clcd"),
                                 pattern = "_prop_f\\d+\\.tif$", recursive = TRUE))
    if (n_base >= 234L && n_focal == 0L) {
      cat("\n  ⚠ 基底已完成、焦点尚未开始。**启动焦点前先修 clcd_focal_one 的已存在检查**\n")
    }
  }

  # 告警
  cat("\n  告警:\n")
  n_alert <- 0L
  if (all(is.finite(mc)) && mc[["used"]] / mc[["limit"]] > 0.95) {
    cat(sprintf("    \u26a0 \u63d0\u4ea4\u91cf\u5df2\u8fbe %.0f%%\uff0c\u63a5\u8fd1\u4e0a\u9650\uff0c\u53ef\u80fd bad_alloc\uff1b\u5efa\u8bae\u51cf\u5c11 worker\n",
                100 * mc[["used"]] / mc[["limit"]]))
    n_alert <- n_alert + 1L
  }
  if (!is.na(mem) && mem < 15) { cat("    ⚠ 内存空闲 < 15 GB，进程可能 bad_alloc\n"); n_alert <- n_alert + 1L }
  if (length(dk)) {
    low <- dk[dk < 30]
    if (length(low)) {
      cat(sprintf("    \u26a0 \u78c1\u76d8\u7a7a\u95f4\u4e0d\u8db3: %s\uff08< 30 GB\uff09\uff0cterras \u6ea2\u5199\u4f1a\u5931\u8d25\n",
                  paste(sprintf("%s %.1f GB", names(low), low), collapse = ", ")))
      n_alert <- n_alert + 1L
    }
  }

  # stderr 扫描（2026-10-20 事故后新增）
  # 背景：磁盘写满时进程**仍然存活**、CPU 照涨、内存充足，
  # 唯一异常信号是 .err 里刷满 "_tiffWriteProc: No space left on device"。
  # 而当时我是**手写文件名**去看的，换一轮任务名（r_t_c* -> r_s_c*）就漏了。
  # 这里改为通配符扫描全部 *.err，只看最近 2 小时内修改过的。
  logdir <- file.path(CHECO_ROOT, "logs")
  errs <- list.files(logdir, pattern = "\\.err$", full.names = TRUE)
  if (length(errs)) {
    info <- file.info(errs)
    recent <- errs[!is.na(info$mtime) & info$size > 0 &
                     as.numeric(difftime(Sys.time(), info$mtime, units = "hours")) < 2]
    if (length(recent)) {
      cat(sprintf("    \u26a0 最近 2 小时有 %d 个 .err 文件非空（stderr 有输出）:\n", length(recent)))
      for (f in head(recent, 5)) {
        last <- tryCatch(tail(readLines(f, warn = FALSE), 1), error = function(e) "")
        cat(sprintf("      %-24s %s\n", basename(f), substr(last, 1, 90)))
      }
      n_alert <- n_alert + 1L
    }
  }
  if (pr[["focal"]] == 0 && pr[["base"]] == 0 && pr[["clcd"]] == 0) {
    cat("    ⚠ 没有任何生成任务在跑\n"); n_alert <- n_alert + 1L
  }
  if (pr[["clcd"]] > 0 && (pr[["focal"]] > 0 || pr[["base"]] > 0)) {
    cat("    ⚠ clcd 与 hlu1km 同时在跑——应串行，否则内存冲突\n"); n_alert <- n_alert + 1L
  }
  if (n_alert == 0L) cat("    （无）\n")

  # 追加日志
  row <- data.frame(
    time = format(now, "%Y-%m-%d %H:%M:%S"),
    have = p$total_have, target = TARGET, pct = round(pct, 2),
    base = pr[["base"]], focal = pr[["focal"]], clcd = pr[["clcd"]],
    mem_gb = round(mem, 1),
    stringsAsFactors = FALSE)
  dir.create(dirname(LOG), showWarnings = FALSE, recursive = TRUE)
  write.table(row, LOG, sep = ",", row.names = FALSE, col.names = !file.exists(LOG),
              append = file.exists(LOG), fileEncoding = "UTF-8")

  # 速率：与日志里上一条比较
  if (file.exists(LOG)) {
    h <- read.csv(LOG, stringsAsFactors = FALSE)
    if (nrow(h) >= 2) {
      k <- nrow(h)
      dt <- as.numeric(difftime(as.POSIXct(h$time[k]), as.POSIXct(h$time[k - 1]), units = "min"))
      dh <- h$have[k] - h$have[k - 1]
      if (is.finite(dt) && dt > 0) {
        cat(sprintf("\n  自上次快照（%.0f 分钟）: +%d 层 = %.1f 层/分钟\n", dt, dh, dh / dt))
        if (dh > 0) cat(sprintf("  按此速率剩余 %d 层需 %.1f 小时\n",
                                TARGET - p$total_have, (TARGET - p$total_have) / (dh / dt) / 60))
      }
    }
    cat(sprintf("\n  日志共 %d 条: %s\n", nrow(h), LOG))
  }
  invisible(row)
}

main()
