# R/tests/test_55_gap.R -- 采集交付树与实际进度的精确差值，供核验报告使用
Sys.setenv(CHECO_ROOT = "E:/CHECO26/N-SDM")
source("E:/CHECO26/N-SDM/R/_bootstrap.R", encoding = "UTF-8")

prov <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"),
                 fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
prov <- prov[prov$status == "active", ]
root <- PATH_COV()
ex <- file.exists(file.path(root, prov$layer_path))

cat(sprintf("溯源表 active: %d\n", nrow(prov)))
cat(sprintf("磁盘已有    : %d (%.2f%%)\n", sum(ex), 100 * mean(ex)))
cat(sprintf("尚缺        : %d\n\n", sum(!ex)))

ds <- sub("^glo/([^/]+)/.*$", "\\2", prov$layer_path)
ds <- paste(sub("^glo/([^/]+)/.*$", "\\1", prov$layer_path),
            sub("^glo/[^/]+/([^/]+)/.*$", "\\1", prov$layer_path), sep = "/")
tab <- data.frame(theme_dataset = names(tapply(ex, ds, length)),
                  total = as.integer(tapply(ex, ds, length)),
                  have  = as.integer(tapply(ex, ds, sum)),
                  stringsAsFactors = FALSE)
tab$missing <- tab$total - tab$have
tab$pct <- round(100 * tab$have / tab$total, 1)
tab <- tab[order(-tab$missing), ]
cat("按数据集（按缺口降序）:\n")
print(tab, row.names = FALSE)

cat(sprintf("\n合计: total=%d have=%d missing=%d\n",
            sum(tab$total), sum(tab$have), sum(tab$missing)))

# 文件大小
fs <- list.files(root, pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
cat(sprintf("\n交付树实际文件: %d 个, %.2f GB\n", length(fs), sum(file.size(fs)) / 1e9))

# 焦点层缺口
foc <- grepl("_f[0-9]+\\.tif$", prov$layer_path)
cat(sprintf("焦点层: 目标 %d, 已有 %d, 缺 %d\n", sum(foc), sum(ex & foc), sum(!ex & foc)))
cat(sprintf("非焦点: 目标 %d, 已有 %d, 缺 %d\n", sum(!foc), sum(ex & !foc), sum(!ex & !foc)))
