# R/tools/resampling_effect.R
# 重采样效应分析（Technical Validation 的核心证据）
#
# 做法：从源层与重采样层各抽随机格，报告两者差值的变异系数中位数。
# 我们的做法更强，分两部分：
#   (a) 一致性：我们的 1 km 值是否等于源数据在该格内的面积加权均值（应≈0 差异）
#   (b) 信息损失：源数据在每个 1 km 格内的变异系数（SD/mean），量化被平滑掉的细节
#
# 只对**真正做过重采样**的主题做：(30 m 或 90 m 源)。1 km 源的重采样是恒等变换。
#
# 用法：Rscript R/tools/resampling_effect.R [n_cells]
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))

ROOT <- Sys.getenv("CHECO_ROOT", getwd())
COV  <- file.path(ROOT, "data/covariates")
MASK <- file.path(ROOT, "data/mask_china.tif")

n_cell <- if (length(commandArgs(TRUE))) as.integer(commandArgs(TRUE)[1]) else 300L

# 候选：每个主题挑一个有代表性的连续型层
# nd   = 源 nodata 值（必须显式排除；terra 未必读得到声明）
# scale = 源单位换算（见溯源表 source_scale_offset）
# 2026-10-21：vege 的源以**厘米**存储（nodata=65535），若不乘 0.01 会得到
# 319 m 的"平均冠层高度"这种物理不可能值——第一次跑就踩了这个坑。
cases <- list(
  list(key = "vege / forest canopy height (30 m, cm->m)",
       our = "glo/vege/ch2019/ch/glo_vege_ch2019_ch.tif",
       src = "E:/CHECO26/NDVI_forest aboveground biomass_forest canopy height/forest canopy height/_/China_Forest_Canopy_Height_2019.tif",
       nd = 65535, scale = 0.01),
  list(key = "hydro / Hydrosheds accumulation (90 m)",
       our = "glo/hydro/hydrosheds/accumulation/glo_hydro_hydrosheds_accumulation.tif",
       src = "E:/HydroSHEDS Core Data/work/00_src/as_acc_3s.tif",
       nd = NA_real_, scale = 1),
  list(key = "dist / stream distance downstream-near (90 m)",
       our = "glo/dist/h90m/stream-dist-dw-near/glo_dist_h90m_stream-dist-dw-near.tif",
       src = "E:/h90m/Final/stream_dist_dw_near/stream_dist_dw_near_china.tif",
       nd = NA_real_, scale = 1)
)

cat("================================================================\n")
cat(" 重采样效应分析\n")
cat(sprintf(" %s ; 每层 %d 个随机 1 km 格\n", format(Sys.time(), "%H:%M:%S"), n_cell))
cat("================================================================\n\n")

# 选样本格：在中国境内、且该层有值
set.seed(20261021)
mk <- terra::rast(MASK)
tpl <- terra::rast(file.path(COV, cases[[1]]$our))

# 在 mask==1 的像元里随机抽
mkv <- terra::values(mk, mat = FALSE)
inside <- which(mkv == 1)
pick <- sample(inside, min(n_cell * 3L, length(inside)))

