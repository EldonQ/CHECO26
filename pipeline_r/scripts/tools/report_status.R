# R/tools/report_status.R
# 从溯源表 + 实际文件存在性生成"层数完成情况"表，并就地更新核验报告的 §2
#
# 存在的理由：报告里的动态数字靠手写必然过时，而过时的数字比没有数字更糟
# （读者会以为进度停滞）。本脚本保证表格永远反映实测状态。
#
# 用法： Rscript R/tools/report_status.R            # 只打印
#        Rscript R/tools/report_status.R write      # 同时写回报告
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

build_table <- function() {
  prov <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"),
                   fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
  prov <- prov[prov$status == "active", ]
  ex <- file.exists(file.path(PATH_COV(), prov$layer_path))
  th <- sub("^glo/([^/]+)/.*$", "\\1", prov$layer_path)
  ds <- sub("^glo/[^/]+/([^/]+)/.*$", "\\1", prov$layer_path)
  key <- paste(th, ds, sep = "/")
  agg <- tapply(ex, key, function(v) c(have = sum(v), total = length(v)))
  tab <- data.frame(ds = names(agg),
                    total = as.integer(sapply(agg, "[", "total")),
                    have  = as.integer(sapply(agg, "[", "have")),
                    row.names = NULL, stringsAsFactors = FALSE)
  tab$miss <- tab$total - tab$have
  tab$pct  <- round(100 * tab$have / tab$total, 1)
  tab[order(-tab$miss, tab$ds), ]
}

render_md <- function(tab, when = Sys.time()) {
  L <- c(sprintf("> 截至 %s 实测（由实际文件存在性统计，数据仍在增长）", format(when, "%Y-%m-%d %H:%M")),
         "",
         "| 数据集 | 目标 | 已有 | 缺口 | 完成度 |",
         "|---|---:|---:|---:|---:|")
  for (i in seq_len(nrow(tab)))
    L <- c(L, sprintf("| `%s` | %s | %s | %s | **%.1f%%** |", tab$ds[i],
        format(tab$total[i], big.mark = ","), format(tab$have[i], big.mark = ","),
        format(tab$miss[i], big.mark = ","), tab$pct[i]))
  c(L, sprintf("| **合计** | **%s** | **%s** | **%s** | **%.2f%%** |",
      format(sum(tab$total), big.mark = ","), format(sum(tab$have), big.mark = ","),
      format(sum(tab$miss), big.mark = ","), 100 * sum(tab$have) / sum(tab$total)))
}

main <- function(mode = c("print", "write")) {
  mode <- match.arg(mode)
  tab <- build_table()
  md  <- render_md(tab)
  cat(md, sep = "\n")
  cat("\n")

  if (mode == "write") {
    p <- file.path(PATH_DOCS(), "FINAL_VERIFICATION_REPORT.md")
    s <- paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    i <- regexpr("> 截至 [^\n]*实测（由实际文件存在性统计，数据仍在增长）", s)
    if (i < 0) i <- regexpr("\\| 数据集 \\| 目标 \\| 已有 \\| 缺口 \\| 完成度 \\|", s)
    if (i < 0) { cat("报告里未找到可替换的表格，放弃\n"); return(invisible(tab)) }
    # 表格从匹配处开始，到其后第一个空行+非表格行结束
    start <- as.integer(i)
    rest  <- substring(s, start)
    lines <- strsplit(rest, "\n", fixed = TRUE)[[1]]
    k <- 1L
    while (k <= length(lines) && (grepl("^\\|", lines[k]) || grepl("^> 截至", lines[k]) || lines[k] == "")) {
      if (lines[k] == "" && k > 2 && !grepl("^\\|", lines[k + 1])) break
      k <- k + 1L
    }
    s2 <- paste0(substring(s, 1, start - 1), paste(md, collapse = "\n"),
                 "\n", paste(lines[k:length(lines)], collapse = "\n"))
    writeLines(s2, p, useBytes = FALSE)
    cat("已写回 FINAL_VERIFICATION_REPORT.md §2\n")
  }
  invisible(tab)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a)) a[1] else "print")
}
