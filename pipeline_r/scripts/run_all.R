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
# 默认顺序包含全部 GLU 快照及 CLCD/HLU 基础层和焦点层。
# 19 从原始瓦片构建历史 h90m 层，17 独立处理上游格高程三层。
# 02b 是兼容入口。内部 HydroSHEDS 是独立阶段 16。完整许可、溯源富化和发布清单由 run_metadata_chelsa.R 重生成。
# 已有并对齐的图层通常会跳过。CHECO_FORCE=1 用于安排重算。
# =============================================================================

source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

STAGES <- list(
  "02"  = list(script = "02_template.R",            args = list(), shardable = FALSE),
  "03"  = list(script = "03_ingest_static.R",       args = list(NULL, FALSE), shardable = FALSE),
  "02b" = list(script = "02b_hydro_stats.R",        args = list(1L, 1L), shardable = TRUE),
  "19"  = list(script = "19_rebuild_h90m_legacy.R", args = list(), shardable = FALSE),
  "17"  = list(script = "17_rebuild_h90m_upstream.R", args = list(), shardable = FALSE),
  "04"  = list(script = "04_ingest_timeseries.R",   args = list(), shardable = FALSE),
  "05"  = list(script = "05_derive_lulc.R",         args = list(1:10), shardable = FALSE),
  "06"  = list(script = "06_derive_lulc_clcd.R",    args = list("base", 1L, 1L), shardable = TRUE),
  "07"  = list(script = "07_derive_lulc_hlu1km.R",  args = list("base", 1L, 1L), shardable = TRUE),
  "06f" = list(script = "06_derive_lulc_clcd.R",    args = list("focal", 1L, 1L), shardable = TRUE),
  "07f" = list(script = "07_derive_lulc_hlu1km.R",   args = list("focal", 1L, 1L), shardable = TRUE),
  "08"  = list(script = "08_derive_topo_vege.R",    args = list("profile"), shardable = FALSE),
  "18"  = list(script = "18_ingest_copdem90.R",      args = list(), shardable = FALSE),
  "09"  = list(script = "09_derive_dist.R",         args = list(), shardable = FALSE),
  "10"  = list(script = "10_future_chains.R",       args = list(1L, 1L), shardable = TRUE),
  "11"  = list(script = "11_validate.R",            args = list("header"), shardable = FALSE),
  "12"  = list(script = "12_make_docs.R",           args = list(TRUE), shardable = FALSE),
  "13"  = list(script = "13_make_provenance.R",     args = list(), shardable = FALSE)
)

run_stage <- function(key, shard = 1L, nshard = 1L) {
  st <- STAGES[[key]]
  if (is.null(st)) stop("unknown stage: ", key)
  path <- file.path(R_DIR, st$script)
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
    result <- do.call(f, args)
    if (is.list(result)) {
      if (!is.null(result$err) && result$err > 0L)
        stop("Stage ", key, " reported ", result$err, " errors")
      if (nshard == 1L && !is.null(result$pending) && result$pending > 0L)
        stop("Stage ", key, " has pending inputs")
    }
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
    keys <- if (length(argv)) argv else setdiff(names(STAGES), "02b")
    cat("将依次执行:", paste(keys, collapse = " -> "), "\n")
    for (k in keys) run_stage(k)
  }
  invisible(NULL)
}

if (sys.nframe() == 0L) main(commandArgs(trailingOnly = TRUE))