res <- list()
for (cs in cases) {
  cat(sprintf("---- %s ----\n", cs$key))
  if (!file.exists(cs$src)) { cat("  跳过：源文件不存在\n\n"); next }
  ours <- terra::rast(file.path(COV, cs$our))
  src  <- terra::rast(cs$src)
  ov <- terra::values(ours)
  dx <- terra::res(ours)[1]; dy <- terra::res(ours)[2]

  # 关键：我们的栅格是 China_Albers（米制，无 EPSG），源多为 EPSG:4326（经纬度）。
  # terra::crop(src, e) 会报 "extents do not overlap"。
  # 正确做法：把 1 km 格构造成正方形多边形 → 转到源 CRS → exactextractr 面积加权。
  # 这与管线本身对 clcd 使用的方法一致（R/06 的 average 重采样），因此是公平对照。
  got <- 0L; rec <- list()
  ok_cells <- pick[!is.na(ov[pick])]
  if (length(ok_cells) > n_cell) ok_cells <- ok_cells[seq_len(n_cell)]
  if (length(ok_cells) >= 10L) {
    xy <- terra::xyFromCell(ours, ok_cells)
    sq <- lapply(seq_along(ok_cells), function(i) {
      sf::st_polygon(list(matrix(c(
        xy[i, 1] - dx / 2, xy[i, 2] - dy / 2,
        xy[i, 1] + dx / 2, xy[i, 2] - dy / 2,
        xy[i, 1] + dx / 2, xy[i, 2] + dy / 2,
        xy[i, 1] - dx / 2, xy[i, 2] + dy / 2,
        xy[i, 1] - dx / 2, xy[i, 2] - dy / 2), ncol = 2, byrow = TRUE)))
    })
    sfobj  <- sf::st_sf(cell = ok_cells, geometry = sf::st_sfc(sq, crs = terra::crs(ours)))
    sf_src <- tryCatch(sf::st_transform(sfobj, terra::crs(src)),
                       error = function(e) NULL)
    if (!is.null(sf_src)) {
      # 用自定义函数：显式排除源 nodata、应用单位换算、按覆盖度加权
      nd <- cs$nd; sc <- cs$scale
      fun <- function(v, c) {
        bad <- is.na(v) | (!is.na(nd) & v == nd)
        if (all(bad)) return(c(mean = NA_real_, stdev = NA_real_, cnt = 0))
        vv <- v[!bad]; cc <- c[!bad]
        m  <- sum(vv * cc) / sum(cc)
        var <- sum(cc * (vv - m)^2) / sum(cc)
        c(mean = m * sc, stdev = sqrt(max(var, 0)) * sc, cnt = sum(cc))
      }
      ex <- tryCatch(exactextractr::exact_extract(src, sf_src, fun, progress = FALSE),
                     error = function(e) NULL)
      # 注意：自定义函数返回命名向量时，exact_extract 给出的是
      # **矩阵（行 = 变量名，列 = 要素）**，不是 data.frame。
      # 直接 ex[, "mean"] 会索引错方向，导致全部判为无效 —— 第一次跑就是这样。
      if (!is.null(ex)) {
        if (is.matrix(ex) && nrow(ex) == 3L && ncol(ex) == length(ok_cells)) ex <- t(ex)
        if (is.matrix(ex) || is.data.frame(ex)) {
          mm <- ex[, "mean"]; ss <- ex[, "stdev"]; nn <- ex[, "cnt"]
          keep <- !is.na(mm) & nn > 0
          got <- sum(keep)
          if (got > 0L)
            rec <- lapply(which(keep), function(i)
              c(our = ov[ok_cells[i]], src_mean = mm[i], src_sd = ss[i], n_src = nn[i]))
        }
      }
    }
  }
  if (got < 10L) { cat(sprintf("  有效格仅 %d，跳过\n\n", got)); next }

  m <- do.call(rbind, rec)
  absd <- abs(m[, "our"] - m[, "src_mean"])
  reld <- absd / pmax(abs(m[, "src_mean"]), 1e-12)
  cv   <- ifelse(abs(m[, "src_mean"]) > 0, m[, "src_sd"] / abs(m[, "src_mean"]), NA)

  cat(sprintf("  比较 %d 个格（源像元/格中位数 %.0f）\n", got, median(m[, "n_src"])))
  cat(sprintf("  (a) 一致性  |our - srcmean|: 中位 %.4g ; 95%% 分位 %.4g ; 最大 %.4g\n",
              median(absd), quantile(absd, 0.95), max(absd)))
  cat(sprintf("      相对差: 中位 %.3e ; 90%% 分位 %.3e ; 相对差 <1%% 的格 %.1f%%\n",
              median(reld), quantile(reld, 0.90), 100 * mean(reld < 0.01)))
  cat(sprintf("  (b) 信息损失  格内源 CV: 中位 %.1f%% ; 90%% 分位 %.1f%%\n",
              100 * median(cv, na.rm = TRUE), 100 * quantile(cv, 0.90, na.rm = TRUE)))
  cat("\n")

  res[[length(res) + 1L]] <- data.frame(
    layer = cs$key, n_cells = got,
    med_abs_diff = median(absd), p95_abs_diff = as.numeric(quantile(absd, 0.95)),
    med_rel_diff_pct = 100 * median(reld),
    p90_rel_diff_pct = 100 * as.numeric(quantile(reld, 0.90)),
    pct_rel_under_1pct = 100 * mean(reld < 0.01),
    med_within_cv_pct = 100 * median(cv, na.rm = TRUE),
    p90_within_cv_pct = 100 * as.numeric(quantile(cv, 0.90, na.rm = TRUE)))
  rm(src); gc(verbose = FALSE)
}

if (length(res)) {
  out <- do.call(rbind, res)
  f <- file.path(ROOT, "00_docs", "resampling_effect.csv")
  write.csv(out, f, row.names = FALSE, fileEncoding = "UTF-8")
  cat("=== 汇总表 ===\n"); print(out, row.names = FALSE)
  cat(sprintf("\n已写出: %s\n", f))
} else {
  cat("没有可分析的层。\n")
}
