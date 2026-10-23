# =============================================================================
# R/01b_ccl.R  --  4 邻域连通域标记（Connected Component Labelling）
#
# 为什么自实现：
#   terra 1.8.54 的 terra::patches() 在约 36 万像元以上触发栈溢出（0xC00000FD），
#   实测 550x550(30万) 正常、600x600(36万) 与 300x4861(146万) 均崩溃；
#   本库栅格为 4062x4861 = 1,974 万像元，且 terra 无 clump() 可退。
#
# 算法：按行游程 + 并查集（经典两遍法）
#   1) 每行找出连续 TRUE 的游程 [start, end]
#   2) 相邻两行的游程若列区间相交（4 邻域），用并查集合并
#   3) 按"首次出现顺序"重编号为 1..n（与 numpy ndimage.label 的扫描序一致）
#
# 复杂度：O(游程数 × α)，与图像面积近似线性；无递归，不会栈溢出。
# =============================================================================

#' 4 邻域连通域标记
#' @param m 逻辑矩阵（nr x nc），TRUE = 目标像元
#' @return list(labels = 整数矩阵（0 = 背景）, n = 斑块数)
ccl4 <- function(m) {
  if (!is.matrix(m)) m <- as.matrix(m)
  nr <- nrow(m); nc <- ncol(m)
  storage.mode(m) <- "logical"

  # ---- 1) 每行游程 ----
  rs <- vector("list", nr); re <- vector("list", nr)
  for (i in seq_len(nr)) {
    x <- m[i, ]
    if (!any(x)) { rs[[i]] <- integer(0); re[[i]] <- integer(0); next }
    d <- diff(c(FALSE, x, FALSE))
    rs[[i]] <- which(d == 1L)
    re[[i]] <- which(d == -1L) - 1L
  }
  len <- lengths(rs)
  nrun <- sum(len)
  if (nrun == 0L) return(list(labels = matrix(0L, nr, nc), n = 0L))

  run_start <- unlist(rs, use.names = FALSE)
  run_end   <- unlist(re, use.names = FALSE)
  run_row   <- rep.int(seq_len(nr), len)
  row_off   <- c(0L, cumsum(len))

  # ---- 2) 并查集 ----
  parent <- seq_len(nrun)
  find <- function(i) {
    while (parent[i] != i) { parent[i] <<- parent[parent[i]]; i <- parent[i] }
    i
  }

  for (i in seq_len(nr - 1L)) {
    # 注意：某行可能没有游程，此时 (off[i]+1):off[i+1] 会退化为递减序列而非空序列，
    # 必须显式判断，否则会把不存在的 run id 传给 findInterval（vec 非有序）。
    a <- if (row_off[i + 1L] > row_off[i]) (row_off[i] + 1L):row_off[i + 1L] else integer(0)
    b <- if (row_off[i + 2L] > row_off[i + 1L]) (row_off[i + 1L] + 1L):row_off[i + 2L] else integer(0)
    if (length(a) == 0L || length(b) == 0L) next
    ps <- run_start[a]; pe <- run_end[a]
    ss <- run_start[b]; se <- run_end[b]
    # 上一行游程按 start 递增；找交叠候选区间 [j0, J]
    J  <- findInterval(se, ps)           # ps <= se 的个数
    j0 <- findInterval(ss - 1L, pe) + 1L # 首个 pe >= ss 的位置
    ok <- which(j0 <= J)
    if (!length(ok)) next
    for (k in ok) {
      for (j in j0[k]:J[k]) {
        ra <- find(a[j]); rb <- find(b[k])
        if (ra != rb) parent[ra] <- rb
      }
    }
  }

  # ---- 3) 按首次出现顺序重编号 ----
  root <- vapply(seq_len(nrun), find, 0L)
  lab_run <- match(root, unique(root))
  n_patch <- length(unique(root))

  # ---- 4) 回填到像元（向量化） ----
  rl <- run_end - run_start + 1L
  cell_col <- sequence(rl, from = run_start)
  cell_row <- rep.int(run_row, rl)
  lab_cell <- rep.int(lab_run, rl)
  labels <- matrix(0L, nr, nc)
  labels[cbind(cell_row, cell_col)] <- lab_cell

  list(labels = labels, n = n_patch)
}

#' 暴力参考实现（仅供小矩阵验证）：逐像元 BFS
ccl4_bruteforce <- function(m) {
  nr <- nrow(m); nc <- ncol(m)
  lab <- matrix(0L, nr, nc); cur <- 0L
  for (i in seq_len(nr)) for (j in seq_len(nc)) {
    if (!m[i, j] || lab[i, j] != 0L) next
    cur <- cur + 1L
    q_r <- i; q_c <- j; lab[i, j] <- cur
    head <- 1L
    while (head <= length(q_r)) {
      r <- q_r[head]; cc <- q_c[head]; head <- head + 1L
      for (d in list(c(-1L, 0L), c(1L, 0L), c(0L, -1L), c(0L, 1L))) {
        rr <- r + d[1]; ccc <- cc + d[2]
        if (rr >= 1 && rr <= nr && ccc >= 1 && ccc <= nc &&
            m[rr, ccc] && lab[rr, ccc] == 0L) {
          lab[rr, ccc] <- cur
          q_r <- c(q_r, rr); q_c <- c(q_c, ccc)
        }
      }
    }
  }
  list(labels = lab, n = cur)
}
