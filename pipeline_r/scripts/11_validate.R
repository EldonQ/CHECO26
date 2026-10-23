# =============================================================================
# R/11_validate.R  --  全库校验
#
# 对应 Python: scripts/08_validate.py
#
# 校验项：
#   V1 网格不变量     CRS / 分辨率 / extent / 尺寸 必须与模板一致
#   V2 格式           float32 单波段、声明 nodata = -9999、可读
#   V3 掩膜合规       中国境外不得有有效像元（OVER-MASK 硬门槛）
#   V4 无效值编码     有效域内不得残留 -9999 数据值（声明 nodata 与实际一致）
#   V5 组成恒等式     LULC 比例组的九类/八类/六类之和 = 1
#   V6 焦点一致性     焦点均值必须落在基底层的 [min, max] 内（等权均值的必要条件）
#
# 输出：CSV 报告 + 控制台摘要。退出码非 0 表示有硬失败。
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", Sys.getenv("CHECO_ROOT", getwd())), "R/_bootstrap.R"),
       encoding = "UTF-8")

#' 枚举交付树中所有层
#' 排除 terra 写入过程中的 .tmp.tif —— 扫描时它可能正被写、或刚被改名，
#' 读不到属正常，不应算作失败（2026-10-19 实测到 2 例假失败）。
list_layers <- function() {
  root <- PATH_COV()
  fs <- list.files(root, pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
  fs[!grepl("\\.(aux\\.xml|tmp\\.tif|tif\\.ovr)$", fs)]
}

#' 读入并把 nodata 归一为 NA（仅在需要值时用）
#'
#' 2026-10-19 修：原用 `terra::NAflag()`，对浮点栅格返回 NaN，此处虽未被调用，
#' 但留着会被照抄。改为读文件头声明的 nodata，并把等于它的像元显式置 NA。
read_layer <- function(p) {
  r <- terra::rast(p)
  nd <- file_nodata(p)          # 不是 terra::NAflag()，见上方说明
  if (!is.na(nd)) r <- terra::ifel(abs(r - nd) < 1e-6, NA, r)
  list(rast = r, nd = nd)
}

#' 从 GDAL 文件头读声明的 nodata。
#' 不能用 terra::NAflag：它对浮点栅格一律返回 NaN（即使文件头写的是 -9999），
#' 2026-10-19 实测确认，故改读 describe 输出。
file_nodata <- function(p) {
  d <- tryCatch(terra::describe(p, print = FALSE), error = function(e) character())
  line <- grep("NoData Value", d, value = TRUE, ignore.case = TRUE)
  if (!length(line)) return(NA_real_)
  v <- suppressWarnings(as.numeric(sub("^.*?NoData Value\\s*=\\s*", "", trimws(line[1]))))
  v
}

# ---- V1/V2：只看头 --------------------------------------------------------
check_header <- function(p) {
  g <- GRID()
  r <- tryCatch(terra::rast(p), error = function(e) NULL)
  if (is.null(r)) return(list(v1 = FALSE, v2 = FALSE, note = "unreadable"))
  same_crs <- identical(terra::crs(r, proj = TRUE), terra::crs(g$rast, proj = TRUE))
  same_res <- isTRUE(all.equal(unname(terra::res(r)), c(g$res, g$res), tolerance = 1e-9))
  same_ext <- isTRUE(all.equal(unname(as.vector(terra::ext(r))),
                               c(g$xmin, g$xmax, g$ymin, g$ymax), tolerance = 1e-9))
  same_dim <- ncol(r) == g$width && nrow(r) == g$height
  v1 <- same_crs && same_res && same_ext && same_dim

  nd <- file_nodata(p)
  v2 <- identical(terra::datatype(r), "FLT4S") && terra::nlyr(r) == 1L &&
        length(nd) == 1L && !is.na(nd) && abs(nd - NODATA()) < 1e-6
  list(v1 = v1, v2 = v2,
       note = sprintf("crs=%s res=%s ext=%s dim=%s dtype=%s nodata=%s",
                      same_crs, same_res, same_ext, same_dim,
                      terra::datatype(r), as.character(nd)))
}

# ---- V3/V4：需要值（流式）--------------------------------------------------
check_mask_and_nodata <- function(p) {
  r <- terra::rast(p)
  m <- china_mask()
  # 境外有效像元数：先掩掉境内，再统计非 NA
  outside <- terra::mask(r, m, maskvalue = TRUE, updatevalue = NA)  # 仅保留境外
  n_out <- as.numeric(terra::global(!is.na(outside), "sum", na.rm = TRUE)[1, 1])
  # 有效域内残留 nd 值（声明 -9999 但值未被识别为 NA 的情形）
  #
  # 2026-10-19 修：这里原用 terra::NAflag(r)，而它对**浮点栅格一律返回 NaN**
  # （本文 Methods §2.3 已专门记录此坑），于是 is.na(nd) 恒为 TRUE、整个检查被跳过，
  # n_bad 永远为 NA，V4 实际从未执行过。改为从 GDAL describe 读声明的 nodata。
  nd <- file_nodata(p)
  n_bad <- NA_real_
  if (!is.na(nd)) {
    bad <- terra::ifel(is.na(r), 0L, terra::ifel(abs(r - nd) < 1e-6, 1L, 0L),
                       filename = tempfile(fileext = ".tif"), overwrite = TRUE,
                       datatype = "INT1U")
    n_bad <- as.numeric(terra::global(bad, "sum", na.rm = TRUE)[1, 1])
  }
  list(n_out = n_out, n_bad = n_bad)
}


#' 按修改时间从旧到新排序
#'
#' 2026-10-19 加：校验器在生成任务运行时会抽到**正在写入**的文件，
#' 造成结论随抽样顺序变化（同一代码两次运行结果不同）。
#' 取最旧的候选，即最可能已经写完的层。
oldest_first <- function(paths) {
  if (!length(paths)) return(paths)
  mt <- file.info(paths)$mtime
  paths[order(mt, na.last = TRUE)]
}

# ---- V5：组成恒等式 -------------------------------------------------------
#' 识别比例组
#'
#' 2026-10-19 修：本库的类别在**兄弟目录**里（如 hlu1km/1960/urban/、hlu1km/1960/cropland/），
#' 不是同一目录下的多个文件。原实现按 dirname() 分组，每组恒为 1 个文件，
#' 于是 V5 永远报"通过 0 组 / 失败 0 组"——**一个从诞生起就空洞的检查**。
#' 正确分组键 = 去掉"类别目录 + 文件名"两级后的前缀。
prop_groups <- function(fs) {
  base <- fs[grepl("_prop\\.tif$", fs)]
  if (!length(base)) return(list())
  key <- vapply(base, function(p) {
    parts <- strsplit(gsub("\\\\", "/", p), "/", fixed = TRUE)[[1]]
    if (length(parts) < 3L) return(dirname(p))
    paste(parts[seq_len(length(parts) - 2L)], collapse = "/")
  }, "", USE.NAMES = FALSE)
  split(base, key)
}

check_composition <- function(files, tol = 1e-3) {
  acc <- NULL; nn <- 0L
  for (f in files) {
    r <- terra::rast(f)
    # 2026-10-19 修：terra::NAflag() 对浮点栅格一律返回 NaN，原写法永远跳过
    # 这段处理。改读 GDAL 声明的 nodata。
    nd <- file_nodata(f)
    x <- r
    if (!is.na(nd)) x <- terra::ifel(abs(r - nd) < 1e-6, NA, r)
    # NA -> 0 是为了把多层相加；但**判定时只在中国掩膜内（sum > 0）**
    x <- terra::ifel(is.na(x), 0, x)
    acc <- if (is.null(acc)) x else acc + x
    nn <- nn + 1L
  }
  # 2026-10-19 修（第二次）：不能用 global(min) —— 掩膜外 8 层全为 0，
  # 和的 min 必然是 0，dev = |0-1| = 1，把正确数据判成失败。
  # 只在中国掩膜内（acc > 0）判定，等价于原版的 `pos <- s > 0`。
  b <- terra::ifel(acc > 0,
                   terra::ifel(abs(acc - 1) > tol, 1L, 0L),
                   0L,
                   filename = tempfile(fileext = ".tif"), overwrite = TRUE,
                   datatype = "INT1U")
  bad <- as.numeric(terra::global(b, "sum", na.rm = TRUE)[1, 1])

  # 掩膜内的极值：先把 acc 在掩膜外置 NA，再取 min/max
  acc_m <- terra::ifel(acc > 0, acc, NA)
  g <- terra::global(acc_m, c("min", "max"), na.rm = TRUE)
  lo <- g[1, 1]; hi <- g[1, 2]
  dev <- if (is.finite(lo) && is.finite(hi)) max(abs(lo - 1), abs(hi - 1)) else NA_real_
  list(n = NA_integer_, bad = bad, maxdev = dev, nclass = nn)
}

# ---- V6：焦点一致性 -------------------------------------------------------
#' 对每组「基底 + 焦点」，检查焦点均值是否落在基底 [min, max] 内
#'
#' 2026-10-19 修：原实现有与 V4/V5 同类的两个问题：
#'   1) 用 `terra::NAflag()`——对浮点栅格一律返回 NaN，`if (!is.na(nd))` 恒为 FALSE，
#'      声明 nodata 从未被剔除；
#'   2) 用 `terra::values()` 把整层 19.7M 像元载入内存，满负荷时 `std::bad_alloc`。
#' 现改为 `file_nodata()` + 流式 `terra::global()`。
check_focal <- function(base_path, focal_paths, tol = 1e-4) {
  b <- terra::rast(base_path)
  nd <- file_nodata(base_path)
  if (!is.na(nd)) b <- terra::ifel(abs(b - nd) < 1e-6, NA, b)
  gb <- terra::global(b, c("min", "max"), na.rm = TRUE)
  lo <- gb[1, 1]; hi <- gb[1, 2]
  if (!is.finite(lo) || !is.finite(hi))
    return(list(ok = TRUE, bad = 0L, note = "base empty"))

  # 2026-10-19 修（第二次）：逐像元 `ifel(f > hi, ...)` 在满负荷下既慢又不可靠。
  # 改用**范围包含**判定：等权均值的必要条件是 焦点层的 [min, max] ⊆ 基底层的 [min, max]。
  # 这只需两次流式 global，且与 test_54/test_57 的判定一致。
  bad <- 0L; detail <- character(0)
  for (fp in focal_paths) {
    f <- terra::rast(fp)
    fnd <- file_nodata(fp)
    if (!is.na(fnd)) f <- terra::ifel(abs(f - fnd) < 1e-6, NA, f)
    gf <- terra::global(f, c("min", "max"), na.rm = TRUE)
    flo <- gf[1, 1]; fhi <- gf[1, 2]
    if (!is.finite(flo) || !is.finite(fhi)) next
    if (flo < lo - tol || fhi > hi + tol) {
      bad <- bad + 1L
      detail <- c(detail, sprintf("%s [%.6g,%.6g]", basename(fp), flo, fhi))
    }
  }
  list(ok = bad == 0L, bad = bad, lo = lo, hi = hi, detail = detail)
}

# ---- 主流程 ---------------------------------------------------------------
main <- function(mode = c("header", "full"), limit = NULL) {
  mode <- match.arg(mode)
  print_grid()
  fs <- list_layers()
  cat(sprintf("交付树层数: %d\n", length(fs)))
  if (!is.null(limit)) fs <- head(fs, limit)

  # V1/V2
  cat("\n=== V1 网格不变量 / V2 格式 ===\n")
  hdr <- lapply(fs, function(p) tryCatch(check_header(p), error = function(e)
    list(v1 = FALSE, v2 = FALSE, note = conditionMessage(e))))
  v1 <- vapply(hdr, function(h) isTRUE(h$v1), TRUE)
  v2 <- vapply(hdr, function(h) isTRUE(h$v2), TRUE)
  cat(sprintf("  V1 通过 %d / %d\n", sum(v1), length(fs)))
  cat(sprintf("  V2 通过 %d / %d\n", sum(v2), length(fs)))
  if (any(!v1)) { cat("  V1 失败样本:\n"); for (p in head(fs[!v1], 10)) cat("    ", p, "\n") }
  if (any(!v2)) { cat("  V2 失败样本:\n"); for (p in head(fs[!v2], 10)) cat("    ", p, "|", hdr[[which(fs==p)[1]]]$note, "\n") }

  if (mode == "header") {
    return(invisible(list(n = length(fs), v1 = sum(v1), v2 = sum(v2))))
  }

  # 2026-10-19 修：`limit` 原本把整个 fs 截断，导致 V5 只在几十层里找比例组，
  # 必然报"比例组数 0、通过 0 组"——一个**空洞的通过**（看起来全过，实际什么都没检）。
  # 现在 `limit` 只限制 V1/V2 的头部扫描，V3–V6 各自从**完整列表**抽样。
  fs_all <- if (is.null(limit) || is.na(limit)) fs else list_layers()

  # V3/V4（抽样）
  # 2026-10-19：60 层在满负荷时会导致进程被静默杀死；12 层足以发现系统性缺陷，
  # 且能保证校验跑完。全量校验应在**空闲机器**上进行（见 FINAL_VERIFICATION_REPORT §8）。
  # 2026-10-21：机器空闲时放宽样本。原先固定 12 层是为避免满载被静默杀死，
  # 但 12 层对 21,110 层的覆盖率仅 0.06%，不足以支撑"全量校验"的表述。
  # 现在 V3/V4 抽 48 层，并在结尾显式报告每个检查实际覆盖了多少。
  n_probe <- min(length(fs_all), 48L)
  probe <- oldest_first(fs_all)[round(seq(1, length(oldest_first(fs_all)), length.out = n_probe))]
  cat(sprintf("\n=== V3 掩膜合规 / V4 无效值编码（从 %d 层中抽样 %d 层）===\n",
              length(fs_all), n_probe))
  res34 <- lapply(probe, function(p) tryCatch(check_mask_and_nodata(p),
                 error = function(e) list(n_out = NA, n_bad = NA)))
  n_out <- vapply(res34, function(r) as.numeric(r$n_out), 0)
  n_bad <- vapply(res34, function(r) as.numeric(r$n_bad), 0)
  cat(sprintf("  V3 境外有效像元为 0 的层: %d / %d\n", sum(n_out == 0, na.rm = TRUE), n_probe))
  cat(sprintf("  V4 残留 nodata 值为 0 的层: %d / %d\n", sum(n_bad == 0, na.rm = TRUE), n_probe))
  if (any(is.na(n_bad))) cat(sprintf("  ⚠ %d 层无法读出声明 nodata，V4 未执行\n", sum(is.na(n_bad))))
  if (any(n_out > 0, na.rm = TRUE)) {
    cat("  V3 失败样本:\n")
    for (i in head(which(n_out > 0), 8)) cat(sprintf("    %s : %d 个境外有效像元\n", probe[i], n_out[i]))
  }

  # V5 组成恒等式
  cat("\n=== V5 组成恒等式 ===\n")
  groups <- prop_groups(fs_all)
  # 2026-10-19 修：原先"通过 0 组 / 失败 0 组"会看起来像通过，实际什么都没检。
  # 只挑**完整组**（成员数 >= 6，即至少 GLULC 的六类），并显式报告被跳过的目录数。
  ncomp <- vapply(groups, length, 0L)
  full_dirs <- names(groups)[ncomp >= 6L]
  # 取最旧的完整组（最可能已完成）
  full_dirs <- full_dirs[order(vapply(full_dirs, function(d) {
    mt <- file.info(groups[[d]])$mtime; if (all(is.na(mt))) NA else max(mt, na.rm=TRUE)
  }, 0), na.last = TRUE)]
  n_v5 <- min(12L, length(full_dirs))
  cat(sprintf("  比例组数: %d（其中完整组 %d；检查 %d 个）\n",
              length(groups), length(full_dirs), n_v5))
  v5pass <- 0L; v5fail <- 0L; v5skip <- 0L
  # 2026-10-21 \u4fee\uff1a\u539f\u6765\u7528 oldest_first() \u53d6\u6700\u65e7\u7684\u7ec4\uff0c
  # \u7ed3\u679c 12 \u7ec4\u5168\u662f glu1km\uff086 \u7c7b\uff09\u4e0e hlu1km\uff088 \u7c7b\uff09\uff0c
  # **\u4e00\u7ec4 CLCD \u4e5f\u6ca1\u68c0\u5230**\u2014\u2014\u800c CLCD \u662f\u4eca\u5929\u6700\u540e\u5199\u5165\u7684\u3001
  # \u4e5f\u662f\u8bba\u6587\u91cc\u62ff\u6765\u505a\u4e3b\u8bc1\u636e\u7684\u90a3\u4e00\u4e2a\u3002
  # \u6309 mtime \u6392\u5e8f\u7b49\u4e8e\u7cfb\u7edf\u6027\u5730\u6392\u9664\u6700\u65b0\u6570\u636e\u3002
  # \u6539\u4e3a\u6309\u4e3b\u9898\u5206\u5c42\u62bd\u6837\uff1a\u6bcf\u4e2a\u4e3b\u9898\u81f3\u5c11\u4e00\u7ec4\u3002
  # 2026-10-21 第二次修：第一版用的是**主题**（lulc/bioclim/...）作分层键，
  # 但比例组全部属于 lulc，于是 head() 仍取前 12 个（glu1km + hlu1km），
  # 依然一组 CLCD 都没检到。正确的分层键是 **theme/dataset**。
  grp_key <- function(d) {
    x <- sub("^.*?covariates/glo/", "", d)     # "lulc/clcd/2008"
    p <- strsplit(x, "/")[[1]]
    if (length(p) >= 2) paste(p[1], p[2], sep = "/") else p[1]
  }
  pick_by_theme <- function(dirs, k) {
    g  <- vapply(dirs, grp_key, "")
    ug <- unique(g)
    # 先每个数据集取 1 组，保证覆盖；再轮转补齐到 k 组，
    # 让组数多的数据集（clcd 234 / hlu1km 3688）也能多检几组。
    sel <- unlist(lapply(ug, function(t) head(dirs[g == t], 1L)))
    pool <- lapply(ug, function(t) dirs[g == t][-1])
    names(pool) <- ug
    while (length(sel) < k && any(lengths(pool) > 0L)) {
      for (t in ug) {
        if (length(sel) >= k) break
        if (length(pool[[t]])) { sel <- c(sel, pool[[t]][1]); pool[[t]] <- pool[[t]][-1] }
      }
    }
    head(sel, k)
  }
  for (d in pick_by_theme(full_dirs, n_v5)) {
    g <- groups[[d]]
    r <- tryCatch(check_composition(g), error = function(e) NULL)
    if (is.null(r) || is.na(r$maxdev)) { v5skip <- v5skip + 1L; next }
    if (r$bad == 0) { v5pass <- v5pass + 1L; cat(sprintf("  PASS %-28s %d 类, max|sum-1| = %.2e\n",
        basename(d), r$nclass, r$maxdev)) } else {
      v5fail <- v5fail + 1L
      cat(sprintf("  FAIL %s : %d 类, %d 像元超差, max|sum-1| = %.3e\n",
                  basename(d), r$nclass, r$bad, r$maxdev))
    }
  }
  cat(sprintf("  通过 %d 组 / 失败 %d 组 / 跳过 %d 组\n", v5pass, v5fail, v5skip))
  if (v5pass == 0L && v5fail == 0L) cat("  ⚠ 未检查任何完整组，V5 结论为空\n")

  # V6 焦点一致性（抽样 20 组）
  cat("\n=== V6 焦点一致性（抽样）===\n")
  bases <- fs_all[grepl("\\.tif$", fs_all) & !grepl("_f[0-9]+\\.tif$", fs_all)]
  cand <- bases[vapply(bases, function(b) {
    stem <- sub("\\.tif$", "", b)
    any(file.exists(paste0(stem, FOCAL_SPEC()$suffix, ".tif")))
  }, TRUE)]
  cat(sprintf("  有焦点变体的基底: %d\n", length(cand)))
  n_v6 <- min(18L, length(cand))
  cat(sprintf("  检查 %d 个\n", n_v6))
  sel <- head(oldest_first(cand), n_v6)
  v6ok <- 0L
  for (b in sel) {
    stem <- sub("\\.tif$", "", b)
    fps <- paste0(stem, FOCAL_SPEC()$suffix, ".tif")
    fps <- fps[file.exists(fps)]
    if (!length(fps)) next
    r <- tryCatch(check_focal(b, fps), error = function(e) list(ok = FALSE))
    if (isTRUE(r$ok)) v6ok <- v6ok + 1L else
      cat(sprintf("  FAIL %s : %d 个像元越界 [%g, %g]\n", basename(b), r$bad, r$lo, r$hi))
  }
  cat(sprintf("  V6 通过 %d / %d\n", v6ok, length(sel)))

  # 覆盖度汇总：让"全量校验"这个说法可以被实际数字检验
  cat("\n=== 覆盖度汇总 ===\n")
  cat(sprintf("  V1/V2  全量        %d / %d 层\n", length(fs), length(fs)))
  cat(sprintf("  V3/V4  抽样        %d / %d 层 (%.2f%%)\n",
              n_probe, length(fs_all), 100 * n_probe / length(fs_all)))
  cat(sprintf("  V5     抽样        %d / %d 个完整比例组\n", v5pass + v5fail, length(full_dirs)))
  cat(sprintf("  V6     抽样        %d / %d 个含焦点变体的基底\n", v6ok, length(cand)))
  cat("  → 论文中不得把 V3–V6 表述为全量；V1/V2 才是全量。\n")

  invisible(list(n = length(fs), v1 = sum(v1), v2 = sum(v2),
                 v3 = sum(n_out == 0, na.rm = TRUE), v4 = sum(n_bad == 0, na.rm = TRUE),
                 v5pass = v5pass, v5fail = v5fail, v6 = v6ok))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) a[1] else "header",
       if (length(a) >= 2) as.integer(a[2]) else NULL)
}
