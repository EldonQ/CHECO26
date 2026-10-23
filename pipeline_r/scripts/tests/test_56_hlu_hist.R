# R/tests/test_56_hlu_hist.R
# 验证文档中的声称："历史段 1960-2020 在五个情景文件中逐像元相同"
# 只在 China 窗口内比较，抽 6 个年份，五个文件两两对比。
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

DIR <- file.path(PATH_ARCHIVE(), "harmonised", "Harmonised-1960-2100")
FILES <- c("SSP1_RCP26_country-f.tif", "SSP2_RCP45_country-f.tif", "SSP3_RCP70_country-f.tif",
           "SSP4_RCP60_country-f.tif", "SSP5_RCP85_country-f.tif")
WIN <- c(70, 140, 12, 58)

read_win <- function(f, y) {
  r <- terra::rast(file.path(DIR, f))[[as.integer(y) - 1959L]]
  v <- terra::values(terra::crop(r, terra::ext(WIN[1], WIN[2], WIN[3], WIN[4]), snap = "out"),
                     mat = FALSE)
  v
}

cat("=== harmonised 源：历史段五文件一致性 ===\n")
cat(sprintf("五个文件 × %d 个年份，逐像元比较（China 窗口）\n\n", 6))

years <- c(1960L, 1980L, 1990L, 2005L, 2015L, 2020L)
allok <- TRUE
for (y in years) {
  base <- read_win(FILES[1], y)
  res <- character(0)
  ok <- TRUE
  for (f in FILES[-1]) {
    v <- read_win(f, y)
    if (length(v) != length(base)) { res <- c(res, "长度不符"); ok <- FALSE; next }
    na1 <- is.na(base); na2 <- is.na(v)
    same_na <- identical(na1, na2)
    d <- sum(abs(base[!na1 & !na2] - v[!na1 & !na2]) > 0)
    bad <- (!same_na) || (d > 0)
    if (bad) { ok <- FALSE; res <- c(res, sprintf("%s: NA差=%s 值差=%d",
                 sub("_country-f.tif$", "", f), !same_na, d)) }
  }
  cat(sprintf("  %d (band %3d): %s", y, y - 1959L, ifelse(ok, "五文件完全相同", "差异 ->")))
  if (!ok) cat(" ", paste(res, collapse = "; ")) 
  cat("\n")
  allok <- allok && ok
}

cat(sprintf("\n=== 结论：%s ===\n", ifelse(allok,
    "抽检的 6 个历史年份在五个文件中逐像元完全相同 -> 文档声称成立",
    "存在差异 -> 文档声称需要修正")))

# 顺带：未来段应当不同（反证）
cat("\n=== 反证：未来段应当不同 ===\n")
y <- 2100L
base <- read_win(FILES[1], y)
for (f in FILES[-1]) {
  v <- read_win(f, y)
  na1 <- is.na(base); na2 <- is.na(v)
  d <- sum(abs(base[!na1 & !na2] - v[!na1 & !na2]) > 0)
  cat(sprintf("  %d SSP1 vs %-10s : 值不同的像元 %d (%.2f%%)\n", y,
              sub("_country-f.tif$", "", f), d, 100 * d / sum(!na1 & !na2)))
}
