# R/tools/test_checkers.R -- self-tests for the checker helpers
#
# The four R checkers compare numbers pulled out of the documents against numbers
# computed from disk. Their helpers are small enough to hide exactly the failure that
# matters: a comparison that passes because neither side produced a value.
#
# This evaluates the real helper definitions out of the real scripts -- by parsing the
# file and evaluating only the expressions up to the helper's assignment -- and then
# feeds them three cases each: a deliberate mismatch, a pair of NAs, and a match.
# A helper is only trustworthy if it reports FAIL, FAIL, PASS in that order.
#
# Usage: Rscript R/tools/test_checkers.R

.root <- Sys.getenv("CHECO_ROOT", "")
if (!nzchar(.root)) {
  .a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  .d <- if (length(.a)) dirname(normalizePath(sub("^--file=", "", .a[1]))) else getwd()
  while (!file.exists(file.path(.d, "R", "_bootstrap.R")) && dirname(.d) != .d) .d <- dirname(.d)
  .root <- .d
}
Sys.setenv(CHECO_ROOT = .root)
source(file.path(.root, "R", "_bootstrap.R"), encoding = "UTF-8")

# Evaluate a script only as far as the expression that defines `what`, then return the
# environment it left behind. Running the whole file would execute against real data.
load_until <- function(path, what) {
  exprs <- parse(path, encoding = "UTF-8")
  e <- new.env(parent = globalenv())
  for (i in seq_along(exprs)) {
    v <- eval(exprs[[i]], envir = e)
    if (is.function(v) && exists("v") &&
        any(all.names(exprs[[i]]) == "<-") && any(all.vars(exprs[[i]]) == what)) break
  }
  e
}

res <- 0L
line <- function(ok, label) {
  cat(sprintf("  %-6s %s\n", if (ok) "PASS" else "FAIL", label))
  if (!ok) res <<- res + 1L
}

# ---- 1) check_docs_consistency.R :: chk(what, claimed, actual) ----------------
cat("=== chk() 自测 ===\n")
e1 <- load_until(file.path(CHECO_ROOT, "R", "tools", "check_docs_consistency.R"), "chk")
before_bad <- e1$bad
invisible(capture.output(e1$chk("mismatch", "1", "2")))
line(e1$bad == before_bad + 1L, "不同的数字 -> FAIL")

before_bad <- e1$bad
invisible(capture.output(e1$chk("both-na", NA, NA)))
line(e1$bad == before_bad + 1L, "两边都是 NA -> FAIL（不得因 identical 判通过）")

before_bad <- e1$bad
invisible(capture.output(e1$chk("same", "7", "7")))
line(e1$bad == before_bad, "相同的数字 -> 不记失败")

# ---- 2) check_trends.R :: say(label, claimed, actual, tol) -------------------
cat("\n=== say() 自测 ===\n")
e2 <- load_until(file.path(CHECO_ROOT, "R", "tools", "check_trends.R"), "say")
b0 <- e2$bad
invisible(capture.output(e2$say("off-by-a-lot", 1.0, 2.0, tol = 0.005)))
line(e2$bad == b0 + 1L, "超出容差 -> FAIL")

b0 <- e2$bad
invisible(capture.output(e2$say("na", NA, 1.0)))
line(e2$bad == b0 + 1L, "NA -> FAIL（且不崩）")

b0 <- e2$bad
invisible(capture.output(e2$say("within", 1.00, 1.004, tol = 0.005)))
line(e2$bad == b0, "容差内 -> 不记失败")

cat(sprintf("\n=== %s：%d 项自测失败 ===\n", if (res == 0L) "通过" else "未通过", res))
if (res > 0L) quit(status = 1L)
