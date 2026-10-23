# R/tests/test_14_sentinel.R -- 单独复测 channel_elv_up_cel（哨兵阈值修正后）
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")
source("E:/CHECO26/N-SDM/R/tests/_helpers.R", encoding = "UTF-8")

# 清掉可能存在的旧缓存（阈值变更必须重算）
cache <- file.path(PATH_SCRATCH(), "sentinel_masked")
if (dir.exists(cache)) { file.remove(list.files(cache, full.names = TRUE)); cat("已清空哨兵缓存\n") }

.ing <- new.env(parent = globalenv())
sys.source("E:/CHECO26/N-SDM/R/03_ingest_static.R", envir = .ing)
tasks <- .ing$build_manifest()
target <- "glo_hydro_h90m_channel-elv-up-cel.tif"
k <- which(vapply(tasks, function(t) basename(layer_path(t$parts)), "") == target)
t <- tasks[[k]]

cat(sprintf("任务: %s | sentinel=%.0f | rule=%s | scale=%s\n",
            target, t$sentinel, t$rule,
            if (is.null(t$scale)) "none" else format(t$scale)))

# 源的哨兵分布核实
src <- terra::rast(t$src)
v <- terra::values(src, mat = FALSE); nd <- terra::NAflag(src)
if (!is.na(nd)) v <- v[is.na(v) | v != nd]
v <- v[!is.na(v)]
cat(sprintf("源: 有效 %s | >50000 的 %d | >99999 的 %d | 区间(%s) [%.0f, %.0f]\n",
            format(length(v), big.mark = ","),
            sum(v >= 50000), sum(v >= 99999),
            paste(setdiff(sort(unique(ifelse(v >= 50000, ">=50k", "<50k"))), ""), collapse = "/"),
            min(v[v >= 50000]), max(v)))
rm(v); gc(verbose = FALSE)

outdir <- file.path(PATH_SCRATCH(), "r_sentinel_test"); ensure_dir(outdir)
dst <- file.path(outdir, target)

s <- .ing$mask_source_sentinel(t$src, t$sentinel, sub("\\.tif$", "", target))
cat(sprintf("掩膜后源: %s\n", s))

warp_to_template(s, dst, method = CFG()$resampling[[t$rule]],
                 src_nodata = t$src_nodata, scale = t$scale)

ref <- layer_path(t$parts)
r <- compare_layers(read_clean(dst), read_clean(ref))
cat("\n", fmt_cmp(r), "\n")
cat(sprintf("合格: %s   (C1 掩膜 %s | C2 偏差 %s | C3 mean %s | C4 tail %s)\n",
            r$pass, r$c[1], r$c[2], r$c[3], r$c[4]))

cat("\n=== R 输出与参照层值域对照 ===\n")
for (p in c(dst, ref)) {
  x <- read_clean(p); vv <- terra::values(x, mat = FALSE); vv <- vv[!is.na(vv)]
  cat(sprintf("  %-58s [%.2f, %.2f] 中位 %.2f n=%s\n",
              basename(p), min(vv), max(vv), median(vv), format(length(vv), big.mark = ",")))
}
