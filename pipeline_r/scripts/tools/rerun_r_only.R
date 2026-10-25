# R/tools/rerun_r_only.R -- recompute the layers that still came from the earlier
# Python pipeline, so that every publishable layer in the delivery is produced by R.
#
# The stage scripts skip layers that already exist and pass the alignment check, so
# a plain re-run would leave the old bytes in place. This driver sets CHECO_FORCE=1
# and calls the stage's own entry point, never touching anything else.
#
# Usage:
#   Rscript R/tools/rerun_r_only.R 08                 # soil profiles + aspect/tri (30)
#   Rscript R/tools/rerun_r_only.R 04 '^glo_vege_'    # vege focal layers (24)
#   Rscript R/tools/rerun_r_only.R 05 1               # glu1km snapshot 1 (54)
#
# The 5 RESTRICTED HydroSHEDS accumulation layers are deliberately not covered:
# the R alternative (15_ingest_h90m_accumulation.R) was tried on 2026-10-21 and
# rejected - channel peaks came out 6.2x too low for reasons never established -
# and those 5 layers are excluded from the public release anyway.

Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
Sys.setenv(CHECO_FORCE = "1")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("usage: rerun_r_only.R <04|08|05> [only|snap_idx]")
stage <- args[1]
arg2 <- if (length(args) >= 2) args[2] else NA_character_

cat(sprintf("=== rerun %s (CHECO_FORCE=%s) ===\n", stage,
            Sys.getenv("CHECO_FORCE")))

e <- new.env(parent = globalenv())

if (stage == "08") {
  sys.source(file.path(CHECO_ROOT, "R/08_derive_topo_vege.R"), envir = e)
  # main() calls match.arg(which), which keeps only the first element, so the two
  # modes have to be invoked one at a time.
  for (w in c("topo", "profile")) {
    cat(sprintf("--- 08: %s ---\n", w))
    res <- e$main(which = w)
  }
} else if (stage == "04") {
  sys.source(file.path(CHECO_ROOT, "R/04_ingest_timeseries.R"), envir = e)
  only <- if (is.na(arg2)) NULL else arg2
  res <- e$main(only = only)
} else if (stage == "05") {
  sys.source(file.path(CHECO_ROOT, "R/05_derive_lulc.R"), envir = e)
  idx <- if (is.na(arg2)) seq_along(e$SNAPSHOTS) else as.integer(arg2)
  for (i in idx) {
    t0 <- Sys.time()
    r <- e$derive_snapshot(e$SNAPSHOTS[[i]], c("prop", "shannon", "edge", "patch"))
    cat(sprintf("  snapshot %d (y=%s): %s, %d 层, %.0f s\n", i,
                e$SNAPSHOTS[[i]]$y, r$status, r$n,
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
  res <- invisible(NULL)
} else {
  stop("unknown stage: ", stage)
}

cat("=== done ===\n")
