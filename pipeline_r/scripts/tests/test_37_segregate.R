# R/tests/test_37_segregate.R -- 测 terra::segregate 是否能替代 9x ifel
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

g <- GRID()
src <- file.path(PATH_ARCHIVE(), "clcd-albert", "CLCD_v01_2020_albert.tif")
r <- terra::rast(src)
if (is.na(terra::NAflag(r))) terra::NAflag(r) <- 0
codes <- 1:9

y1 <- g$ymax - 1500 * g$res; y0 <- y1 - 10 * g$res
sub <- terra::rast(xmin = g$xmin, xmax = g$xmax, ymin = y0, ymax = y1,
                   resolution = g$res, crs = g$crs)
cs <- terra::crop(r, terra::ext(sub) + 2 * g$res, snap = "out")
v <- terra::values(cs, mat = FALSE); v[is.na(v) | !(v %in% codes)] <- NA
terra::values(cs) <- v
cat(sprintf("窗口 %d px\n", terra::ncell(cs)))

tm <- function(lab, expr) {
  t0 <- Sys.time(); x <- force(expr)
  cat(sprintf("  %-26s %.1f s\n", lab, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  x
}

cat("\n=== 方法 A：9 x ifel ===\n")
layA <- tm("9x ifel", lapply(codes, function(c) terra::ifel(cs == c, 1L, 0L)))
ohA  <- tm("rast(list)", terra::rast(layA))

cat("\n=== 方法 B：segregate ===\n")
segB <- tm("segregate(classes)", terra::segregate(cs, classes = codes, keep = FALSE, other = 0))
cat(sprintf("  层数 %d，数据类型 %s\n", terra::nlyr(segB), terra::datatype(segB)))
cat(sprintf("  第1层值域 [%s, %s]\n",
            format(min(terra::values(segB[[1]], mat = FALSE), na.rm = TRUE)),
            format(max(terra::values(segB[[1]], mat = FALSE), na.rm = TRUE))))
cat(sprintf("  第1层 NA 数 %d ; 源 NA 数 %d\n",
            sum(is.na(terra::values(segB[[1]], mat = FALSE))),
            sum(is.na(terra::values(cs, mat = FALSE)))))

cat("\n=== 两种方法结果是否一致（第 1 层）===\n")
a1 <- terra::values(ohA[[1]], mat = FALSE)
b1 <- terra::values(segB[[1]], mat = FALSE)
cat(sprintf("  都有效 %d ; 仅A %d ; 仅B %d ; 值不等 %d\n",
            sum(!is.na(a1) & !is.na(b1)), sum(!is.na(a1) & is.na(b1)),
            sum(is.na(a1) & !is.na(b1)), sum(a1 != b1, na.rm = TRUE)))

cat("\n=== project 计时（各自）===\n")
tm("project(ohA)", terra::project(ohA, sub, method = "average", align = FALSE))
tm("project(segB)", terra::project(segB, sub, method = "average", align = FALSE))
