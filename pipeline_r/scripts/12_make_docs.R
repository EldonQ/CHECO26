# =============================================================================
# R/12_make_docs.R  --  变量字典与交付文档
#
# 与早期 Python 版 09_make_docs.py 逐项对齐（该脚本已归档于 archive/removed_python_pipeline_20261025/）
#
# 策略（与 13_make_provenance.R 一致）：现有 1,600 行的 unit/note 已人工校对，
# 不重推，而是保留已有行、剔除撤出数据集、为新数据集生成行。
#
# 产出：
#   00_docs/variable_dictionary.csv   每个交付层一行（21,110 行 + 8 withdrawn）
#   00_docs/LAYER_INDEX.md            按主题/数据集的层数索引
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

VD_PATH <- function() file.path(PATH_DOCS(), "variable_dictionary.csv")

# ---- 新数据集的单位与说明 --------------------------------------------------
NEW_META <- list(
  hfp = list(unit = "指数(0-50)", note = "人类足迹指数（Mu 版，面积加权 1km 均值）"),
  clcd = list(unit = "比例(0-1)", note = "CLCD 土地覆盖类别面积比例（30m→1km 面积加权）"),
  hlu1km = list(unit = "比例(0-1)", note = "Harmonised 土地利用类别面积比例（0.01°→1km 面积加权）")
)

#' 从 relpath 解析 theme / dataset / 变量 / 后缀
parse_relpath <- function(rp) {
  parts <- strsplit(rp, "/", fixed = TRUE)[[1]]
  fn <- parts[length(parts)]
  # 后缀：_prop / _prop_fNNNN / _fNNNN / _min / _max / _profile / _shannon_fNNNN ...
  suffix <- ""
  if (grepl("_(prop|edge|shannon|patchdensity-[a-z]+|patchsize-[a-z]+)(_f[0-9]+)?\\.tif$", fn)) {
    suffix <- sub("^.*?(_(prop|edge|shannon|patchdensity|patchsize).*)\\.tif$", "\\1", fn)
  } else if (grepl("_f[0-9]+\\.tif$", fn)) {
    suffix <- sub("^.*(_f[0-9]+)\\.tif$", "\\1", fn)
  } else if (grepl("_(min|max|profile)\\.tif$", fn)) {
    suffix <- sub("^.*(_(min|max|profile))\\.tif$", "\\1", fn)
  }
  list(theme = parts[2], dataset = parts[3], file = fn, suffix = suffix)
}

# ---- CHELSA bioclim 变量单位（按变量区分，而非按数据集）------------------
CHELSA_UNIT <- c(
  bio01="°C", bio02="°C", bio03="%", bio04="°C×100", bio05="°C", bio06="°C", bio07="°C",
  bio08="°C", bio09="°C", bio10="°C", bio11="°C",
  bio12="mm", bio13="mm", bio14="mm", bio15="%", bio16="mm", bio17="mm", bio18="mm", bio19="mm",
  gdd0="°C·day", gdd5="°C·day", gdd10="°C·day"
)

# ---- 新数据集行 ----------------------------------------------------------
mk_vd_rows <- function(prov) {
  out <- list()
  for (i in seq_len(nrow(prov))) {
    rp <- prov$layer_path[i]
    pr <- parse_relpath(rp)
    if (is.na(pr$dataset)) next
    if (pr$theme == "bioclim" && grepl("^chelsa21", pr$dataset)) {
      var <- tail(strsplit(sub("\\.tif$", "", pr$file), "_")[[1]], 1)
      unit <- if (var %in% names(CHELSA_UNIT)) CHELSA_UNIT[[var]] else ""
      out[[length(out) + 1L]] <- data.frame(
        relpath = rp, theme = pr$theme, dataset = pr$dataset,
        unit = unit, value_min = NA_real_, value_max = NA_real_,
        n_valid = NA_integer_, suffix = pr$suffix,
        note = "CHELSA v2.1 生物气候变量（标准口径，1km 重投影）",
        sdm_note = "", stringsAsFactors = FALSE)
    } else if (pr$dataset %in% names(NEW_META)) {
      meta <- NEW_META[[pr$dataset]]
      out[[length(out) + 1L]] <- data.frame(
        relpath = rp, theme = pr$theme, dataset = pr$dataset,
        unit = meta$unit, value_min = NA_real_, value_max = NA_real_,
        n_valid = NA_integer_, suffix = pr$suffix, note = meta$note,
        sdm_note = "", stringsAsFactors = FALSE)
    }
  }
  if (!length(out)) return(NULL)
  do.call(rbind, out)
}

