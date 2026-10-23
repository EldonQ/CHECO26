# R/tools/clcd_subset.R
# 只跑指定年份的 CLCD，用于"减年"方案（如只做 6 个十年年份）
#
# 背景：R/06_derive_lulc_clcd.R 的 main() 已有 years 参数，但命令行入口
# 只解析 phase/shard/nshard，没有暴露 years。本脚本作为包装器补上这个通道，
# 好处是**不需要修改正在运行的主脚本**。
#
# 用法：
#   Rscript R/tools/clcd_subset.R base 1 4 2000,2005,2010,2015,2020,2025
#   Rscript R/tools/clcd_subset.R focal 1 1 2000,2005,2010,2015,2020,2025
#
# 说明：
#   - shard/nshard 仍按传入的 years 向量做轮转分配
#   - 已存在的层会被 clcd_year_base 跳过（幂等）
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

.ing <- new.env(parent = globalenv())
sys.source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/06_derive_lulc_clcd.R"), envir = .ing)

main <- function(argv = character()) {
  if (length(argv) < 4L) {
    cat("用法: Rscript R/tools/clcd_subset.R <base|focal> <shard> <nshard> <years>\n")
    cat("例:   Rscript R/tools/clcd_subset.R base 1 4 2000,2005,2010,2015,2020,2025\n")
    quit(save = "no", status = 2L)
  }
  ph <- argv[1]
  sh <- as.integer(argv[2]); ns <- as.integer(argv[3])
  yr <- as.integer(trimws(strsplit(argv[4], ",", fixed = TRUE)[[1]]))

  # 只保留源文件确实存在的年份，避免白跑
  ok <- vapply(yr, function(y) file.exists(.ing$clcd_src(y)), TRUE)
  if (any(!ok)) {
    cat("以下年份缺源文件，已剔除:", paste(yr[!ok], collapse = ", "), "\n")
    yr <- yr[ok]
  }
  if (!length(yr)) { cat("无可处理的年份\n"); quit(save = "no", status = 1L) }

  cat(sprintf("=== CLCD 子集运行 ===\n  phase=%s  shard=%d/%d\n  years=%s\n",
              ph, sh, ns, paste(yr, collapse = ",")))
  t0 <- Sys.time()
  .ing$main(ph, sh, ns, years = yr)
  cat(sprintf("=== 完成，用时 %.0f 秒 ===\n",
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

if (sys.nframe() == 0L) main(commandArgs(trailingOnly = TRUE))
