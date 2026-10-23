# R/tests/test_06_warp_diag.R
# 分离"几何差异"与"插值差异"：
#   A) R nearest  vs Python nearest  -> 若一致，几何相同
#   B) R bilinear vs Python bilinear -> 若不一致而 A 一致，则插值实现不同
#   C) Python bilinear vs 既有交付层  -> 顺带验证既有层确实是 bilinear 产物

Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/00_config.R"), encoding = "UTF-8")
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/01_common.R"), encoding = "UTF-8")

read_clean <- function(path) {
  r <- terra::rast(path)
  nd <- terra::NAflag(r)
  v <- terra::values(r, mat = FALSE)
  if (!is.na(nd)) v[!is.na(v) & v == nd] <- NA
  v[is.nan(v)] <- NA
  terra::values(r) <- v
  r
}

compare <- function(a, b, tag) {
  av <- terra::values(a, mat = FALSE); bv <- terra::values(b, mat = FALSE)
  ok <- !is.na(av) & !is.na(bv)
  d <- abs(av[ok] - bv[ok])
  span <- diff(range(bv[ok]))
  cat(sprintf("%-34s 共有效 %10s | 仅A %5d 仅B %5d | max|d| %10.3e | max|d|/span %9.2e\n",
              tag, format(sum(ok), big.mark = ","),
              sum(!is.na(av) & is.na(bv)), sum(is.na(av) & !is.na(bv)),
              max(d), max(d)/span))
  cat(sprintf("%-34s   |d|>0.01: %8s   |d|>0.1: %8s   |d|>0.5: %8s\n", "",
              format(sum(d > 0.01), big.mark = ","),
              format(sum(d > 0.1), big.mark = ","),
              format(sum(d > 0.5), big.mark = ",")))
  invisible(list(n = sum(ok), max = max(d), span = span))
}

cfg <- CFG()
src <- file.path(P("bioclim"), "cnclim1km/present/1991_2020/bio01",
                 "bioclim_cnclim1km_present_1991_2020_bio01.tif")
diag <- file.path(PATH_SCRATCH(), "diag_warp")
ref_existing <- file.path(PATH_COV(), "glo/bioclim/cnclim1km/present/bio01",
                          "glo_bioclim_cnclim1km_present_bio01.tif")

cat("=== warp 差异来源判定 ===\n\n")

dst_n <- file.path(diag, "r_bio01_nearest.tif")
dst_b <- file.path(diag, "r_bio01_bilinear.tif")
warp_to_template(src, dst_n, method = "near")
warp_to_template(src, dst_b, method = "bilinear")

a_n <- read_clean(dst_n); a_b <- read_clean(dst_b)
p_n <- read_clean(file.path(diag, "py_bio01_nearest.tif"))
p_b <- read_clean(file.path(diag, "py_bio01_bilinear.tif"))
e_b <- read_clean(ref_existing)

compare(a_n, p_n, "A) R nearest  vs Python nearest")
compare(a_b, p_b, "B) R bilinear vs Python bilinear")
compare(p_b, e_b, "C) Python bilinear vs 既有交付层")
compare(a_n, a_b, "D) R nearest vs R bilinear（自比）")
