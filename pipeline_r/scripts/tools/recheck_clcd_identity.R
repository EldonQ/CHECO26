# R/tools/recheck_clcd_identity.R
# 收尾清单 1.2 + 3.2：在**全部** clcd 层上重测两件事
#
# 1.2 组成恒等式：max |sum(9 类) - 1| 与有效像元数
#     现状问题：文档里的 4.24e-08 / 1,165,552 像元来自 300 行冒烟测试
#     （R_PROGRESS_20261019_R6），只覆盖全国网格的 7.4%，不是产品级验证。
#
# 3.2 亚公里组成证据：1 km 有效像元中有多少比例具有"中间值"（非 0/1）
#     已知对照：hlu1km 2020 urban 为 1.97%（98.03% essentially 0 或 1）
#     clcd 是 30 m 源，同一指标预计 >90%
#     这条对比是论文里"三套产品不可互相替代"的最硬证据。
#
# 用法：
#   Rscript R/tools/recheck_clcd_identity.R            # 全部 1,170 层
#   Rscript R/tools/recheck_clcd_identity.R 2010       # 只查某一年（9 类）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

# CLCD 的九类与码（与 R/06_derive_lulc_clcd.R 的 CLCD_LEGEND 保持一致）
CLCD_CLASSES <- c("cropland", "forest", "shrub", "grassland", "water",
                  "snowice", "barren", "impervious", "wetland")

clcd_layer <- function(year, cls) {
  layer_path(c("glo", "lulc", "clcd", as.character(year), cls), "_prop")
}

#' 对一年：返回 max|Σ−1|、有效像元数、中间值比例
one_year <- function(year) {
  paths <- vapply(CLCD_CLASSES, function(cn) clcd_layer(year, cn), "")
  if (!all(file.exists(paths)))
    return(list(year = year, status = "missing",
                n_missing = sum(!file.exists(paths))))

  # 累加九类（流式读取，避免同时持 9 个全国浮点栅格）
  acc_sum <- NULL; valid <- NULL
  for (p in paths) {
    r <- terra::rast(p)
    v <- terra::values(r, mat = FALSE)
    if (is.null(acc_sum)) {
      acc_sum <- ifelse(is.na(v), 0, v)
      valid   <- !is.na(v)          # 以第一类的 NA 结构定义有效像元
    } else {
      acc_sum <- acc_sum + ifelse(is.na(v), 0, v)
      valid   <- valid | !is.na(v)
    }
  }
  dev <- abs(acc_sum[valid] - 1)

  # 中间值比例，两个口径**必须分开报**（2026-10-20 曾把二者混为一谈，
  # 用"任一类"对"单类"相比，把 3.7-10 倍夸大成 35 倍）：
  #   mid_mean : 逐类中间值比例的均值  <- 与 hlu1km 逐类数字同口径
  #   mid_any  : 九类中至少一类有中间值  <- 必然更大，不可与单类相比
  mids <- numeric(0); mid_any <- rep(FALSE, sum(valid))
  for (p in paths) {
    v <- terra::values(terra::rast(p), mat = FALSE)[valid]
    is_mid <- (v > 1e-6 & v < 1 - 1e-6)
    mids <- c(mids, 100 * mean(is_mid))
    mid_any <- mid_any | is_mid
  }

  list(year = year, status = "ok",
       max_dev = max(dev), n_valid = sum(valid),
       mid_mean = mean(mids), mid_any = 100 * mean(mid_any))
}

