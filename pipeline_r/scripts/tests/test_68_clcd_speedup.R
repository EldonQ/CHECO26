# R/tests/test_68_clcd_speedup.R
# 探索 CLCD 提速方案：缩小 band 让 one-hot 留在内存，省掉落盘的 40.9 s
#
# 现有：band=25 行，segregate 出 9 层 float64（9.7 GB）→ 写 INT1U 临时（40.9 s）→ project
# 候选：band=10 行，segregate 出 9 层 float64（3.9 GB）→ 直接 project（不落盘）
#       band=15 行 → 5.8 GB
#
# 注意：必须验证与现有实现等价（max|d| = 0）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd.R"), envir = .ing)

codes <- as.integer(names(.ing$CLCD_LEGEND))
YEAR <- 2010L
r <- terra::rast(.ing$clcd_src(YEAR))
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0
g <- GRID()

#' 不落盘版本：band 较小，9 层 one-hot 留在内存直接 project
band_props_inmem <- function(r, r0, nr, codes, margin_cells = 2L) {
  sub <- .ing$band_template(r0, nr)
  win <- terra::ext(sub) + margin_cells * g$res
  src <- terra::crop(r, win, snap = "out")
  v <- terra::values(src, mat = FALSE)
  v[is.na(v) | !(v %in% codes)] <- NA
  terra::values(src) <- v
  onehot <- terra::segregate(src, classes = codes, keep = FALSE, other = 0)
  out <- terra::project(onehot, sub, method = terra_method("average"), align = FALSE)
  rm(onehot); gc(verbose = FALSE)
  out
}

run <- function(label, nr, fn) {
  # 用同一段的起始行，保证可比
  t <- Sys.time()
  o <- tryCatch(fn(nr), error = function(e) { cat("   ", label, "失败:", conditionMessage(e), "\n"); NULL })
  s <- as.numeric(difftime(Sys.time(), t, units = "secs"))
  if (is.null(o)) return(NULL)
  cat(sprintf("  %-28s %6.1f s   %d 层\n", label, s, terra::nlyr(o)))
  list(out = o, s = s)
}

cat("=== 方案对比（同一段：row0=1000）===\n\n")

# 基线：现有实现，band=25 + 落盘
a <- run("现有 band=25 + 落盘", 25L, function(nr) .ing$band_props(r, 1000L, nr, codes, tag = "base"))

# 候选：不落盘，不同 band
b <- run("内存 band=10 不落盘", 10L, function(nr) band_props_inmem(r, 1000L, nr, codes))
c_ <- run("内存 band=15 不落盘", 15L, function(nr) band_props_inmem(r, 1000L, nr, codes))
d <- run("内存 band=25 不落盘", 25L, function(nr) band_props_inmem(r, 1000L, nr, codes))

# 等价性：只比较 band=10 与基线的前 10 行
if (!is.null(b) && !is.null(a)) {
  cat("\n=== 等价性（内存 band=10 vs 现有 band=25，取前 10 行）===\n")
  worst <- 0; nasame <- TRUE
  for (k in seq_along(codes)) {
    va <- terra::values(a$out[[k]], mat = FALSE)
    vb <- terra::values(b$out[[k]], mat = FALSE)
    ncol_out <- terra::ncol(a$out)
    # 基线前 10 行 = 前 10*ncol 个值（terra 按行优先）
    idx <- seq_len(10L * ncol_out)
    xa <- va[idx]; xb <- vb
    if (length(xb) == length(idx)) {
      if (!identical(is.na(xa), is.na(xb))) nasame <- FALSE
      both <- !is.na(xa) & !is.na(xb)
      worst <- max(worst, if (any(both)) max(abs(xa[both] - xb[both])) else 0)
    }
  }
  cat(sprintf("  NA 结构一致: %s ; 最大 max|d| = %.3e\n", nasame, worst))
}

# 年化估算
cat("\n=== 年化（按实测外推）===\n")
if (!is.null(a)) cat(sprintf("  现有       : %.2f h/年/分片\n", ceiling(4062/25)*a$s/3600))
if (!is.null(b)) cat(sprintf("  内存 band10: %.2f h/年/分片  (%.2fx)\n",
                             ceiling(4062/10)*b$s/3600, (ceiling(4062/25)*a$s)/(ceiling(4062/10)*b$s)))
if (!is.null(c_)) cat(sprintf("  内存 band15: %.2f h/年/分片  (%.2fx)\n",
                              ceiling(4062/15)*c_$s/3600, (ceiling(4062/25)*a$s)/(ceiling(4062/15)*c_$s)))
if (!is.null(d)) cat(sprintf("  内存 band25: %.2f h/年/分片  (%.2fx)\n",
                             ceiling(4062/25)*d$s/3600, a$s/d$s))
