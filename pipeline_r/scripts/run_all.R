# =============================================================================
# R/run_all.R  --  CHECO26 全流程复现入口
#
# 用法（单进程顺序执行，最稳妥但最慢）：
#   Rscript R/run_all.R                # 跑完全部阶段
#   Rscript R/run_all.R 03 04 05       # 只跑指定阶段
#
# 用法（分片并行，推荐）：
#   Rscript R/run_all.R stage 06 1 4   # 06 阶段的第 1/4 片
#
# 阶段一览（顺序有依赖，不可乱序）：
#   02  template + 中国掩膜            ← 一切的基础
#   03  静态主题基底 234 层            ← 依赖 02
#   02b 水文窗口极值 18 层             ← 依赖 03（源哨兵掩膜）
#   04  时序主题 164 层（hfp/smod/ndvi）← 依赖 02
#   05  GLULC 540 层                   ← 依赖 02，焦点依赖本阶段基底
#   06  CLCD 1,170 层                  ← 依赖 02
#   07  harmonised 18,440 层           ← 依赖 02
#   08  topo 派生 2 + 土壤剖面 28      ← 依赖 03（elev、soil 基底）
#   09  距离面 5 层                    ← 依赖 02 与 03（smod）
#   10  bioclim 未来链 504 层          ← 依赖 02
#   11  全库校验                       ← 依赖以上全部
#   12  变量字典                       ← 依赖 11 通过
#   13  溯源表                         ← 依赖 12
#
# 幂等性：所有阶段"目标已存在且模板四查通过则跳过"。
# 因此可反复运行本脚本；要强制重建，设环境变量 CHECO_FORCE=1。
# =============================================================================

source(file.path(Sys.getenv("CHECO_ROOT", Sys.getenv("CHECO_ROOT", getwd())), "R/_bootstrap.R"),
       encoding = "UTF-8")

STAGES <- list(
  "02"  = list(script = "02_template.R",            args = list(), shardable = FALSE),
  "03"  = list(script = "03_ingest_static.R",       args = list(), shardable = FALSE),
  "02b" = list(script = "02b_hydro_stats.R",        args = list(1L, 1L), shardable = TRUE),
  "04"  = list(script = "04_ingest_timeseries.R",   args = list(), shardable = FALSE),
  "05"  = list(script = "05_derive_lulc.R",         args = list(), shardable = FALSE),
  "06"  = list(script = "06_derive_lulc_clcd.R",    args = list("base", 1L, 1L), shardable = TRUE),
  "07"  = list(script = "07_derive_lulc_hlu1km.R",  args = list("base", 1L, 1L), shardable = TRUE),
  "08"  = list(script = "08_derive_topo_vege.R",    args = list("topo"), shardable = FALSE),
  "09"  = list(script = "09_derive_dist.R",         args = list(), shardable = FALSE),
  "10"  = list(script = "10_future_chains.R",       args = list(1L, 1L), shardable = TRUE),
  "11"  = list(script = "11_validate.R",            args = list("header"), shardable = FALSE),
  "12"  = list(script = "12_make_docs.R",           args = list("nostats"), shardable = FALSE),
  "13"  = list(script = "13_make_provenance.R",     args = list(), shardable = FALSE)
)

run_stage <- function(key, shard = 1L, nshard = 1L) {
  st <- STAGES[[key]]
  if (is.null(st)) stop("unknown stage: ", key)
  path <- file.path(CHECO_ROOT, "R", st$script)
  if (!file.exists(path)) stop("script not found: ", path)
  cat(sprintf("\n===== stage %-3s : %s =====\n", key, st$script))
  t0 <- Sys.time()
  # 在干净环境里 source 并调用该脚本的 main()（各脚本 sys.nframe()!=0 时不自动执行）
  env <- new.env(parent = globalenv())
  sys.source(path, envir = env)
  if (exists("main", envir = env, inherits = FALSE)) {
    f <- get("main", envir = env)
    args <- st$args
    # 分片参数只传给声明 shardable 的阶段，替换其最后两个位置参数
    if (isTRUE(st$shardable)) {
      args[[length(args) - 1L]] <- as.integer(shard)
      args[[length(args)]]     <- as.integer(nshard)
    }
    do.call(f, args)
  } else {
    cat("  (该脚本在 source 时即执行)\n")
  }
  cat(sprintf("===== stage %-3s done in %.0f s =====\n", key,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

main <- function(argv = character()) {
  print_grid()
  mode <- if (length(argv) && argv[1] == "stage") "stage" else "seq"
  if (mode == "stage") {
    key <- argv[2]
    sh  <- if (length(argv) >= 3) as.integer(argv[3]) else 1L
    ns  <- if (length(argv) >= 4) as.integer(argv[4]) else 1L
    run_stage(key, sh, ns)
  } else {
    keys <- if (length(argv)) argv else names(STAGES)
    cat("将依次执行:", paste(keys, collapse = " -> "), "\n")
    for (k in keys) run_stage(k)
  }
  invisible(NULL)
}

if (sys.nframe() == 0L) main(commandArgs(trailingOnly = TRUE))
