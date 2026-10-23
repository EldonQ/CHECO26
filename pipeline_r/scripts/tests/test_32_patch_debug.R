# R/tests/test_32_patch_debug.R -- 逐步仪表化 patch_metric，定位有效域缺失
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

cfg <- CFG(); legend <- unlist(cfg$lulc_legend)
legend <- legend[order(as.integer(names(legend)))]
codes <- as.integer(names(legend))
snap <- local({
  s <- list(y = "2020", ssp = NA_character_, f = "history_2020.tif"); s
})
src <- file.path(P("lulc_raw"), snap$f)
r <- terra::rast(src); terra::NAflag(r) <- 0
cls <- terra::project(r, GRID()$rast, method = terra_method(cfg$resampling$categorical), align = FALSE)
m <- china_mask()
v <- terra::values(cls, mat = FALSE); mm <- terra::values(m, mat = FALSE)
v[is.na(mm) | mm != 1] <- 255
v[!is.na(v) & !(v %in% codes)] <- 255
terra::values(cls) <- v
valid <- cls; terra::values(valid) <- as.integer(!is.na(v) & v %in% codes)

bin_r <- valid
bin <- !is.na(terra::as.matrix(bin_r, wide = TRUE)) &
       terra::as.matrix(bin_r, wide = TRUE) == 1
cat(sprintf("binary TRUE: %s\n", format(sum(bin), big.mark = ",")))

cc <- ccl4(bin)
labm <- cc$labels; n_patch <- cc$n
cat(sprintf("斑块数: %d ; 有标签像元: %s ; 最大面积: %s\n",
            n_patch, format(sum(labm > 0), big.mark = ","),
            format(max(tabulate(labm[labm > 0], nbins = n_patch)), big.mark = ",")))

nr <- nrow(labm); nc <- ncol(labm)
areas <- tabulate(labm[labm > 0L], nbins = n_patch)
flat <- as.vector(t(labm)); nz <- which(flat > 0L)
lab_nz <- flat[nz]; first <- !duplicated(lab_nz)
anc_cell <- nz[first]
anc_row <- ((anc_cell - 1L) %/% nc) + 1L
anc_col <- ((anc_cell - 1L) %% nc) + 1L
cat(sprintf("锚点数: %d ; 首个锚点 row=%d col=%d\n", length(anc_cell), anc_row[1], anc_col[1]))

anchor <- integer(nr * nc); anchor[anc_cell] <- 1L
parea  <- integer(nr * nc); parea[nz] <- areas[lab_nz]
anchor_r <- terra::rast(bin_r); terra::values(anchor_r) <- as.numeric(anchor)
parea_r  <- terra::rast(bin_r); terra::values(parea_r)  <- as.numeric(parea)

rc <- 5L; d <- 2L * rc + 1L; off <- -rc:rc
yy <- matrix(rep(off, each = d), d, d); xx <- matrix(rep(off, times = d), d, d)
kern <- ifelse((xx^2 + yy^2) <= rc^2, 1, 0)
cnt_r <- terra::focal(anchor_r, w = kern, fun = "sum", na.policy = "all", na.rm = TRUE)
cnt_m <- round(terra::as.matrix(cnt_r, wide = TRUE))
cat(sprintf("focal 后: NA=%d ; =0 的 %s ; >=1 的 %s\n",
            sum(is.na(cnt_m)), format(sum(cnt_m == 0, na.rm = TRUE), big.mark = ","),
            format(sum(cnt_m >= 1, na.rm = TRUE), big.mark = ",")))

inside <- labm > 0L
idx_pad <- labm + 1L
anc_row_p <- c(NA_integer_, anc_row); anc_col_p <- c(NA_integer_, anc_col)
dy <- row(labm) - anc_row_p[idx_pad]
dx <- col(labm) - anc_col_p[idx_pad]
own_out <- inside & !is.na(dy) & ((dy^2 + dx^2) > rc^2)
cat(sprintf("own_out TRUE: %s\n", format(sum(own_out), big.mark = ",")))
cnt_m[own_out] <- cnt_m[own_out] + 1
cat(sprintf("补计后: >=1 的 %s (应接近 %s)\n",
            format(sum(cnt_m >= 1, na.rm = TRUE), big.mark = ","),
            format(sum(bin), big.mark = ",")))
cat(sprintf("  其中 cnt==0 且 inside 的: %s\n",
            format(sum(cnt_m == 0 & inside, na.rm = TRUE), big.mark = ",")))
