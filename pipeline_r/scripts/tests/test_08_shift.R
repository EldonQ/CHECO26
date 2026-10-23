# R/tests/test_08_shift.R -- 位移互相关：R 的 nearest 与 Python 的 nearest 差在何处
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/00_config.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/01_common.R"), encoding = "UTF-8")

diag <- file.path(PATH_SCRATCH(), "diag_warp")
getmat <- function(p) {
  r <- terra::rast(p)
  v <- terra::values(r, mat = FALSE)
  nd <- terra::NAflag(r)
  if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
  v[is.nan(v)] <- NA
  matrix(v, nrow = nrow(r), ncol = ncol(r), byrow = TRUE)
}
A <- getmat(file.path(diag, "r_bio01_nearest.tif"))
B <- getmat(file.path(diag, "py_bio01_nearest.tif"))
cat(sprintf("矩阵: %d x %d ; R 有效 %s ; Python 有效 %s\n",
            nrow(A), ncol(A), format(sum(!is.na(A)), big.mark = ","),
            format(sum(!is.na(B)), big.mark = ",")))

r0 <- 2000; c0 <- 2500; w <- 300
va <- A[r0:(r0 + w - 1), c0:(c0 + w - 1)]

cat("\n=== 位移互相关 ===\n")
best <- NULL
for (dy in -2:2) for (dx in -2:2) {
  rr <- (r0 + dy):(r0 + dy + w - 1); cc <- (c0 + dx):(c0 + dx + w - 1)
  if (min(rr) < 1 || max(rr) > nrow(B) || min(cc) < 1 || max(cc) > ncol(B)) next
  vb <- B[rr, cc]
  ok <- !is.na(va) & !is.na(vb)
  if (sum(ok) < 100) next
  md <- mean(abs(va[ok] - vb[ok]))
  if (is.null(best) || md < best$md) best <- list(dy = dy, dx = dx, md = md, n = sum(ok))
  if (abs(dy) <= 1 && abs(dx) <= 1)
    cat(sprintf("  dy=%+d dx=%+d : mean|d| = %.6f (n=%d)\n", dy, dx, md, sum(ok)))
}
cat(sprintf("  最优: dy=%+d dx=%+d mean|d| = %.6f\n", best$dy, best$dx, best$md))

cat("\n=== 零位移下的差异分布（全图）===\n")
ok <- !is.na(A) & !is.na(B)
d <- abs(A[ok] - B[ok])
cat(sprintf("  共有效 %s ; max|d| %.4f ; mean|d| %.6f\n",
            format(sum(ok), big.mark = ","), max(d), mean(d)))
for (t in c(1e-6, 1e-3, 0.01, 0.1, 1, 5))
  cat(sprintf("    |d| > %-8g : %s\n", t, format(sum(d > t), big.mark = ",")))

cat("\n=== 差异像元的空间分布（按行/列分位）===\n")
idx <- which(ok & (abs(A - B) > 0.01), arr.ind = TRUE)
if (nrow(idx) > 0) {
  cat(sprintf("  差异像元 %s\n", format(nrow(idx), big.mark = ",")))
  cat(sprintf("  行分位: %s\n", paste(sprintf("%.0f%%", quantile(idx[,1]/nrow(A), c(0,.25,.5,.75,1))*100), collapse = " ")))
  cat(sprintf("  列分位: %s\n", paste(sprintf("%.0f%%", quantile(idx[,2]/ncol(A), c(0,.25,.5,.75,1))*100), collapse = " ")))
  cat("\n  这些像元在 Python 侧邻域内的变程（局部极差）中位: ")
  k <- sample(nrow(idx), min(300, nrow(idx)))
  rg <- numeric(length(k))
  for (j in seq_along(k)) {
    rr <- max(1, idx[k[j],1]-1):min(nrow(B), idx[k[j],1]+1)
    cc <- max(1, idx[k[j],2]-1):min(ncol(B), idx[k[j],2]+1)
    v <- B[rr, cc]; v <- v[!is.na(v)]
    rg[j] <- if (length(v) > 1) diff(range(v)) else 0
  }
  cat(sprintf("%.4f\n", median(rg)))
}
