# R/tools/check_clcd_year.R
# clcd 单年份结果的全面质检（30 m -> 1 km 聚合）
#
# 检查分六组：
#   A 结构：网格/CRS/分辨率/extent/数据类型/nodata 是否**声明且存储**
#   B 值域：[0,1]，无负值，无数值型 nodata 混入
#   C 组成：九类之和 = 1（逐像元）
#   D 掩膜：境外必须全为 nodata；境内有效像元数应与 mask_china 一致
#   E 接缝：25 行带边界处不应出现台阶（banding 是分段计算最容易出的错）
#   F **独立复算**：用 exactextractr 面积加权重算一小块，与存储层比对
#     —— 这是唯一能证明"30 m -> 1 km 聚合本身正确"的检查，
#        A–E 都只能证明"数据自洽"，不能证明"算得对"。
#
# 用法：
#   Rscript R/tools/check_clcd_year.R 2000
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
suppressPackageStartupMessages(library(exactextractr))

CLCD_CLASSES <- c("cropland", "forest", "shrub", "grassland", "water",
                  "snowice", "barren", "impervious", "wetland")

ok <- 0L; bad <- 0L; warn <- 0L
chk <- function(label, cond, detail = "") {
  if (isTRUE(cond)) { cat(sprintf("  PASS  %s%s\n", label, if (nzchar(detail)) paste0("  ", detail) else "")); ok <<- ok + 1L }
  else { cat(sprintf("  FAIL  %s  %s\n", label, detail)); bad <<- bad + 1L }
}
ntc <- function(label, detail) { cat(sprintf("  note  %s  %s\n", label, detail)); warn <<- warn + 1L }

