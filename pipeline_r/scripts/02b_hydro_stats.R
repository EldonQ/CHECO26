# Legacy command-line entry for the 16 supplementary h90m extrema.
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")
legacy <- new.env(parent = globalenv())
sys.source(file.path(R_DIR, "19_rebuild_h90m_legacy.R"), envir = legacy)

build_manifest <- function() {
  tasks <- legacy$h90m_legacy_manifest()
  unlist(lapply(tasks, function(t) {
    lapply(intersect(t$methods, c("min", "max")), function(s)
      list(parts = t$parts, var = t$var, stat = s, suffix = paste0("_", s),
           scale = t$scale))
  }), recursive = FALSE, use.names = FALSE)
}

run_task <- function(t) {
  dst <- layer_path(t$parts, t$suffix)
  if (legacy$h90m_existing_output(dst)) return(list(status = "skip", dst = dst))
  legacy$rebuild_h90m_legacy(t$var, t$stat)
  list(status = "ok", dst = dst)
}

main <- function(shard = 1L, nshard = 1L) {
  if (shard < 1L || shard > nshard) stop("Invalid h90m shard")
  tasks <- build_manifest()
  index <- seq_along(tasks)
  tasks <- tasks[(index - 1L) %% nshard == shard - 1L]
  if (nshard > 1L) {
    for (t in tasks) run_task(t)
  } else {
    vars <- unique(vapply(tasks, function(t) t$var, ""))
    legacy$rebuild_h90m_legacy(vars, c("min", "max"))
  }
  invisible(tasks)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  main(if (length(args)) as.integer(args[1]) else 1L,
       if (length(args) >= 2L) as.integer(args[2]) else 1L)
}
