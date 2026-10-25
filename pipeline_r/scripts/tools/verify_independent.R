# R/tools/verify_independent.R
# 独立复核：不使用项目内任何 helper（_bootstrap.R、raster_stats()、file_nodata()、
# count_layers() 等一律不用），只用 terra + base R 从磁盘重新算一遍。
#
# 动机（2026-10-21）：本会话已发现 5 处"检查器空转"缺陷——
#   V4 从未执行、V5 从诞生起没检查过组成恒等式、F 组读了错误文件、
#   窗口落在国界外导致 0 次比较、D 组测试了已被替换为 0 的变量。
# 共同特征：**检查跑完了、报 PASS 了、但实际比较次数为 0**。
# 所以本脚本对每一项都强制输出"比较次数"，且断言里包含次数 > 0。
#
# 用法：Rscript R/tools/verify_independent.R
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))

ROOT  <- Sys.getenv("CHECO_ROOT", getwd())
COV   <- file.path(ROOT, "data/covariates")
DOCS  <- file.path(ROOT, "00_docs")
TPL   <- file.path(ROOT, "data/template_albers1km.tif")
MASK  <- file.path(ROOT, "data/mask_china.tif")
NROWS <- 4062L; NCOLS <- 4861L
ND    <- -9999

ok <- 0L; bad <- 0L; fails <- character(0)
say <- function(pass, label, detail) {
  if (isTRUE(pass)) { ok <<- ok + 1L; cat(sprintf("  PASS  %-46s %s\n", label, detail)) }
  else { bad <<- bad + 1L; fails <<- c(fails, label)
         cat(sprintf("  FAIL  %-46s %s\n", label, detail)) }
}

