# R/tools/check_table2.R -- 核验论文 Table 2 的每个数据集层数与磁盘一致
#
# 2026-10-21 新增。动机：`check_docs_consistency.R` 只检查**主题合计**
# （lulc 20,150 / bioclim 532 / ...），不检查**数据集层级**。
# 若某数据集少一层、另一处多一层，主题合计仍然对得上，现有检查不会报警。
# Table 2 有 21 个数据集 x 一个数字，值得单独核。
#
# 为什么用显式映射表而不是从 Markdown 解析：
#   · `smod` 在两个主题下各有一个（anthro/smod 12、dist/smod 1）；
#   · `h90m` 同理（hydro/h90m 39、dist/h90m 12）；
#   · dist 的四个数据集在论文里合并为一行 `grip4 / gsw / osm / smod (dist) | 17`。
#   自动解析在这些情形下会错配或漏配，所以这里把"论文行 -> 磁盘键"写死。
#
# 用法：Rscript R/tools/check_table2.R
ROOT <- "E:/CHECO26/N-SDM"

# 论文 Table 2 的行  ->  磁盘上的 theme/dataset 键（多个键表示论文里合并成一行）
MAP <- list(
  "hlu1km"                = "lulc/hlu1km",
  "clcd"                  = "lulc/clcd",
  "glu1km"                = "lulc/glu1km",
  "cnclim1km"             = "bioclim/cnclim1km",
  "cnclim1km-ensmean"     = "bioclim/cnclim1km-ensmean",
  "cnclim1km-bcc-csm2-mr" = "bioclim/cnclim1km-bcc-csm2-mr",
  "csdlv2"                = "soil/csdlv2",
  "hfp"                   = "anthro/hfp",
  "smod"                  = "anthro/smod",
  "h90m"                  = "hydro/h90m",
  "hydrosheds"            = "hydro/hydrosheds",
  "glassndvi"             = "vege/glassndvi",
  "ch2019"                = "vege/ch2019",
  "agb2019"               = "vege/agb2019",
  "catcd"                 = "vege/catcd",
  "chinadem"              = "topo/chinadem",
  "dist (grip4/gsw/osm/smod)" = c("dist/grip4", "dist/gsw", "dist/osm", "dist/smod", "dist/h90m")
)

# 论文 Table 2 里写下的数字（必须与文档逐字一致，改文档时同步改这里）
PAPER_N <- c(
  hlu1km = 18440, clcd = 1170, glu1km = 540,
  cnclim1km = 28, `cnclim1km-ensmean` = 252, `cnclim1km-bcc-csm2-mr` = 252,
  csdlv2 = 196, hfp = 125, smod = 12, h90m = 39, hydrosheds = 5,
  glassndvi = 15, ch2019 = 5, agb2019 = 5, catcd = 5, chinadem = 4,
  `dist (grip4/gsw/osm/smod)` = 17
)

man <- read.csv(file.path(ROOT, "00_docs", "MANIFEST.csv"),
                fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
cov <- man[grepl("^covariates/", man$relpath), ]
rel <- sub("^covariates/glo/", "", cov$relpath)
key <- sapply(strsplit(rel, "/"), function(x) paste(x[1], x[2], sep = "/"))
tb  <- table(key)

cat("=== Table 2 \u6570\u636e\u96c6\u5c42\u6570\u6838\u9a8c ===\n")
nbad <- 0L
for (nm in names(MAP)) {
  d <- sum(as.integer(tb[names(tb) %in% MAP[[nm]]]))
  claimed <- as.integer(PAPER_N[[nm]])
  okk <- identical(d, claimed)
  if (!okk) nbad <- nbad + 1L
  cat(sprintf("  %-28s \u8bba\u6587 %6d  \u78c1\u76d8 %6d  %s\n", nm, claimed, d,
              if (okk) "OK" else "**\u4e0d\u4e00\u81f4**"))
}
cat(sprintf("\n  \u5408\u8ba1 %d / %d \u4e00\u81f4\n", length(MAP) - nbad, length(MAP)))
tot <- sum(as.integer(PAPER_N))
cat(sprintf("  \u8bba\u6587\u5404\u884c\u4e4b\u548c %d ; \u78c1\u76d8 covariates \u603b\u6570 %d  %s\n",
            tot, nrow(cov),
            if (identical(tot, nrow(cov))) "OK" else "**\u4e0d\u7b49**"))
invisible(nbad)
