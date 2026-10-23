# R/tests/test_67_clcd_streaming.R
# 验证"逐类流式"实现与现有 band_props 是否等价，并测量提速
#
# 现有实现：segregate → 9 层 float64（9.7 GB）→ 写 INT1U 临时（41 s）→ project
# 新实现  ：对每个类单独 ifel → 1 层 → project → 收集
#          每步峰值仅 1 层（1.1 GB），无需落盘
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd.R"), envir = .ing)

codes <- as.integer(names(.ing$CLCD_LEGEND))

#' 逐类流式实现（候选方案）
band_props_stream <- function(r, r0, nr, codes, margin_cells = 2L) {
  g <- GRID()
  sub <- .ing$band_template(r0, nr)
  win <- terra::ext(sub) + margin_cells * g$res
  src <- terra::crop(r, win, snap = "out")

  v <- terra::values(src, mat = FALSE)
  v[is.na(v) | !(v %in% codes)] <- NA
  terra::values(src) <- v

  outs <- vector("list", length(codes))
  for (k in seq_along(codes)) {
    # src == code_k 为 NA 时 ifel 自动给 NA，与 segregate + other=0 的 NA 语义一致
    x <- terra::ifel(src == codes[k], 1, 0)
    outs[[k]] <- terra::project(x, sub, method = terra_method("average"), align = FALSE)
    rm(x)
  }
  terra::rast(outs)
}

YEAR <- 2010L
r <- terra::rast(.ing$clcd_src(YEAR))
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0

cat(sprintf("=== 对比：year=%d, 同一带（row0=1000, 25 行）===\n\n", YEAR))

t0 <- Sys.time()
ref <- .ing$band_props(r, 1000L, 25L, codes, tag = "ref")
t_ref <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("  现有实现 : %6.1f s   %d 层\n", t_ref, terra::nlyr(ref)))

t0 <- Sys.time()
new <- band_props_stream(r, 1000L, 25L, codes)
t_new <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("  逐类流式 : %6.1f s   %d 层\n", t_new, terra::nlyr(new)))
cat(sprintf("  提速     : %.2fx\n\n", t_ref / t_new))

cat("=== 逐层等价性 ===\n")
worst <- 0
for (k in seq_along(codes)) {
  a <- terra::values(ref[[k]],  mat = FALSE)
  b <- terra::values(new[[k]],  mat = FALSE)
  na_a <- is.na(a); na_b <- is.na(b)
  same_na <- identical(na_a, na_b)
  both <- !na_a & !na_b
  d <- if (any(both)) max(abs(a[both] - b[both])) else 0
  worst <- max(worst, d, na.rm = TRUE)
  cat(sprintf("  类 %-3d (code %3d): NA 数 %d vs %d  %s   max|d| = %.3e\n",
              k, codes[k], sum(na_a), sum(na_b),
              ifelse(same_na, "NA一致", "NA不一致"), d))
}
cat(sprintf("\n  最大 max|d| = %.3e\n", worst))
cat(sprintf("  判定（阈值 1e-6）: %s\n", ifelse(worst < 1e-6,
    "通过 —— 两种实现等价", "不通过")))

# 组成恒等式也应成立
s_ref <- Reduce(`+`, lapply(seq_along(codes), function(k) {
  x <- terra::values(ref[[k]], mat = FALSE); x[is.na(x)] <- 0; x }))
s_new <- Reduce(`+`, lapply(seq_along(codes), function(k) {
  x <- terra::values(new[[k]], mat = FALSE); x[is.na(x)] <- 0; x }))
cat(sprintf("\n  和的极值  现有: [%.9f, %.9f]\n", min(s_ref), max(s_ref)))
cat(sprintf("  和的极值  流式: [%.9f, %.9f]\n", min(s_new), max(s_new)))

cat(sprintf("\n  === 年化 ===\n  现有 %.2f h/年/分片 ; 流式 %.2f h/年/分片\n",
            ceiling(4062/25)*t_ref/3600, ceiling(4062/25)*t_new/3600))
