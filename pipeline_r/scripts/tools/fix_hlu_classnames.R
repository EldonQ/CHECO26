# R/tools/fix_hlu_classnames.R
# 修复 hlu1km 图层名错位（segregate 按码升序，原命名未排序）
#
# 置换（5-循环，无不动点，两阶段改名避免碰撞）：
#   mngforest  -> grassshrub   (文件里装的是 55 Unmanaged grass/shrubland)
#   forest     -> sparse       (66 Sparse/no vegetation)
#   grassshrub -> water        (77 Water)
#   sparse     -> mngforest    (441 Managed forest)
#   water      -> forest       (442 Unmanaged forest)
#   urban / cropland / pasture 不变
#
# 用法：
#   Rscript R/tools/fix_hlu_classnames.R dry     # 只统计，不改动
#   Rscript R/tools/fix_hlu_classnames.R apply   # 实际改名
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

MAP <- c(mngforest = "grassshrub", forest = "sparse", grassshrub = "water",
         sparse = "mngforest", water = "forest")

root <- file.path(PATH_COV(), "glo/lulc/hlu1km")
stopifnot(dir.exists(root))

#' 两阶段改名：先把所有 src 改成 __TMP_<src>，再改成目标名
two_phase <- function(pairs, is_dir = FALSE) {
  if (!nrow(pairs)) return(invisible(0L))
  # 阶段 1
  for (i in seq_len(nrow(pairs))) {
    tmp <- file.path(pairs$dir[i], paste0("__TMP_", pairs$from[i]))
    if (is_dir) file.rename(pairs$path[i], tmp) else file.rename(pairs$path[i], tmp)
    pairs$tmp[i] <- tmp
  }
  # 阶段 2
  ok <- 0L
  for (i in seq_len(nrow(pairs))) {
    dst <- file.path(pairs$dir[i], pairs$to[i])
    if (file.rename(pairs$tmp[i], dst)) ok <- ok + 1L else
      warning(sprintf("改名失败: %s -> %s", pairs$tmp[i], dst))
  }
  ok
}

main <- function(mode = c("dry", "apply")) {
  mode <- match.arg(mode)
  print_grid()

  # ---- 1) 类目目录 ----
  all_dirs <- list.dirs(root, recursive = TRUE, full.names = TRUE)
  cls_dirs <- all_dirs[basename(all_dirs) %in% names(MAP)]
  cat(sprintf("待改名的类目目录: %d 个\n", length(cls_dirs)))
  dp <- data.frame(path = cls_dirs, dir = dirname(cls_dirs),
                   from = basename(cls_dirs), tmp = NA_character_,
                   stringsAsFactors = FALSE)
  dp$to <- unname(MAP[dp$from])

  # ---- 2) 文件 ----
  fs <- list.files(root, pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
  fs <- fs[!grepl("\\.(aux\\.xml|tmp\\.tif|tif\\.ovr)$", fs)]
  hit <- vapply(fs, function(p) {
    b <- basename(p)
    any(vapply(names(MAP), function(k) grepl(paste0("_", k, "_prop"), b, fixed = TRUE), TRUE))
  }, TRUE)
  fs <- fs[hit]
  cat(sprintf("待改名的类目目录: %d 个；文件: %d 个\n", nrow(dp), length(fs)))

  fp <- do.call(rbind, lapply(fs, function(p) {
    b <- basename(p); d <- dirname(p)
    for (k in names(MAP)) {
      if (grepl(paste0("_", k, "_prop"), b, fixed = TRUE)) {
        nb <- sub(paste0("_", k, "_prop"), paste0("_", MAP[[k]], "_prop"), b, fixed = TRUE)
        return(data.frame(path = p, dir = d, from = b, to = nb, tmp = NA_character_,
                          stringsAsFactors = FALSE))
      }
    }
    NULL
  }))
  cat(sprintf("  可解析出的文件改名对: %d\n", nrow(fp)))

  # ---- 3) 抽样展示 ----
  cat("\n=== 抽样（前 4 个目录、前 4 个文件）===\n")
  for (i in head(seq_len(nrow(dp)), 4))
    cat(sprintf("  DIR  %-14s -> %s\n", dp$from[i], dp$to[i]))
  for (i in head(seq_len(nrow(fp)), 4))
    cat(sprintf("  FILE %-58s -> %s\n", fp$from[i], fp$to[i]))

  if (mode == "dry") {
    cat("\n[dry] 未做任何改动。确认无误后用 apply 执行。\n")
    return(invisible(list(dir = dp, file = fp)))
  }

  cat("\n=== 执行改名 ===\n")
  n1 <- two_phase(dp, is_dir = TRUE)
  cat(sprintf("  目录改名成功: %d / %d\n", n1, nrow(dp)))

  # 目录已改，文件的 dir 需随之更新
  fp$dir <- vapply(fp$dir, function(d) {
    b <- basename(d)
    if (b %in% names(MAP)) file.path(dirname(d), unname(MAP[[b]])) else d
  }, "")
  fp$path <- file.path(fp$dir, fp$from)

  n2 <- two_phase(fp, is_dir = FALSE)
  cat(sprintf("  文件改名成功: %d / %d\n", n2, nrow(fp)))

  cat("\n=== 改名后统计 ===\n")
  for (c in c("urban","cropland","pasture","mngforest","forest","grassshrub","sparse","water"))
    cat(sprintf("  %-12s %5d\n", c,
                length(list.files(root, pattern = paste0("_", c, "_prop.*\\.tif$"),
                                  recursive = TRUE))))
  cat(sprintf("  合计 %d\n", length(list.files(root, pattern = "\\.tif$", recursive = TRUE))))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a)) a[1] else "dry")
}
