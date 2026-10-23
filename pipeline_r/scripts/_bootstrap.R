# =============================================================================
# R/_bootstrap.R  --  所有 R 脚本的统一引导
#
# 用法：在任何脚本开头写
#     source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"))
# 或（推荐，自动定位）
#     source(file.path(dirname(sys.frame(1)$ofile %||% "."), "_bootstrap.R"))
#
# 本文件职责：
#   1) 确定并导出 CHECO_ROOT（仓库根）
#   2) 加载 00_config.R 与 01_common.R
# =============================================================================

if (!nzchar(Sys.getenv("CHECO_ROOT", ""))) {
  Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
}
CHECO_ROOT <- Sys.getenv("CHECO_ROOT")

R_DIR <- file.path(CHECO_ROOT, "R")
if (!dir.exists(R_DIR)) stop("R/ not found under CHECO_ROOT: ", CHECO_ROOT)

source(file.path(R_DIR, "00_config.R"), encoding = "UTF-8")
source(file.path(R_DIR, "01_common.R"), encoding = "UTF-8")
source(file.path(R_DIR, "01b_ccl.R"), encoding = "UTF-8")

# terra 单进程内存上限。多进程并发时每个进程都按默认 60% 物理内存规划会超额承诺，
# 触发 C++ std::bad_alloc（2026-10-19 实测：6-8 并发必须压低到 0.12）。
.mf <- suppressWarnings(tryCatch(as.numeric(CFG()$runtime$terra_memfrac),
                                 error = function(e) NA_real_))
if (length(.mf) == 1 && !is.na(.mf)) terra::terraOptions(memfrac = .mf)

invisible(TRUE)
