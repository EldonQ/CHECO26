# R/tools/refresh_readme_numbers.R
# 把 README.md 里所有"可从磁盘算出"的数字重新生成
#
# 动机：本会话有 4 次因手填数字而被实际值打回：
#   1) hlu1km 基底缺 632 层（实际 12）      2) 68.6% vs 1.97% 口径不同
#   3) 78 测试 / 6 工具 / 6 绘图（实际 70/7/5）  4) 论文行数 264/1218（实际 266/1220）
# 每一次都是"能算出来的数字却手填了"。与 report_status.R 自动生成完成度表同理，
# 这里把 README 的计数也交给脚本。
#
# 用法：
#   Rscript R/tools/refresh_readme_numbers.R        # 只报告差异
#   Rscript R/tools/refresh_readme_numbers.R write  # 写回
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

readme_path <- function() file.path(PATH_DOCS(), "README.md")

#' 磁盘上的真实计数
actual_counts <- function() {
  root <- CHECO_ROOT
  docs <- PATH_DOCS()
  papers <- c("PAPER_ABSTRACT_AND_BACKGROUND.md", "PAPER_DATA_RECORDS.md",
              "PAPER_METHODS.md", "PAPER_TECHNICAL_VALIDATION.md")
  nlines <- function(f) length(readLines(file.path(docs, f), encoding = "UTF-8", warn = FALSE))
  un_txt <- paste(readLines(file.path(docs, "USAGE_NOTES_AND_LIMITATIONS.md"),
                            encoding = "UTF-8", warn = FALSE), collapse = "\n")
  list(
    main  = length(list.files(file.path(root, "R"), pattern = "\\.R$")),
    test  = length(list.files(file.path(root, "R", "tests"), pattern = "\\.R$")),
    tool  = length(list.files(file.path(root, "R", "tools"), pattern = "\\.R$")),
    fig_r = length(list.files(file.path(root, "R", "figs"),  pattern = "\\.R$")),
    fig_p = length(list.files(file.path(docs, "figures"), pattern = "\\.png$")),
    lim   = length(regmatches(un_txt, gregexpr("\n## B[0-9]+", un_txt, fixed = FALSE))[[1]]),
    paper = setNames(vapply(papers, nlines, 0L), papers),
    ptotal = sum(vapply(papers, nlines, 0L))
  )
}

main <- function(mode = c("report", "write")) {
  mode <- match.arg(mode)
  a <- actual_counts()
  s <- paste(readLines(readme_path(), encoding = "UTF-8", warn = FALSE), collapse = "\n")
  orig <- s
  changes <- character(0)

  sub1 <- function(pat, repl, label) {
    m <- regmatches(s, regexpr(pat, s))
    if (!length(m)) { cat(sprintf("  --  %-28s 未找到锚点\n", label)); return(invisible()) }
    new <- sub(pat, repl, m)
    if (identical(new, m)) { cat(sprintf("  OK  %-28s %s\n", label, m)); return(invisible()) }
    s <<- sub(pat, repl, s)
    changes <<- c(changes, sprintf("%s: %s -> %s", label, m, new))
    cat(sprintf("  FIX %-28s %s -> %s\n", label, m, new))
  }

  cat("=== README 计数复核 ===\n\n1) R/ 目录\n")
  sub1("([0-9]+) 个主脚本", sprintf("%d 个主脚本", a$main), "主脚本数")
  sub1("([0-9]+) 个测试",   sprintf("%d 个测试",   a$test), "测试脚本数")
  sub1("([0-9]+) 个工具",   sprintf("%d 个工具",   a$tool), "工具脚本数")
  sub1("([0-9]+) 个绘图脚本", sprintf("%d 个绘图脚本", a$fig_r), "绘图脚本数")

  cat("\n2) 图件与限制\n")
  sub1("figures/`，([0-9]+) 张", sprintf("figures/`，%d 张", a$fig_p), "图件张数")
  sub1("([0-9]+) 项已知限制", sprintf("%d 项已知限制", a$lim), "限制条数")

  cat("\n3) 论文行数\n")
  for (f in names(a$paper)) {
    sub1(paste0("`", f, "` \\| ([0-9]+) \\|"),
         sprintf("`%s` | %d |", f, a$paper[[f]]), f)
  }
  sub1("\\*\\*合计 ([0-9,]+) 行", sprintf("**合计 %s 行", format(a$ptotal, big.mark = ",")), "论文合计")

  if (mode == "write" && length(changes)) {
    writeLines(s, readme_path(), useBytes = TRUE)
    cat(sprintf("\n已写回 README.md（%d 处修改）\n", length(changes)))
  } else if (!length(changes)) {
    cat("\n全部一致，无需修改。\n")
  } else {
    cat(sprintf("\n发现 %d 处不一致。加 write 参数以写回。\n", length(changes)))
  }
  invisible(length(changes))
}

if (sys.nframe() == 0L) {
  arg <- commandArgs(trailingOnly = TRUE)
  main(if (length(arg) >= 1) arg[1] else "report")
}
