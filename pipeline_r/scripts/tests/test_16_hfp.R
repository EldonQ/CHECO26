# R/tests/test_16_hfp.R -- hfp 单层端到端测试（Mollweide 1km -> Albers 1km）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/tests/_helpers.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/04_ingest_timeseries.R"), envir = .ing)

src <- file.path(PATH_ARCHIVE(), "hfp", "HFP-2000-2018", "16571064", "hfp2000", "hfp2000.tif")
cat("=== 源属性 ===\n")
r <- terra::rast(src)
cat(sprintf("  %d x %d | res %s | crs %s | datatype %s | NAflag %s\n",
            ncol(r), nrow(r), paste(terra::res(r), collapse = ","),
            terra::crs(r, proj = TRUE),
            terra::datatype(r), as.character(terra::NAflag(r))))
v <- terra::values(r, mat = FALSE)
cat(sprintf("  全球值域 [%.4f, %.4f] ; NA 数 %s\n",
            min(v, na.rm = TRUE), max(v, na.rm = TRUE), format(sum(is.na(v)), big.mark = ",")))
rm(v); gc(verbose = FALSE)

outdir <- file.path(PATH_SCRATCH(), "r_hfp_test"); ensure_dir(outdir)
dst <- file.path(outdir, "glo_anthro_hfp_2000_hfp.tif")

cat("\n=== 执行 warp（average）===\n")
t0 <- Sys.time()
warp_to_template(src, dst, method = CFG()$resampling$downscale_continuous,
                 src_nodata = NULL, scale = NULL)
cat(sprintf("  耗时 %.1f 秒\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))

g <- read_clean(dst); vv <- terra::values(g, mat = FALSE); vv <- vv[!is.na(vv)]
cat(sprintf("  中国区: n=%s  [%.4f, %.4f]  中位 %.4f\n",
            format(length(vv), big.mark = ","), min(vv), max(vv), median(vv)))
cat(sprintf("  四查: %s\n", check_alignment(dst)))
cat(sprintf("  境内覆盖率: %.4f%%\n", 100 * length(vv) / 9490310))

cat("\n=== 合理性检查（HFP 0-50 标度）===\n")
cat(sprintf("  max <= 50: %s\n", max(vv) <= 50))
cat(sprintf("  min >= 0 : %s\n", min(vv) >= 0))
