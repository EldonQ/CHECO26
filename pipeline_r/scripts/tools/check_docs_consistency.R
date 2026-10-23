# R/tools/check_docs_consistency.R
# 文档一致性检查：把"手填数字"变成"可自动发现的错误"
#
# 动机（2026-10-20）：本会话三次在文档里写了凭记忆的数字并被实际值打回
#   1) 说 hlu1km 基底缺 632 层（实际只剩 12 层）
#   2) 说 clcd 亚公里证据是 "68.6% vs 1.97%，35 倍"（口径不同，实为 3.7–10 倍）
#   3) README 写 "78 个测试 + 6 个工具 + 6 个绘图"（实际 70 / 7 / 5）
# 前两个靠人发现，第三个写进文档就只能靠人复查。
# 这个脚本把"能从磁盘/表里算出来的数字"逐个比对，任何不一致都报出来。
#
# 用法：
#   Rscript R/tools/check_docs_consistency.R
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

bad <- 0L; ok <- 0L
chk <- function(what, claimed, actual) {
  good <- identical(as.character(claimed), as.character(actual))
  if (good) { cat(sprintf("  PASS  %-42s %s\n", what, actual)); ok <<- ok + 1L }
  else { cat(sprintf("  FAIL  %-42s 文档写 %s，实际 %s\n", what, claimed, actual)); bad <<- bad + 1L }
}

read_md <- function(f) paste(readLines(file.path(PATH_DOCS(), f), encoding = "UTF-8",
                                     warn = FALSE), collapse = "\n")

#' 从 Markdown 里抓形如 `NN 个测试` 的数字
grab <- function(txt, pattern) {
  m <- regmatches(txt, regexpr(pattern, txt))
  if (!length(m)) return(NA_character_)
  sub(pattern, "\\1", m)
}

