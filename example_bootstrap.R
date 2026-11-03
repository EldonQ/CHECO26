# =============================================================================
# example_bootstrap.R  --  shared setup for the three worked examples
#
# The examples are meant to call the *production* functions, not a parallel
# implementation. They therefore load the same scripts the archive was built
# with (pipeline_r/scripts/00_config.R and 01_common.R) and the same parameters
# (pipeline_r/config.yaml).
#
# The only thing this file does is tell the production code where to find the
# public sample data. It writes a throw-away copy of config.yaml into a
# temporary run root, points paths.covariates at data/sample_layers, and sets
# CHECO_ROOT to that root. Nothing in the repository is modified.
#
# Usage (from an example script):
#     source(file.path(dirname(sys.frame(1)$ofile %||% "."), "..", "example_bootstrap.R"))
# or simply:
#     source("../example_bootstrap.R", chdir = TRUE)
# =============================================================================

.example_repo_root <- function() {
  env <- Sys.getenv("CHECO_REPO_ROOT", "")
  if (nzchar(env)) return(normalizePath(env, mustWork = FALSE))
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  start <- if (length(hit) == 1L) {
    dirname(normalizePath(sub("^--file=", "", hit), mustWork = FALSE))
  } else getwd()
  # 向上找到含 pipeline_r/ 的目录
  d <- normalizePath(start, mustWork = FALSE)
  while (!dir.exists(file.path(d, "pipeline_r")) && dirname(d) != d) d <- dirname(d)
  d
}

REPO_ROOT <- .example_repo_root()

.p_repo <- file.path(REPO_ROOT, "pipeline_r")
.p_cfg  <- file.path(.p_repo, "config.yaml")
.p_scr  <- file.path(.p_repo, "scripts")
.p_data <- file.path(REPO_ROOT, "data")

for (f in c(.p_cfg, file.path(.p_scr, "_bootstrap.R"),
            file.path(.p_scr, "00_config.R"), file.path(.p_scr, "01_common.R"))) {
  if (!file.exists(f)) stop("repository file missing: ", f)
}

# ---- 1) 用生产 config.yaml，只把 covariantes 指向公开样例 -------------------
.cfg <- yaml::read_yaml(.p_cfg)
.run_root <- file.path(tempdir(), "checo26-example")
dir.create(file.path(.run_root, "scripts"), recursive = TRUE, showWarnings = FALSE)

.cfg$paths$covariates <- file.path(.p_data, "sample_layers")
.cfg$paths$docs       <- file.path(.run_root, "docs")
.cfg$paths$logs       <- file.path(.run_root, "logs")
.cfg$paths$scratch    <- file.path(.run_root, "scratch")
.cfg$paths$archive    <- file.path(.run_root, "archive")
yaml::write_yaml(.cfg, file.path(.run_root, "scripts", "config.yaml"))

# ---- 2) 让生产代码在这个 run root 下工作 ------------------------------------
Sys.setenv(CHECO_ROOT = .run_root)

# 直接载入生产脚本（_bootstrap.R 走的是交付树布局，这里是仓库布局）
source(file.path(.p_scr, "00_config.R"), encoding = "UTF-8")
source(file.path(.p_scr, "01_common.R"), encoding = "UTF-8")

# ---- 3) 样例路径 ------------------------------------------------------------
SAMPLE_LAYERS <- file.path(.p_data, "sample_layers")
SOURCE_LAYERS <- file.path(.p_data, "source_layers")
MASK_PATH     <- file.path(.p_data, "mask_china.tif")
GRID_PATH     <- file.path(.p_data, "CHECO26-standardgrid.tif")

sample_layer <- function(...) file.path(SAMPLE_LAYERS, ...)

# 示例输出目录（每次运行前清空）
example_outdir <- function(name) {
  d <- file.path(tempdir(), "checo26-example", "out", name)
  unlink(d, recursive = TRUE, force = TRUE)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# 打印一段标题，便于阅读运行输出
example_rule <- function(title) {
  cat("\n", strrep("=", 72), "\n", title, "\n", strrep("=", 72), "\n", sep = "")
}

invisible(TRUE)
