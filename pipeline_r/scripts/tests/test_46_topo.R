# R/tests/test_46_topo.R -- 验证 aspect / tri / soil profile 与 Python 原层一致
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
OUT <- "E:/CHECO26/N-SDM/scratch/r_topo_test"
Sys.setenv(CHECO_OUT_ROOT = OUT)
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/08_derive_topo_vege.R", envir = .ing)

g <- GRID(); res <- as.numeric(CFG()$grid$resolution)

# 读现有 elev（掩膜后）
ep <- file.path(PATH_COV(), "glo/topo/chinadem/elev/glo_topo_chinadem_elev.tif")
elev <- terra::as.matrix(read_clean(ep), wide = TRUE)
cat(sprintf("elev: %d x %d, 有效 %s\n\n", nrow(elev), ncol(elev),
            format(sum(!is.na(elev)), big.mark = ",")))

# ---- aspect ----
t0 <- Sys.time()
asp <- .ing$horn_aspect(elev, res)
cat(sprintf("aspect 计算 %.1f 秒, 值域 [%.4f, %.4f]\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs")),
            min(asp, na.rm = TRUE), max(asp, na.rm = TRUE)))
dst <- file.path(OUT, "aspect.tif")
atomic_write_raster(dst, terra::rast(asp, extent = terra::ext(g$rast), crs = g$crs), dtype = "float32")
ref <- file.path(PATH_COV(), "glo/topo/chinadem/aspect/glo_topo_chinadem_aspect.tif")
r <- compare_layers(read_clean(dst), read_clean(ref))
cat(sprintf("  aspect vs 参照: %s\n    %s\n", ifelse(r$pass, "PASS", "FAIL"), fmt_cmp(r)))

# ---- tri ----
t0 <- Sys.time()
tri <- .ing$riley_tri(elev)
cat(sprintf("tri    计算 %.1f 秒, 值域 [%.4f, %.4f]\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs")),
            min(tri, na.rm = TRUE), max(tri, na.rm = TRUE)))
dst2 <- file.path(OUT, "tri.tif")
atomic_write_raster(dst2, terra::rast(tri, extent = terra::ext(g$rast), crs = g$crs), dtype = "float32")
ref2 <- file.path(PATH_COV(), "glo/topo/chinadem/tri/glo_topo_chinadem_tri.tif")
r2 <- compare_layers(read_clean(dst2), read_clean(ref2))
cat(sprintf("  tri vs 参照: %s\n    %s\n", ifelse(r2$pass, "PASS", "FAIL"), fmt_cmp(r2)))

# ---- soil profile（抽 3 个属性）----
cat("\n=== soil profile 抽样 ===\n")
for (adir in c("clay", "ph", "socd")) {
  t0 <- Sys.time()
  rr <- .ing$soil_profile(adir)
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  dst3 <- file.path(OUT, sprintf("soil_%s_profile.tif", adir))
  # soil_profile 写到 PATH_SCRATCH 下? 不，它用 layer_path，受 CHECO_OUT_ROOT 控制
  got <- layer_path(c("glo", "soil", "csdlv2", adir), "_profile")
  if (!file.exists(got)) { cat(sprintf("  %-6s 未生成 (%s)\n", adir, rr$status)); next }
  ref3 <- file.path(PATH_COV(), sprintf("glo/soil/csdlv2/%s/glo_soil_csdlv2_%s_profile.tif", adir, adir))
  if (!file.exists(ref3)) { cat(sprintf("  %-6s 参照不存在\n", adir)); next }
  r3 <- compare_layers(read_clean(got), read_clean(ref3))
  cat(sprintf("  %-6s %s (%.0f 秒) | %s\n", adir, ifelse(r3$pass, "PASS", "FAIL"), el, fmt_cmp(r3)))
}
