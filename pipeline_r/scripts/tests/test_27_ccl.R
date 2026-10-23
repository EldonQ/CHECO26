# R/tests/test_27_ccl.R
# 1) 小矩阵上与暴力 BFS 逐像元比对（分组是否正确）
# 2) 中矩阵上与 terra::patches 比对（若 terra 能算）
# 3) 全尺寸计时（4062 x 4861），urban 与 forest 两种稀疏度
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

# ---- 1) 与暴力实现比对（只看分组等价，不看标签数值）----
cat("=== 1) 小矩阵 vs 暴力 BFS ===\n")
set.seed(42)
same_partition <- function(a, b) {
  # 两个标签矩阵是否表示同一划分：对每个 (i,j) 对，同组关系一致
  va <- as.vector(a); vb <- as.vector(b)
  ka <- match(va, unique(va)); kb <- match(vb, unique(vb))
  identical(ka, kb)
}
npass <- 0
for (t in 1:30) {
  nr <- sample(5:40, 1); nc <- sample(5:40, 1)
  p <- runif(1, 0.2, 0.8)
  m <- matrix(runif(nr * nc) < p, nr, nc)
  A <- ccl4(m); B <- ccl4_bruteforce(m)
  # 斑块数必须相等；且连通性判断一致（抽 200 个像元对）
  ok <- A$n == B$n
  if (ok) {
    idx <- which(m)
    if (length(idx) > 1) {
      for (q in 1:min(200, length(idx))) {
        i1 <- sample(idx, 1); i2 <- sample(idx, 1)
        if (A$labels[i1] == A$labels[i2] && m[i1] && m[i2])
          ok <- ok && (B$labels[i1] == B$labels[i2])
      }
    }
  }
  npass <- npass + ok
  if (t <= 5) cat(sprintf("  %2d: %2dx%2d p=%.2f -> ccl4 n=%d, brute n=%d %s\n",
                          t, nr, nc, p, A$n, B$n, ifelse(ok, "OK", "MISMATCH")))
}
cat(sprintf("  %d / 30 通过\n", npass))

# ---- 2) 中矩阵 vs terra::patches ----
cat("\n=== 2) 中矩阵 vs terra::patches ===\n")
nr <- 400; nc <- 400
m <- matrix(runif(nr * nc) < 0.45, nr, nc)
A <- ccl4(m)
r <- terra::rast(m, extent = terra::ext(0, nc, 0, nr))
B <- terra::patches(terra::ifel(r, r, NA), directions = 4, values = TRUE)
bm <- terra::as.matrix(B, wide = TRUE)
cat(sprintf("  ccl4 n=%d | terra n=%d | 斑块数一致: %s\n",
            A$n, max(bm, na.rm = TRUE), A$n == max(bm, na.rm = TRUE)))
# 分组一致性（抽 300 对）
idx <- which(m)
agree <- 0; tot <- 0
for (q in 1:300) {
  i1 <- sample(idx, 1); i2 <- sample(idx, 1)
  if (A$labels[i1] == A$labels[i2]) {
    tot <- tot + 1
    if (identical(bm[i1], bm[i2])) agree <- agree + 1
  }
}
cat(sprintf("  同组像元对的一致性: %d / %d\n", agree, tot))

# ---- 3) 全尺寸计时 ----
cat("\n=== 3) 全尺寸计时 4062 x 4861 ===\n")
for (cls in c("urban", "forest", "cropland")) {
  p <- file.path(PATH_COV(), sprintf("glo/lulc/glu1km/2020/%s/glo_lulc_glu1km_2020_%s_prop.tif", cls, cls))
  if (!file.exists(p)) next
  r <- terra::rast(p)
  v <- terra::values(r, mat = FALSE); nd <- terra::NAflag(r)
  if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
  m <- matrix(!is.na(v) & v > 0.5, nrow = nrow(r), ncol = ncol(r), byrow = TRUE)
  t0 <- Sys.time()
  A <- ccl4(m)
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("  %-9s 斑块像元 %9s -> 斑块数 %6d  耗时 %6.1fs\n",
              cls, format(sum(m), big.mark = ","), A$n, el))
  rm(m, A); gc(verbose = FALSE)
}