# ---- 主流程 --------------------------------------------------------------
main <- function(fill_stats = TRUE) {
  prov <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"),
                   fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
  base <- read.csv(VD_PATH(), fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
  cat(sprintf("现有字典: %d 行；溯源表: %d 行\n", nrow(base), nrow(prov)))

  drop <- grepl("^reg/anthro/(landscan|foothii)/", base$relpath)
  drop_bio <- grepl("^reg/bioclim/cnclim1km", base$relpath)
  base <- base[!drop & !drop_bio, ]
  cat(sprintf("  剔除 LandScan/footHII: %d 行；旧 cnclim1km bioclim: %d 行，余 %d 行\n",
              sum(drop), sum(drop_bio), nrow(base)))

  new <- mk_vd_rows(prov)
  cat(sprintf("  新数据集行: %d 行\n", nrow(new)))

  # 2026-10-21 修：缺幂等保护。第一次运行后 base 已含这些层，
  # 再次运行会把 new 重复拼上（21,110 + 19,735 = 40,845），
  # 随后 stopifnot(!anyDuplicated) 报错退出。
  # 与 13_make_provenance.R L227 同样的修法：跳过 base 已有的 relpath。
  dup <- new$relpath %in% base$relpath
  if (any(dup)) {
    cat(sprintf("  基准表已含，跳过 %d 行（幂等）\n", sum(dup)))
    new <- new[!dup, , drop = FALSE]
  }

  out <- rbind(base[, names(base)], new[, names(base)])
  # 只保留溯源表中仍为 active 的层
  act <- prov$layer_path[prov$status == "active"]
  out <- out[out$relpath %in% act, ]
  cat(sprintf("合并后: %d 行（期望 21,788）\n", nrow(out)))
  stopifnot(!anyDuplicated(out$relpath))

  if (fill_stats) {
    cat("读取已存在层填 value_min/max/n_valid ...\n")
    root <- PATH_COV(); n <- 0L; t0 <- Sys.time()
    for (i in seq_len(nrow(out))) {
      if (!is.na(out$n_valid[i])) next
      p <- file.path(root, out$relpath[i])
      if (!file.exists(p)) next
      st <- tryCatch(raster_stats(p), error = function(e) NULL)
      if (is.null(st) || st$n == 0) next
      out$value_min[i] <- st$min; out$value_max[i] <- st$max; out$n_valid[i] <- st$n
      n <- n + 1L
      if (n %% 200 == 0) cat(sprintf("  %d ... %.0f 秒\n", n,
                                     as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    }
    cat(sprintf("  已填 %d / %d 行，耗时 %.0f 秒\n", n, nrow(out),
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }

  write.csv(out, VD_PATH(), row.names = FALSE, fileEncoding = "UTF-8")
  cat(sprintf("已写出: %s\n", VD_PATH()))

  # ---- 层数索引 ----
  tab <- table(paste(out$theme, out$dataset, sep = "/"))
  md <- c("# Layer index by theme / dataset (CHECO26)",
          "",
          sprintf("Total layers: **%d**. Grid: 1 km China_Albers, 4861 x 4062.", nrow(out)),
          "",
          "| theme / dataset | layers |", "|---|---:|")
  for (nm in names(tab)) md <- c(md, sprintf("| `%s` | %d |", nm, tab[[nm]]))
  md <- c(md, sprintf("| **total** | **%d** |", nrow(out)))
  writeLines(md, file.path(PATH_DOCS(), "LAYER_INDEX.md"), useBytes = FALSE)
  cat("已写出: LAYER_INDEX.md\n")

  print(tab)
  invisible(out)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(!identical(a[1], "nostats"))
}
