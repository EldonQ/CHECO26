# =============================================================================
# R/run_bioclim_chelsa.R  --  CHELSA v2.1 bioclim 替换生产入口（仅 bioclim 主题）
#
# 用法（Windows R 需 UTF-8 locale，本脚本已自动设置）：
#   Rscript R/run_bioclim_chelsa.R            # 现值 + 未来全部（幂等，可反复跑）
#   Rscript R/run_bioclim_chelsa.R present    # 仅现值 22 层
#   Rscript R/run_bioclim_chelsa.R future     # 仅未来 1188 层
#
# 产出：reg/bioclim/chelsa21/{present,scenario}/... 共 1,210 层
#   现值 22（bio01-19 + gdd0/5/10，1981-2010）
#   未来 22 × 6 链(5GCM+ensmean) × 3 SSP × 3 时段 = 1,188
#
# 幂等：目标已存在且模板四查通过则跳过；gdd 源未下载时对应任务报 error，
#       下载完成后重跑本脚本即补齐（已完成的 bio 层自动跳过）。
# 不触碰其他 7 主题，不删除旧 cnclim1km（旧层归档另见 Phase 5）。
# =============================================================================

# Windows R 默认 GBK locale 无法 source UTF-8 中文脚本，先切到 UTF-8（codepage 65001）
invisible(try(Sys.setlocale("LC_CTYPE", ".65001"), silent = TRUE))
if (!nzchar(Sys.getenv("CHECO_ROOT", ""))) Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")

a <- commandArgs(trailingOnly = TRUE)
mode <- if (length(a) >= 1) a[1] else "all"

cat("==== CHECO_ROOT:", Sys.getenv("CHECO_ROOT"), " locale:", Sys.getlocale("LC_CTYPE"), "====\n")
source(file.path(Sys.getenv("CHECO_ROOT"), "R/_bootstrap.R"), encoding = "UTF-8")

if (mode %in% c("all", "present")) {
  cat("\n########## 现值（03 bioclim）##########\n")
  source(file.path(Sys.getenv("CHECO_ROOT"), "R/03_ingest_static.R"), encoding = "UTF-8")
  main(only = "reg_bioclim")
}
if (mode %in% c("all", "future")) {
  cat("\n########## 未来（10 CHELSA 链）##########\n")
  source(file.path(Sys.getenv("CHECO_ROOT"), "R/10_future_chains.R"), encoding = "UTF-8")
  main()
}
cat("\n==== run_bioclim_chelsa 完成 ====\n")