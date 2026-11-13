# =============================================================================
# R/run_metadata_chelsa.R  --  CHELSA 替换后的元数据重生成入口（Phase 6）
#
# 前提：run_bioclim_chelsa.R 已产出全部 1,210 层 chelsa21（含 gdd）。
# 用法：Rscript R/run_metadata_chelsa.R
#
# 顺序（与 00_docs/README 重生成顺序一致，含许可注入）：
#   1) 13_make_provenance.R fill   重建溯源表（剔旧 cnclim1km，加 chelsa21，填 actual_range）
#   2) tools/build_licence_registry.R write   注入 4 列许可（CC0-1.0 等）+ 写 LICENCE_REGISTRY.csv
#   3) scripts/enrich_provenance.py   补 hfp/clcd/hlu 的 source_file 与证据等级（chelsa 已在 13 设好）
#   4) 12_make_docs.R   重建变量字典（填统计）+ LAYER_INDEX.md
#   5) 14_manifest.R hash / release   MANIFEST.csv / PUBLIC_RELEASE_MANIFEST.csv / RESTRICTED_LAYERS.csv
#
# 自动设置 Windows UTF-8 locale；幂等，可反复跑。
# =============================================================================

invisible(try(Sys.setlocale("LC_CTYPE", ".65001"), silent = TRUE))
if (!nzchar(Sys.getenv("CHECO_ROOT", ""))) Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
root <- Sys.getenv("CHECO_ROOT")
cat("==== 元数据重生成 CHECO_ROOT:", root, " locale:", Sys.getlocale("LC_CTYPE"), "====\n")
source(file.path(root, "R/_bootstrap.R"), encoding = "UTF-8")

run_r <- function(rel, ...) {
  cat("\n##########", rel, "##########\n")
  e <- new.env(parent = globalenv())
  sys.source(file.path(root, rel), envir = e)
  if (exists("main", envir = e, inherits = FALSE)) do.call(get("main", envir = e), list(...))
}

# 1) 溯源表（fill_actual=TRUE 读已产出层填 actual_range）
run_r("R/13_make_provenance.R", TRUE)
# 2) 许可注入
run_r("R/tools/build_licence_registry.R", "write")
# 3) enrich（Python，补 source_file/证据等级）
py <- "E:/CHECO26/.venv/Scripts/python.exe"
if (file.exists(py)) {
  cat("\n########## scripts/enrich_provenance.py ##########\n")
  st <- system2(py, shQuote(file.path(root, "scripts/enrich_provenance.py")))
  if (st != 0) cat("  WARN: enrich_provenance.py 退出码", st, "\n")
} else {
  cat("\nWARN: 未找到", py, "，跳过 enrich（chelsa21 的 source_file 已在 13 设好）\n")
}
# 4) 变量字典 + 索引
run_r("R/12_make_docs.R", TRUE)
# 5) 清单
run_r("R/14_manifest.R", "hash")
run_r("R/14_manifest.R", "release")

cat("\n==== 元数据重生成完成；请运行验收核验（四方一致 + 哈希复核）====\n")