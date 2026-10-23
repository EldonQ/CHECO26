# R/tests/test_50_distance_semantics.R -- 最小用例弄清 terra::distance 的语义
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

g <- GRID()
# 11x11 网格，中心一个要素
m <- matrix(0L, 11, 11); m[6, 6] <- 1L
r <- terra::rast(m, extent = terra::ext(0, 11000, 0, 11000), crs = g$crs)
cat("=== 输入（0/1，中心 = 1）===\n"); print(m)

cat("\n=== terra::distance(target = 1, unit = 'm') ===\n")
d1 <- terra::distance(r, target = 1, unit = "m")
print(round(terra::as.matrix(d1, wide = TRUE), 1))

cat("\n=== terra::distance(target = 1) 默认 unit ===\n")
d2 <- terra::distance(r, target = 1)
print(round(terra::as.matrix(d2, wide = TRUE), 3))

cat("\n=== 解析期望值（像元 1000 m，中心到边角 = sqrt(50)*1000 = %.1f）===\n", sqrt(50) * 1000)
cat(sprintf("  中心: 0 ; 上下左右一格: 1000 ; 对角一格: %.1f\n", sqrt(2) * 1000))

cat("\n=== 试 feat = 0/1 但用 NA 表示非要素 ===\n")
m2 <- matrix(NA_integer_, 11, 11); m2[6, 6] <- 1L
r2 <- terra::rast(m2, extent = terra::ext(0, 11000, 0, 11000), crs = g$crs)
print(round(terra::as.matrix(terra::distance(r2), wide = TRUE), 1))