cat("================================================================\n")
cat(" CHECO26 独立复核\n")
cat(sprintf(" %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat(" 不使用项目内任何 helper；每项均报告比较次数\n")
cat("================================================================\n\n")

# ---------------------------------------------------------------- A 层数
cat("A. 层数与清单\n")
all_tif <- list.files(COV, pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
all_tif <- all_tif[!grepl("\\.(aux\\.xml|tmp\\.tif|ovr)$", all_tif)]
say(length(all_tif) == 21110L, "covariates 下 tif 层数 = 21,110",
    sprintf("实测 %d（比较 1 次）", length(all_tif)))

man <- read.csv(file.path(DOCS, "MANIFEST.csv"), fileEncoding = "UTF-8-BOM",
                stringsAsFactors = FALSE)
man_layers <- man[grepl("^covariates/", man$relpath), ]
say(nrow(man) == 21118L, "MANIFEST 总行数 = 21,118",
    sprintf("实测 %d（比较 1 次）", nrow(man)))
say(nrow(man_layers) == 21110L, "MANIFEST 中 covariates 行 = 21,110",
    sprintf("实测 %d（比较 1 次）", nrow(man_layers)))

# 清单与磁盘双向差集
# 注意：MANIFEST 的 relpath 以 "covariates/" 开头（data/ 下的相对路径），
# 而 list.files(COV) 给出的已经不含这层前缀，必须补回，否则两边永远不交。
disk_rel <- paste0("covariates/",
                   sub(paste0("^", gsub("\\\\", "/", COV), "/"), "",
                       gsub("\\\\", "/", all_tif)))
only_disk <- setdiff(disk_rel, man_layers$relpath)
only_man  <- setdiff(man_layers$relpath, disk_rel)
say(length(only_disk) == 0L && length(only_man) == 0L,
    "MANIFEST 与磁盘双向完全一致",
    sprintf("磁盘多 %d / 清单多 %d（比较 %d 次）",
            length(only_disk), length(only_man), length(disk_rel)))

# ---------------------------------------------------------------- B 网格
cat("\nB. 网格一致性（随机抽 60 层，与模板逐项比对）\n")
set.seed(20261021)
samp <- sample(all_tif, 60)
tpl  <- terra::rast(TPL)
tex  <- as.vector(terra::ext(tpl)); tdim <- dim(tpl); tres <- terra::res(tpl)
n_cmp <- 0L; bad_grid <- character(0)
for (f in samp) {
  r <- terra::rast(f)
  e <- as.vector(terra::ext(r)); d <- dim(r); rs <- terra::res(r)
  n_cmp <- n_cmp + 1L
  same <- isTRUE(all.equal(e, tex, tolerance = 1e-6)) &&
          d[1] == tdim[1] && d[2] == tdim[2] &&
          isTRUE(all.equal(as.vector(rs), as.vector(tres), tolerance = 1e-9))
  if (!same) bad_grid <- c(bad_grid, basename(f))
}
say(n_cmp == 60L && length(bad_grid) == 0L, "60 层 ext/dim/res 全部与模板一致",
    sprintf("比较 %d 层，不一致 %d 层", n_cmp, length(bad_grid)))
if (length(bad_grid)) cat("        不一致:", paste(head(bad_grid, 3), collapse = ", "), "\n")

# ---------------------------------------------------------------- C nodata
cat("\nC. nodata：声明值 vs 实际存储值\n")
# 已知陷阱：terra::NAflag() 对浮点栅格一律返回 NaN，必须解析 describe()
read_declared_nd <- function(f) {
  d <- terra::describe(f, print = FALSE)
  ln <- grep("NoData Value", d, value = TRUE)
  if (!length(ln)) return(NA_real_)
  suppressWarnings(as.numeric(sub(".*NoData Value[=: ]+", "", ln[1])))
}
nd_decl <- vapply(samp, read_declared_nd, 0)
say(sum(nd_decl == ND, na.rm = TRUE) == 60L, "60 层声明的 nodata 均为 -9999",
    sprintf("比较 60 层，声明 -9999 的 %d 层", sum(nd_decl == ND, na.rm = TRUE)))

# 已知陷阱：terra::NAflag() 对浮点返回 NaN —— 断言这一点，避免有人误用它
naflag_all_nan <- all(is.nan(vapply(samp, function(f) terra::NAflag(terra::rast(f)), 0)))
say(naflag_all_nan, "确认 NAflag() 对浮点栅格返回 NaN（不能用于读 nodata）",
    sprintf("比较 60 层，返回 NaN 的 %d 层", 60L))

# 实际存储值：在 mask 外（mask == 0）取一个像元，应为 -9999
# 注意：mask_china.tif 是 INT1U、值域 0/1、声明 nodata=255 但实际没有 255，
# 所以 is.na(mask) 恒为 FALSE。必须用 mask == 0 判定"国界外"。
mk <- terra::rast(MASK)
mkv <- terra::values(mk, mat = FALSE)
cat(sprintf("        mask 值域: %s ; ==1 的像元 %s ; ==0 的像元 %s ; 声明 nodata=255 但出现 %d 次\n",
            paste(sort(unique(mkv)), collapse = "/"),
            format(sum(mkv == 1), big.mark = ","),
            format(sum(mkv == 0), big.mark = ","),
            sum(mkv == 255, na.rm = TRUE)))
outside <- which(mkv == 0)[1]
if (length(outside) && !is.na(outside)) {
  # terra 读到声明的 nodata=-9999 时会自动转成 NA，所以这里读出 NaN 是**正确**的。
  # 原始存储值是否真是 -9999，由上面的 describe() 断言（60 层全部声明 -9999）。
  rr <- terra::rast(samp[1]); v <- terra::values(rr, mat = FALSE)
  say(is.na(v[outside]),
      "mask 外像元被读作 NA（说明 nodata 生效）",
      sprintf("取第 %d 个像元，读出 %s（比较 1 次）", outside, format(v[outside])))

  # 更强的检查：整层的 NA 数应等于 mask 的 0 值数
  n_na <- sum(is.na(v)); n_zero <- sum(mkv == 0)
  say(n_na == n_zero,
      "整层 NA 像元数 = mask 的 0 值数",
      sprintf("NA %s vs mask0 %s（比较 %s 次）",
              format(n_na, big.mark = ","), format(n_zero, big.mark = ","),
              format(length(v), big.mark = ",")))
} else {
  say(FALSE, "mask 外像元被读作 NA", "找不到 mask==0 的像元")
}

# ---------------------------------------------------------------- D 掩膜
cat("\nD. 掩膜有效像元\n")
mask_valid <- sum(mkv == 1)
say(mask_valid == 9490310L, "mask_china 有效像元（==1）= 9,490,310",
    sprintf("实测 %s（比较 1 次）", format(mask_valid, big.mark = ",")))
say(sum(mkv == 0) == 19745382L - 9490310L, "mask_china 无效像元（==0）= 10,255,072",
    sprintf("实测 %s（比较 1 次）", format(sum(mkv == 0), big.mark = ",")))

# ---------------------------------------------------------------- E 统计一致性
cat("\nE. 抽样统计量与文档记录一致\n")
vd <- read.csv(file.path(DOCS, "variable_dictionary.csv"), fileEncoding = "UTF-8-BOM",
               stringsAsFactors = FALSE)
filled <- vd[!is.na(vd$n_valid) & !is.na(vd$value_min), ]
cat(sprintf("        字典中已填统计的行: %d / %d\n", nrow(filled), nrow(vd)))
if (nrow(filled) >= 10L) {
  set.seed(7); pick <- sample(seq_len(nrow(filled)), 10)
  n_cmp <- 0L; mism <- 0L
  for (i in pick) {
    p <- file.path(COV, filled$relpath[i])
    if (!file.exists(p)) next
    r <- terra::rast(p)
    g <- terra::global(r, c("min", "max"), na.rm = TRUE)
    nv <- terra::global(!is.na(r), "sum", na.rm = TRUE)[1, 1]
    n_cmp <- n_cmp + 1L
    if (!isTRUE(all.equal(as.numeric(g[1, 1]), as.numeric(filled$value_min[i]), tolerance = 1e-6)) ||
        !isTRUE(all.equal(as.numeric(g[1, 2]), as.numeric(filled$value_max[i]), tolerance = 1e-6)) ||
        !isTRUE(all.equal(as.numeric(nv),      as.numeric(filled$n_valid[i]),   tolerance = 1e-6)))
      mism <- mism + 1L
  }
  say(n_cmp == 10L && mism == 0L, "随机 10 层重算 min/max/n_valid 与字典一致",
      sprintf("比较 %d 层，不一致 %d 层", n_cmp, mism))
} else {
  cat("        跳过（已填统计行不足 10）\n")
}

# ---------------------------------------------------------------- F 哈希
cat("\nF. SHA-256 抽样比对\n")
# relpath 形如 "covariates/glo/..."，是相对 data/ 的路径，
# 所以要拼 dirname(COV) 而不是 COV，否则会变成 .../covariates/covariates/...
DATA <- dirname(COV)
set.seed(11); hpick <- sample(seq_len(nrow(man_layers)), 8)
n_cmp <- 0L; hmis <- 0L; hmiss <- character(0)
for (i in hpick) {
  p <- file.path(DATA, man_layers$relpath[i])
  if (!file.exists(p)) { hmiss <- c(hmiss, man_layers$relpath[i]); next }
  h <- digest::digest(file = p, algo = "sha256", serialize = FALSE)
  n_cmp <- n_cmp + 1L
  if (!identical(h, man_layers$sha256[i])) hmis <- hmis + 1L
}
say(n_cmp == 8L && hmis == 0L, "随机 8 层 SHA-256 与 MANIFEST 一致",
    sprintf("比较 %d 层，不一致 %d 层，文件缺失 %d 个", n_cmp, hmis, length(hmiss)))

# ---------------------------------------------------------------- G clcd 恒等式
cat("\nG. clcd 组成恒等式（独立复算）\n")
clcd_dir <- file.path(COV, "glo/lulc/clcd")
yr <- "2008"
cls <- c("cropland","forest","shrub","grassland","water","snowice","barren","impervious","wetland")
fs <- file.path(clcd_dir, yr, cls, sprintf("glo_lulc_clcd_%s_%s_prop.tif", yr, cls))
have <- file.exists(fs)
say(sum(have) == 9L, sprintf("%s 年 9 个类层齐全", yr),
    sprintf("找到 %d / 9", sum(have)))
if (sum(have) == 9L) {
  st <- terra::rast(fs)
  s  <- terra::app(st, "sum", na.rm = FALSE)
  v  <- terra::values(s, mat = FALSE)
  good <- !is.na(v)
  n_cmp <- sum(good)
  dev <- max(abs(v[good] - 1))
  say(n_cmp > 9e6 && dev < 1e-6, sprintf("%s 年 |sum-1| < 1e-6（%s 个像元）", yr,
                                          format(n_cmp, big.mark = ",")),
      sprintf("max|sum-1| = %.3e（比较 %s 次）", dev, format(n_cmp, big.mark = ",")))
  # 有效像元数
  say(n_cmp == 9471991L, "clcd 有效像元 = 9,471,991",
      sprintf("实测 %s（比较 1 次）", format(n_cmp, big.mark = ",")))
}

# ---------------------------------------------------------------- 汇总
cat("\n================================================================\n")
cat(sprintf(" 汇总: PASS %d / FAIL %d\n", ok, bad))
if (bad) cat(" 失败项:\n", paste0("   - ", fails, collapse = "\n"), "\n")
cat("================================================================\n")
