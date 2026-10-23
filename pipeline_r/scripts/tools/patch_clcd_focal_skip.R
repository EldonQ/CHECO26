# R/tools/patch_clcd_focal_skip.R
# 缺陷 44 的修复补丁：给 clcd_focal_one 加上按尺度的"已存在检查"
#
# 为什么做成独立补丁：R/06_derive_lulc_clcd.R 在基底阶段被运行中的分片独占
# （Windows 文件锁），改动必须等到"基底完成、焦点启动前"；那时分片已退出，零成本。
#
# 用法：
#   Rscript R/tools/patch_clcd_focal_skip.R dry     # 只验证，不写文件
#   Rscript R/tools/patch_clcd_focal_skip.R apply   # 写入（先备份，失败自动回滚）
#
# 实现方式：**逐行手术**，不做多行字符串匹配。
#   早先版本把整段函数放进一个单引号字符串里替换，连续踩了两个坑：
#     1) 字符串以 '# 开头 -> 第二个引号把字符串提前闭合
#     2) 改成换行开头后，第二行仍是 '# -> 同样闭合
#   多行 R 字符串里只要出现一个与定界符相同的引号就会崩，而函数体里到处都是引号。
#   改成逐行插入后，每处改动都是单行短字符串，不再有这个问题。
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")

TARGET <- Sys.getenv("CHECO_PATCH_TARGET",
                     "E:/CHECO26/N-SDM/R/06_derive_lulc_clcd.R")

main <- function(mode = c("dry", "apply")) {
  mode <- match.arg(mode)
  L <- readLines(TARGET, encoding = "UTF-8", warn = FALSE)

  if (any(grepl("need <- !file.exists(dsts)", L, fixed = TRUE))) {
    cat("已打过补丁（检测到 need 变量），无需重复。\n")
    return(invisible(FALSE))
  }

  find1 <- function(pat, fixed = TRUE) {
    i <- which(grepl(pat, L, fixed = fixed))
    if (length(i) != 1L) stop(sprintf("锚点未唯一匹配 [%s]: 命中 %d 处", pat, length(i)))
    i
  }

  # --- 1) base 行改为先建 parts（后面 dsts 要用） ---------------------------
  i1 <- find1("  base <- layer_path(clcd_parts(year, cls), \"_prop\")")
  L[i1] <- "  parts <- clcd_parts(year, cls)"
  L <- append(L, "  base <- layer_path(parts, \"_prop\")", after = i1)

  # --- 2) pending 返回之后插入 need 判定 ------------------------------------
  i2 <- find1("  if (!file.exists(base)) return(list(status = \"pending\"))")
  L <- append(L, c(
    "",
    "  # 2026-10-20 修（缺陷 44）：4 个目标全部存在则直接跳过，连基底都不读。",
    "  # 与缺陷 42（hlu_focal_one）同类，是同一段模式复制到本脚本时一并带来的。",
    "  dsts <- layer_path(parts, paste0(\"_prop\", fs$suffix))",
    "  need <- !file.exists(dsts)",
    "  if (!any(need)) return(list(status = \"skip\", n = 0L))"
  ), after = i2)

  # --- 3) cnt 只对需要的尺度准备 -------------------------------------------
  i3 <- find1("  cnt <- lapply(fs$radius_cells, function(rc) {")
  stopifnot(grepl("focal_count_sep", L[i3 + 1L], fixed = TRUE))
  stopifnot(trimws(L[i3 + 2L]) == "})")
  L <- L[-(i3 + 1L):-(i3 + 2L)]
  L <- append(L, c(
    "    if (!need[k]) return(NULL)",
    "    rc <- fs$radius_cells[k]",
    "    if (2L * rc + 1L >= 21L) focal_count_sep(terra::ifel(is.na(b), NA, 1), rc) else NULL",
    "  })"
  ), after = i3)
  L[i3] <- "  cnt <- lapply(seq_len(nrow(fs)), function(k) {"

  # --- 4) 写循环只处理缺失的尺度 -------------------------------------------
  i4 <- find1("  for (k in seq_len(nrow(fs))) {")
  L[i4] <- "  for (k in which(need)) {"
  i5 <- find1("    dst <- layer_path(clcd_parts(year, cls), paste0(\"_prop\", fs$suffix[k]))")
  L <- L[-i5]
  i6 <- which(grepl("atomic_write_raster(dst, out, dtype = \"float32\")", L, fixed = TRUE))
  if (length(i6) != 1L) stop("atomic_write_raster 锚点未唯一匹配")
  L[i6] <- "    atomic_write_raster(dsts[k], out, dtype = \"float32\")"

  if (mode == "dry") {
    tmp <- tempfile(fileext = ".R"); writeLines(L, tmp, useBytes = TRUE)
    r <- tryCatch({ invisible(parse(tmp)); "语法 OK" },
                  error = function(e) paste("语法错误:", conditionMessage(e)))
    cat(sprintf("dry-run: %s\n", r))
    cat(sprintf("dry-run: 行数 %d -> %d\n", length(readLines(TARGET, warn = FALSE)), length(L)))
    unlink(tmp)
    cat("（未写入文件。加 apply 参数以实际写入）\n")
    return(invisible(identical(r, "语法 OK")))
  }

  bak <- paste0(TARGET, ".bak_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  file.copy(TARGET, bak, overwrite = FALSE)
  cat(sprintf("已备份: %s\n", basename(bak)))
  writeLines(L, TARGET, useBytes = TRUE)

  r <- tryCatch({ invisible(parse(TARGET)); "语法 OK" },
                error = function(e) paste("语法错误:", conditionMessage(e)))
  cat(sprintf("写入后校验: %s\n", r))
  if (!identical(r, "语法 OK")) {
    file.copy(bak, TARGET, overwrite = TRUE); cat("已回滚\n"); quit(save = "no", status = 1L)
  }
  cat(sprintf("补丁已应用: %s\n", TARGET))
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) a[1] else "dry")
}
