# R/tests/test_12_theme_equiv.R  (v2：采用 _helpers.R 的统一判据 + 修正哨兵阈值)
#
# 逐主题抽样验证：用 03_ingest_static.R 的任务清单，把指定层用 R 重算到 scratch，
# 与 Python 原层按 C1–C4 判据比对（判据依据见 _helpers.R 注释与 test_13）。

Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/tests/_helpers.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/03_ingest_static.R"), envir = .ing)
tasks <- .ing$build_manifest()

pick <- c(
  "glo_bioclim_cnclim1km_present_bio01.tif",
  "glo_bioclim_cnclim1km_present_bio12.tif",
  "glo_bioclim_cnclim1km_present_sunp.tif",
  "glo_soil_csdlv2_clay_0.tif",
  "glo_soil_csdlv2_ph_0.tif",
  "glo_soil_csdlv2_an_0.tif",
  "glo_topo_chinadem_elev.tif",
  "glo_topo_chinadem_slope.tif",
  "glo_hydro_h90m_channel-dist-up-cel.tif",
  "glo_hydro_h90m_channel-curv-cel.tif",
  "glo_hydro_h90m_spi.tif",
  "glo_hydro_h90m_channel-elv-up-cel.tif",
  "glo_hydro_h90m_basin.tif",
  "glo_vege_ch2019_ch.tif",
  "glo_vege_agb2019_agb.tif",
  "glo_vege_catcd_treecover.tif"
)

name_of <- function(t) basename(layer_path(t$parts))
idx <- match(pick, vapply(tasks, name_of, ""))
if (any(is.na(idx))) { cat("未在清单中找到:\n"); print(pick[is.na(idx)]); idx <- idx[!is.na(idx)] }

outdir <- file.path(PATH_SCRATCH(), "r_theme_equiv2"); ensure_dir(outdir)

cat("=== 逐主题抽样验证 v2（C1 掩膜≤0.02% / C2 |偏差|<1e-3 / C3 mean|d|<5e-3 / C4 tail≤0.001%）===\n\n")
cat(sprintf("%-44s %6s %6s %8s %9s %9s %9s %6s %s\n",
            "层", "仅R", "仅Py", "掩膜%", "偏差", "mean|d|", "max|d|", "tail", "判定"))
cat(strrep("-", 128), "\n")

res <- list()
for (k in idx) {
  t <- tasks[[k]]; nm <- name_of(t)
  ref_path <- layer_path(t$parts)
  if (!file.exists(ref_path)) { cat(sprintf("%-44s [无参照层]\n", nm)); next }
  dst <- file.path(outdir, nm)
  ok <- tryCatch({
    s <- t$src
    if (!is.null(t$sentinel)) s <- .ing$mask_source_sentinel(s, t$sentinel, sub("\\.tif$", "", nm))
    warp_to_template(s, dst, method = CFG()$resampling[[t$rule]],
                     src_nodata = t$src_nodata, scale = t$scale)
    TRUE
  }, error = function(e) { cat(sprintf("%-44s [ERR] %s\n", nm, conditionMessage(e))); FALSE })
  if (!ok) next

  r <- compare_layers(read_clean(dst), read_clean(ref_path))
  cat(sprintf("%-44s %6d %6d %8.4f %9.2e %9.2e %9.2e %6d  %s\n",
              substr(nm, 1, 44), r$only_a, r$only_b, r$mism_pct,
              r$bias, r$mean_abs, r$max_abs, r$n_tail,
              ifelse(r$pass, "PASS", paste0("FAIL(", paste(which(!r$c), collapse = ","), ")"))))
  res[[nm]] <- r$pass
}

cat("\n")
cat(sprintf("=== 结论：%d / %d 通过 ===\n", sum(unlist(res)), length(res)))
if (any(!unlist(res))) { cat("未通过:\n"); print(names(res)[!unlist(res)]) }