main <- function(year) {
  g <- GRID()
  paths <- vapply(CLCD_CLASSES, function(cn)
    layer_path(c("glo", "lulc", "clcd", as.character(year), cn), "_prop"), "")
  cat(sprintf("=== clcd %d 质检（9 类）===\n\n", year))
  if (!all(file.exists(paths))) {
    cat(sprintf("  缺 %d 层，无法检查\n", sum(!file.exists(paths)))); return(invisible(NULL))
  }
  rs <- lapply(paths, terra::rast)

  # ---------- A 结构 ----------
  cat("A 结构\n")
  chk("9 层网格一致", length(unique(vapply(rs, function(r) paste(terra::res(r), collapse="x"), ""))) == 1L)
  chk("分辨率 = 1000 m", all(vapply(rs, function(r) isTRUE(all.equal(terra::res(r), c(1000, 1000))), TRUE)))
  # 注意：dim() 返回 double，用 identical() 比较整型常量会**永远为 FALSE**
  # （2026-10-20 首跑踩过：尺寸正确却报 FAIL）。
  chk("尺寸 = 4062 行 x 4861 列",
      all(vapply(rs, function(r) all(dim(r)[1:2] == c(4062, 4861)), TRUE)),
      sprintf("实际 %s", paste(dim(rs[[1]])[1:2], collapse = " x ")))
  ext_g <- as.vector(terra::ext(g$rast))
  chk("extent 与模板一致",
      all(vapply(rs, function(r) isTRUE(all.equal(as.vector(terra::ext(r)), ext_g)), TRUE)))
  chk("CRS 与模板一致",
      all(vapply(rs, function(r) terra::same.crs(r, g$rast), TRUE)))
  chk("数据类型为 float32",
      all(vapply(rs, function(r) terra::datatype(r) %in% c("FLT4S"), TRUE)),
      unique(vapply(rs, terra::datatype, ""))[[1]])

  # nodata：必须**声明且存储**（terra::NAflag 对浮点一律返回 NaN，故读描述）
  # terra::NAflag() 对浮点栅格一律返回 NaN，必须从 describe() 的文本里解析。
  # 与 R/11_validate.R 的 file_nodata() 同一做法（这里不 source 那个文件，避免副作用）。
  file_nodata_local <- function(p) {
    d <- tryCatch(terra::describe(p, print = FALSE), error = function(e) character())
    line <- grep("NoData Value", d, value = TRUE, ignore.case = TRUE)
    if (!length(line)) return(NA_real_)
    suppressWarnings(as.numeric(sub("^.*?NoData Value\\s*=\\s*", "", trimws(line[1]))))
  }
  nd <- vapply(paths, file_nodata_local, 0)
  chk("nodata 已在元数据声明为 -9999",
      all(is.finite(nd) & nd == -9999), paste(unique(nd), collapse = " | "))

  # ---------- B 值域 ----------
  cat("\nB 值域\n")
  stats <- lapply(rs, function(r) terra::global(r, c("min", "max"), na.rm = TRUE))
  mins <- vapply(stats, function(s) s[[1]], 0); maxs <- vapply(stats, function(s) s[[2]], 0)
  chk("min >= 0", all(mins >= -1e-9), sprintf("最小 %.3e", min(mins)))
  chk("max <= 1 + 1e-6", all(maxs <= 1 + 1e-6), sprintf("最大 %.6f", max(maxs)))
  chk("无 -9999 混入有效值", all(mins > -1), sprintf("最小 %.3e", min(mins)))
  gm <- vapply(rs, function(r) terra::global(r, "mean", na.rm = TRUE)[[1]], 0)
  cat(sprintf("  各类全国均值: %s\n",
              paste(sprintf("%s=%.4f", CLCD_CLASSES, gm), collapse = " ")))
  cat(sprintf("  九类均值之和: %.6f（应 ≈ 1）\n", sum(gm)))

  # ---------- C 组成 ----------
  cat("\nC 组成恒等式\n")
  acc <- NULL
  for (r in rs) {
    v <- terra::values(r, mat = FALSE)
    acc <- if (is.null(acc)) ifelse(is.na(v), 0, v) else acc + ifelse(is.na(v), 0, v)
  }
  valid <- !is.na(terra::values(rs[[1]], mat = FALSE))
  dev <- abs(acc[valid] - 1)
  chk("max |Σ-1| < 1e-6", max(dev) < 1e-6, sprintf("实测 %.3e", max(dev)))
  cat(sprintf("  有效像元 %s ; 均值 %.9f\n", format(sum(valid), big.mark = ","), mean(acc[valid])))

  # ---------- D 掩膜 ----------
  cat("\nD 掩膜\n")
  m <- china_mask()
  mv <- terra::values(m, mat = FALSE)
  in_china <- !is.na(mv) & mv == 1
  raw1 <- terra::values(rs[[1]], mat = FALSE)

  # 真正的不变量是**单向**的：有效像元必须都在境内。
  # 不能要求数量相等——2026-10-20 实测 clcd 比 mask 少 18,319 个（0.19%），
  # 抽样查明这些 1 km 格的源窗口内**有效源像元为 0**（CLCD 栅格未覆盖到矢量边界，
  # 集中在黑龙江北部）。源在那里没有数据，层存 NA 是正确行为，不应伪造 0。
  chk("所有有效像元都在境内（无境外值）", !any(!is.na(raw1) & !in_china),
      sprintf("境外有效 %d 个", sum(!is.na(raw1) & !in_china)))
  chk("境外全部为 nodata", all(is.na(raw1[!in_china])),
      sprintf("境外有效占比 %.4f%%", 100*mean(!is.na(raw1[!in_china]))))
  gap <- sum(in_china) - sum(valid)
  if (gap > 0) ntc("境内无源数据像元", sprintf("%d 个（%.2f%%），源于 CLCD 栅格覆盖不及矢量边界",
                                              gap, 100*gap/sum(in_china)))

  # ---------- E 接缝 ----------
  cat("\nE 带接缝（25 行分段计算）\n")
  v1 <- terra::values(rs[[1]], mat = FALSE)
  mat1 <- matrix(v1, nrow = 4062, ncol = 4861, byrow = TRUE)
  # 相邻行差分的绝对值，在 25 的整数倍行处是否异常大
  d <- abs(diff(mat1))
  rmean <- rowMeans(d, na.rm = TRUE)
  bnd <- which(seq_len(nrow(d)) %% 25L == 0L)
  inner <- setdiff(seq_len(nrow(d)), bnd)
  chk("带边界行差 ≈ 非边界行差",
      abs(mean(rmean[bnd], na.rm=TRUE) - mean(rmean[inner], na.rm=TRUE)) <
        0.05 * mean(rmean[inner], na.rm=TRUE),
      sprintf("边界 %.5f vs 内部 %.5f", mean(rmean[bnd], na.rm=TRUE), mean(rmean[inner], na.rm=TRUE)))

  # ---------- F 独立复算 ----------
  cat("\nF 独立复算（exactextractr，不依赖本流水线的聚合代码）\n")
  # 2026-10-20 两次踩坑后改为最稳的形态：只测**一个**混合像元。
  #   坑一：拿网格模板当数据读 -> 全 NA -> 循环不执行 -> 空转 PASS
  #   坑二：硬编码窗口在国界外 -> 全 NA -> 同样空转
  # 现在：用 mask 与 cropland 比例共同定位一个境内混合像元，
  #       只对这一个 1 km 格建多边形，exact_extract 算九类面积比，逐一比对。
  src_path <- file.path(PATH_ARCHIVE(), "clcd-albert",
                        sprintf("CLCD_v01_%d_albert.tif", as.integer(year)))
  src <- terra::rast(src_path)
  if (is.na(terra::NAflag(src))) terra::NAflag(src) <- 0

  cv <- terra::values(rs[[1]], mat = FALSE)
  mv2 <- terra::values(china_mask(), mat = FALSE)
  cand <- which(!is.na(cv) & cv > 0.25 & cv < 0.55 & !is.na(mv2) & mv2 == 1)
  if (!length(cand)) { cat("  找不到境内混合像元，跳过\n") } else {
    pick <- cand[order(abs(cand - length(cv) / 2))][1]
    one <- g$rast
    terra::values(one) <- NA_real_
    one[pick] <- 1
    poly <- sf::st_as_sf(terra::as.polygons(one, values = FALSE, na.rm = TRUE))
    fine <- terra::crop(src, terra::ext(poly) + 100, snap = "out")
    ex <- exactextractr::exact_extract(fine, poly, fun = NULL, progress = FALSE)[[1]]
    vv <- ex[[1]]; ww <- ex[[ncol(ex)]]
    keep <- !is.na(vv) & vv %in% seq_along(CLCD_CLASSES)
    wsum <- sum(ww[keep])
    xy <- terra::xyFromCell(g$rast, pick)
    cat(sprintf("  测试格 @ (%.0f, %.0f)，源像元 %d 个（有效 %d），覆盖和 %.4f km²\n",
                xy[1], xy[2], nrow(ex), sum(keep), wsum))
    worst <- 0; ncmp <- 0L
    for (j in seq_along(CLCD_CLASSES)) {
      ref <- sum(ww[keep & vv == j]) / wsum
      got <- terra::values(rs[[j]], mat = FALSE)[pick]
      if (is.finite(got)) {
        d <- abs(ref - got)
        worst <- max(worst, d); ncmp <- ncmp + 1L
        if (d > 1e-4) cat(sprintf("    %-11s ref=%.6f stored=%.6f d=%.2e\n",
                                  CLCD_CLASSES[j], ref, got, d))
      }
    }
    chk("独立复算非空转（比较次数 = 9）", ncmp == 9L, sprintf("%d 次", ncmp))
    chk("独立复算与存储层一致（max|d| < 1e-4）", worst < 1e-4, sprintf("max|d| = %.3e", worst))
  }

  # ---------- 亚公里组成证据 ----------
  # 2026-10-20 修：原版只算"任一类有中间值"，却与 hlu1km 的**单类**数字 1.97%
  # 相比，断言阈值也按"任一类"标定（pct > 50）。九类求并必然远大于单类，
  # 这个比较不成立。现改为**逐类均值**做主判据（与 hlu1km 八类均值 5.8% 同口径），
  # "任一类"仅作参考信息、不参与判定。
  cat("\nG 亚公里组成（比例是否真的连续）\n")
  mids <- numeric(0); mid_any <- rep(FALSE, sum(valid))
  for (r in rs) {
    v <- terra::values(r, mat = FALSE)[valid]
    is_mid <- (v > 1e-6 & v < 1 - 1e-6)
    mids <- c(mids, 100 * mean(is_mid))
    mid_any <- mid_any | is_mid
  }
  mid_mean <- mean(mids)
  mid_any_pct <- 100 * mean(mid_any)
  cat(sprintf("  逐类中间值均值 : %.1f%%   <- 与 hlu1km 八类均值 5.8%% 同口径\n", mid_mean))
  cat(sprintf("  任一类中间值   : %.1f%%   <- 九类求并，不参与判定\n", mid_any_pct))
  cat(sprintf("  逐类明细       : %s\n",
              paste(sprintf("%s=%.0f%%", CLCD_CLASSES, mids), collapse = " ")))
  chk("逐类中间值均值 > 2x hlu1km 的 5.8%（证明 30 m 带来真实亚公里组成）",
      mid_mean > 2 * 5.8, sprintf("%.1f%%", mid_mean))

  cat(sprintf("\n=== 汇总: PASS %d / FAIL %d / note %d ===\n", ok, bad, warn))
  invisible(list(ok = ok, bad = bad))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) as.integer(a[1]) else 2000L)
}