main <- function(years = NULL) {
  if (is.null(years)) years <- CLCD_YEARS_ <- 2000:2025
  cat(sprintf("=== clcd 组恒等式与亚公里组成重测（%d 年）===\n\n", length(years)))

  res <- list(); worst_dev <- 0; tot_valid <- 0; mids <- numeric(0)
  for (y in years) {
    r <- one_year(y)
    if (r$status != "ok") {
      cat(sprintf("  %d: 缺 %d 层，跳过\n", y, r$n_missing)); next
    }
    worst_dev <- max(worst_dev, r$max_dev)
    tot_valid <- tot_valid + r$n_valid
    cat(sprintf("  %d: max|Σ-1| = %.3e ; 有效 %s ; 逐类均值 %.1f%% ; 任一类 %.1f%%\n",
                y, r$max_dev, format(r$n_valid, big.mark = ","), r$mid_mean, r$mid_any))
    res[[length(res) + 1L]] <- r
  }

  if (!length(res)) { cat("\n无可用年份。\n"); return(invisible(NULL)) }

  cat(sprintf("\n=== 汇总 ===\n"))
  cat(sprintf("  年份数        : %d / %d\n", length(res), length(years)))
  cat(sprintf("  最大 |Σ-1|    : %.3e   （历史文档曾写 4.24e-08，来自冒烟测试；现为全量实测）\n", worst_dev))
  cat(sprintf("  有效像元总数  : %s\n", format(tot_valid, big.mark = ",")))
  mm <- vapply(res, function(x) x$mid_mean, 0)
  ma <- vapply(res, function(x) x$mid_any, 0)
  cat(sprintf("  逐类中间值均值: %.1f%% – %.1f%%（均值 %.1f%%）  <- 与 hlu1km 逐类同口径\n",
              min(mm), max(mm), mean(mm)))
  cat(sprintf("  任一类中间值  : %.1f%% – %.1f%%  <- 九类求并，不可与单类相比\n",
              min(ma), max(ma)))
  cat(sprintf("  对照 hlu1km   : 八类均值 5.8%% ; urban 1.97%%\n"))
  # 判定必须用逐类均值 mm，不能用早已废弃的 mids（那个变量在上一步已移除，
  # 引用它会得到 NULL -> mean(NULL) = NA，于是判定行印出 "NA"）
  cat(sprintf("\n  判定: 恒等式 %s（阈值 1e-6）；亚公里证据 %s\n",
              ifelse(worst_dev < 1e-6, "通过", "**未通过**"),
              ifelse(mean(mm) > 2 * 5.8, "成立（逐类均值 >2x hlu1km 的 5.8%）",
                     "**不成立，需复查**")))

  # 落盘，便于写进文档
  # 注意：res 的元素是 list，x["year"] 仍返回 list，vapply 会报
  # "values must be type 'double' but FUN(X[[1]]) result is type 'list'"。
  # 必须用 x$year（即 x[["year"]]）取标量。
  out <- data.frame(year = vapply(res, function(x) x$year, 0L),
                    max_abs_sum_minus_1 = vapply(res, function(x) x$max_dev, 0),
                    n_valid = vapply(res, function(x) x$n_valid, 0),
                    mid_per_class_mean_pct = vapply(res, function(x) x$mid_mean, 0),
                    mid_any_class_pct = vapply(res, function(x) x$mid_any, 0))
  f <- file.path(PATH_DOCS(), "clcd_identity_recheck.csv")
  # 2026-10-20 修：原来直接 write.csv 会**覆盖**上一次的结果，
  # 于是先跑 2000:2005 再单独跑 2008，CSV 里就只剩 2008。
  # 改为与已有记录按年份合并，便于逐年累积复核。
  if (file.exists(f)) {
    old <- tryCatch(read.csv(f, fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE),
                    error = function(e) NULL)
    if (!is.null(old) && nrow(old) && "year" %in% names(old)) {
      out <- out[!out$year %in% old$year, , drop = FALSE]
      out <- rbind(old, out)
      out <- out[order(out$year), , drop = FALSE]
    }
  }
  write.csv(out, f, row.names = FALSE, fileEncoding = "UTF-8")
  cat(sprintf("\n  明细已写入（累积 %d 年）: %s\n", nrow(out), f))
  invisible(out)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) as.integer(a[1]) else NULL)
}
