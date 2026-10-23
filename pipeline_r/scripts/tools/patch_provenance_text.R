# R/tools/patch_provenance_text.R
# 修正已生成溯源表里的静态文本（生成器改了但数据已存在的情形）
#
# 背景（2026-10-21）：
#   `R/13_make_provenance.R` 里的 clcd 行定义原先写着
#     "max|sum-1| = 4.24e-08 over 25,684 cells"
#   这是更早期一次小窗口冒烟测试的数字。生成器已改为全量实测值
#     "9,471,991 valid cells: max|sum-1| = 5.08e-08 ..."
#   但**已生成的 1,170 行不会因此更新**——`13_make_provenance.R fill`
#   只填充统计字段（actual_range），静态文本保持原样，且它的幂等逻辑
#   检测到"基准表已含"就跳过这些行。
#
#   这正是"改了生成器，但数据已存在"的典型失败模式：
#   改代码 ≠ 改数据。
#
# 用法：
#   Rscript R/tools/patch_provenance_text.R dry    # 只报受影响的处数
#   Rscript R/tools/patch_provenance_text.R apply  # 实际写入（自动备份）
ROOT <- "E:/CHECO26/N-SDM"
PROV <- file.path(ROOT, "00_docs", "provenance_table.csv")

OLD <- paste0(
  "Source class 0 is set to NA before aggregation, so the nine proportions sum to exactly 1 ",
  "within every valid cell (verified: max|sum-1| = 4.24e-08 over 25,684 cells). ",
  "Cells outside the China mask are nodata.")

NEW <- paste0(
  "Source class 0 is set to NA before aggregation, so the nine proportions sum to exactly 1 ",
  "within every valid cell. Verified on the complete 2000 reference year over all ",
  "9,471,991 valid cells: max|sum-1| = 5.08e-08 (independent recomputation with exactextractr ",
  "agrees to 5.0e-09). 18,319 cells of the national mask (0.19%) are nodata because the CLCD ",
  "raster does not reach the vector boundary; sampled cells there had zero valid 30 m source ",
  "pixels. Cells outside the China mask are nodata.")

main <- function(mode = c("dry", "apply")) {
  mode <- match.arg(mode)
  if (!file.exists(PROV)) stop("溯源表不存在: ", PROV)
  p <- read.csv(PROV, fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE,
                check.names = FALSE)
  cat(sprintf("溯源表: %d 行 x %d 列\n", nrow(p), ncol(p)))

  hit <- which(p$missing_boundary_rule == OLD)
  cat(sprintf("命中原文本的行: %d\n", length(hit)))
  if (!length(hit)) {
    cat("无需修改。\n")
    return(invisible(0L))
  }
  cat(sprintf("受影响的数据集: %s\n",
              paste(unique(sub("^glo/([^/]+/[^/]+)/.*$", "\\1", p$layer_path[hit])), collapse = ", ")))

  # 安全检查：旧文本里若还有其他变体，先报出来
  other <- grep("25,684|4\\.24e-08", p$missing_boundary_rule, value = FALSE)
  cat(sprintf("含旧数字（25,684 或 4.24e-08）的总行数: %d\n", length(other)))

  if (mode == "dry") {
    cat("\n[dy] 未写入。加 apply 参数以实际写入。\n")
    return(invisible(length(hit)))
  }

  bak <- paste0(PROV, ".bak_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  file.copy(PROV, bak, overwrite = FALSE)
  cat(sprintf("\n已备份: %s\n", basename(bak)))

  p$missing_boundary_rule[hit] <- NEW
  write.csv(p, PROV, row.names = FALSE, fileEncoding = "UTF-8")
  cat(sprintf("已写入 %d 行\n", length(hit)))

  # 写后自检
  q <- read.csv(PROV, fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE,
                check.names = FALSE)
  left <- grep("25,684|4\\.24e-08", q$missing_boundary_rule)
  cat(sprintf("写后自检: 行数 %d ; 仍含旧数字的行 %d\n", nrow(q), length(left)))
  invisible(length(left))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) a[1] else "dry")
}
