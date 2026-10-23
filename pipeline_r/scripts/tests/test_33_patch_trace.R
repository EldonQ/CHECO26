# R/tests/test_33_patch_trace.R -- 追踪 patch_metric 返回值到写盘的有效像元数
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
Sys.setenv(CHECO_OUT_ROOT = "E:/CHECO26/N-SDM/scratch/r_patch_trace")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/05_derive_lulc.R", envir = .ing)

cfg <- CFG(); legend <- unlist(cfg$lulc_legend)
legend <- legend[order(as.integer(names(legend)))]
codes <- as.integer(names(legend)); cnames <- as.character(legend)

src <- file.path(P("lulc_raw"), "history_2020.tif")
r <- terra::rast(src); terra::NAflag(r) <- 0
cls <- terra::project(r, GRID()$rast, method = terra_method(cfg$resampling$categorical), align = FALSE)
m <- china_mask()
v <- terra::values(cls, mat = FALSE); mm <- terra::values(m, mat = FALSE)
v[is.na(mm) | mm != 1] <- 255
v[!is.na(v) & !(v %in% codes)] <- 255
terra::values(cls) <- v
valid <- cls; terra::values(valid) <- as.integer(!is.na(v) & v %in% codes)

binary <- cls
terra::values(binary) <- as.integer(!is.na(v) & v %in% codes)
cat(sprintf("binary == 1 : %s\n", format(as.integer(terra::global(binary, "sum", na.rm = TRUE)[1,1]), big.mark = ",")))

pm <- .ing$patch_metric(binary, 5L)
dv <- terra::values(pm$density, mat = FALSE)
cat(sprintf("patch_metric 返回 density: 非NA %s ; NA %s\n",
            format(sum(!is.na(dv)), big.mark = ","), format(sum(is.na(dv)), big.mark = ",")))

mv <- terra::values(pm$msize, mat = FALSE)
cat(sprintf("patch_metric 返回 msize  : 非NA %s\n", format(sum(!is.na(mv)), big.mark = ",")))

masked <- apply_china_mask(pm$density, NA)
xv <- terra::values(masked, mat = FALSE)
cat(sprintf("apply_china_mask 后     : 非NA %s\n", format(sum(!is.na(xv)), big.mark = ",")))

dst <- file.path(Sys.getenv("CHECO_OUT_ROOT"), "trace.tif")
atomic_write_raster(dst, masked, dtype = "float32")
chk <- read_clean(dst)
yv <- terra::values(chk, mat = FALSE)
cat(sprintf("写盘后读回              : 非NA %s\n", format(sum(!is.na(yv)), big.mark = ",")))
cat(sprintf("NAflag: %s\n", as.character(terra::NAflag(terra::rast(dst)))))
cat(sprintf("值与 masked 一致: %s\n",
            isTRUE(all.equal(ifelse(is.na(xv), NA, xv), ifelse(is.na(yv), NA, yv)))))
