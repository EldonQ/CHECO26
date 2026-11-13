# =============================================================================
# R/run_bioclim_shard.R  --  CHELSA 未来层分片并行生产入口
# 用法：Rscript R/run_bioclim_shard.R <shard> <nshard>
#   例：4 路并行 → 分别跑 1 4 / 2 4 / 3 4 / 4 4
# 分片互斥（seq.int(shard, n, by=nshard)），各片写不同层，原子写无竞争。
# 每片先 GCM 后 ensmean；ensmean 依赖全部 5 GCM，跨片未就绪时记 pending，
# 全部片完成后另跑 `Rscript R/run_bioclim_shard.R 1 1` 补齐 ensmean。
# =============================================================================
invisible(try(Sys.setlocale("LC_CTYPE", ".65001"), silent = TRUE))
if (!nzchar(Sys.getenv("CHECO_ROOT", ""))) Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source(file.path(Sys.getenv("CHECO_ROOT"), "R/_bootstrap.R"), encoding = "UTF-8")
a <- commandArgs(trailingOnly = TRUE)
shard  <- if (length(a) >= 1) as.integer(a[1]) else 1L
nshard <- if (length(a) >= 2) as.integer(a[2]) else 1L
cat(sprintf("==== bioclim 未来分片 shard=%d/%d ====\n", shard, nshard))
source(file.path(Sys.getenv("CHECO_ROOT"), "R/10_future_chains.R"), encoding = "UTF-8")
main(shard, nshard)