main <- function() {
  cat("=== 文档一致性检查 ===\n\n")

  # ---------- 1) 脚本与图件计数 ----------
  cat("1) R/ 目录计数（README §七）\n")
  n_main <- length(list.files(file.path(CHECO_ROOT, "R"), pattern = "\\.R$"))
  n_test <- length(list.files(file.path(CHECO_ROOT, "R", "tests"), pattern = "\\.R$"))
  n_tool <- length(list.files(file.path(CHECO_ROOT, "R", "tools"), pattern = "\\.R$"))
  n_fig  <- length(list.files(file.path(CHECO_ROOT, "R", "figs"),  pattern = "\\.R$"))
  readme <- read_md("README.md")
  chk("主脚本数", grab(readme, "([0-9]+) 个主脚本"), n_main)
  chk("测试脚本数", grab(readme, "([0-9]+) 个测试"), n_test)
  chk("工具脚本数", grab(readme, "([0-9]+) 个工具"), n_tool)
  chk("绘图脚本数", grab(readme, "([0-9]+) 个绘图脚本"), n_fig)

  # ---------- 2) 图件张数 ----------
  cat("\n2) 图件张数（README §四）\n")
  n_png <- length(list.files(file.path(PATH_DOCS(), "figures"), pattern = "\\.png$"))
  chk("可用图件张数", grab(readme, "figures/`，([0-9]+) 张"), n_png)

  # ---------- 3) 目标层数与完成度 ----------
  cat("\n3) 层数（provenance 表 vs Data Records）\n")
  prov <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"),
                   fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
  n_active <- sum(prov$status == "active")
  n_all    <- nrow(prov)
  chk("active 层数（应为 21,110）", 21110L, n_active)
  chk("provenance 总行数（active + withdrawn）", n_all, 21118L)

  # ---------- 4) 已知限制条数 ----------
  cat("\n4) 已知限制条数（README vs Usage Notes）\n")
  un_txt <- read_md("USAGE_NOTES_AND_LIMITATIONS.md")
  # 注意：文本已折叠成单个字符串，^ 在多行模式下不生效
  # 首版写成 "^### B" 数出 0 条——限制的真实层级是 "## B"（三级 "###" 只有后来追加的
  # B21–B23 用过，已统一为 "##"），且必须匹配 "\n## B" 而不是行首锚点。
  n_b <- length(regmatches(un_txt, gregexpr("\n## B[0-9]+", un_txt, fixed = FALSE))[[1]])
  chk("Usage Notes 限制条数", grab(readme, "([0-9]+) 项已知限制"), n_b)

  # ---------- 5) 论文行数 ----------
  cat("\n5) 论文各节行数（README vs 实际）\n")
  for (f in c("PAPER_ABSTRACT_AND_BACKGROUND.md", "PAPER_DATA_RECORDS.md",
              "PAPER_METHODS.md", "PAPER_TECHNICAL_VALIDATION.md")) {
    n_ln <- length(readLines(file.path(PATH_DOCS(), f), warn = FALSE))
    # README 里的行: | `PAPER_XXX.md` | 264 | ...
    pat <- paste0("`", f, "` \\| ([0-9]+) \\|")
    chk(f, grab(readme, pat), n_ln)
  }

  # ---------- 6) 论文合计行数 ----------
  cat("\n6) 论文合计行数\n")
  tot_actual <- sum(vapply(c("PAPER_ABSTRACT_AND_BACKGROUND.md", "PAPER_DATA_RECORDS.md",
                             "PAPER_METHODS.md", "PAPER_TECHNICAL_VALIDATION.md"),
                           function(f) length(readLines(file.path(PATH_DOCS(), f), warn = FALSE)), 0L))
  chk("论文合计行数", grab(readme, "\\*\\*合计 ([0-9,]+) 行"), format(tot_actual, big.mark = ","))

  # ---- 论文里的核心数字（2026-10-21 新增） ----
  # 已发生过一次 GB/GiB 单位混淆（157.8 GiB 被写成 157.8 GB），
  # 所以把论文引用的磁盘事实固定成可机器校验的断言。
  # 2026-10-21 扩展：论文现有三份（正文 + 投稿英文版 + 中文版）。
  # 只核对其中一份，另两份可以静默地漂移。因此循环核对全部。
  papers <- c("PAPER_CHECO26_DATADESCRIPTOR.md",
              file.path("SUBMISSION", "PAPER_EN.md"),
              file.path("SUBMISSION", "PAPER_ZH.md"))
  papers <- papers[file.exists(file.path(PATH_DOCS(), papers))]
  for (pf in papers) {
  pp <- file.path(PATH_DOCS(), pf)
  cat(sprintf("\n7) \u8bba\u6587\u5f15\u7528\u7684\u6570\u5b57\uff08%s\uff09\n", pf))
  if (file.exists(pp)) {
    ptxt <- paste(readLines(pp, encoding = "UTF-8", warn = FALSE), collapse = "\n")
    gp <- function(pat) {
      m <- regmatches(ptxt, regexpr(pat, ptxt, perl = TRUE))
      if (!length(m)) NA_character_ else sub(pat, "\\1", m, perl = TRUE)
    }
    prov2 <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"),
                      fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
    act2 <- prov2[prov2$status == "active", ]
    th2 <- sub("/.*", "", sub("^glo/", "", act2$layer_path))
    man2 <- read.csv(file.path(PATH_DOCS(), "MANIFEST.csv"),
                     fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
    gb2 <- sum(man2$bytes[grepl("^covariates/", man2$relpath)]) / 1e9

    chk("\u8bba\u6587 cov \u4f53\u79ef (GB)", gp("([0-9]+\\.[0-9]) GB"),
        sprintf("%.1f", gb2))
    # 中文版用“8 个主题”而非“eight themes”，模式需按语言选择
    zh <- grepl("PAPER_ZH", pf)
    n_th <- length(unique(th2))
    if (zh) {
      chk("\u8bba\u6587\u4e3b\u9898\u6570", gp("([0-9]+) \u4e2a\u4e3b\u9898"), as.character(n_th))
    } else {
      chk("\u8bba\u6587\u4e3b\u9898\u6570", gp("(eight|ten) themes"),
          if (n_th == 8L) "eight" else "ten")
    }
    for (nm in c("lulc", "bioclim", "soil", "anthro", "hydro", "vege", "dist", "topo")) {
      # 2026-10-21 改：原来要求单元格写成 "(`lulc`)"，绑定了一种排版；
      # 改为 `| `lulc` | **20,150**` 这种更自然的形式，与论文的主题汇总表一致。
      pat <- sprintf("\\| `%s` \\| \\*\\*([0-9,]+)\\*\\*", nm)
      chk(sprintf("\u8bba\u6587 %s \u5408\u8ba1", nm), gp(pat),
          format(sum(th2 == nm), big.mark = ","))
    }
    ds2 <- unique(paste(sub("/.*", "", sub("^glo/", "", act2$layer_path)),
      sapply(strsplit(sub("^glo/", "", act2$layer_path), "/"),
             function(x) if (length(x) >= 2) x[2] else x[1]), sep = "/"))
    if (zh) {
      chk("\u8bba\u6587\u6570\u636e\u96c6\u6570", gp("([0-9]+) \u4e2a\u6570\u636e\u96c6"), as.character(length(ds2)))
    } else {
      chk("\u8bba\u6587\u6570\u636e\u96c6\u6570", gp("([0-9]+) datasets"),
          as.character(length(ds2)))
    }
  }
  }

  cat(sprintf("\n=== 汇总: PASS %d / FAIL %d ===\n", ok, bad))
  if (bad > 0L) {
    cat("\n以上 FAIL 是文档里的数字与磁盘实际不符。\n")
    cat("修法：改 README 里对应的数字，或改本脚本的期望值（如果是本脚本过时）。\n")
  } else {
    cat("\n文档数字与磁盘一致。\n")
  }
  invisible(bad)
}

if (sys.nframe() == 0L) main()
