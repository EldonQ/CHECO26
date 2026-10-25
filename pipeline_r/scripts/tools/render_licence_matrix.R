# R/tools/render_licence_matrix.R
# 从 LICENCE_REGISTRY.csv 生成 00_docs/LICENCE_MATRIX.md
#
# 动机：许可信息原先手写在 LICENCE_MATRIX.md 与 R/14_manifest.R 两处，容易漂移。
# 现在唯一来源是 LICENCE_REGISTRY.csv（由 build_licence_registry.R 写入），
# 本脚本只负责把它渲染成人读的 Markdown。
#
# 用法：Rscript R/tools/render_licence_matrix.R
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

reg <- read.csv(file.path(PATH_DOCS(), "LICENCE_REGISTRY.csv"),
                fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
stopifnot(sum(reg$layers) == 21110)

fmt <- function(x) format(x, big.mark = ",", scientific = FALSE)
L <- character(0)
add <- function(...) L <<- c(L, ...)

add("# 许可证矩阵与分发风险（2026-10-21 重建）", "",
    "本文件**由 `R/tools/render_licence_matrix.R` 从 `LICENCE_REGISTRY.csv` 自动生成**，",
    "请勿手工编辑。机器可读版本即该 CSV（逐数据集 19 个字段）。", "",
    "每层的许可信息也已写入 `provenance_table.csv` 的 4 个许可列
（`licence` / `licence_url` / `attribution` / `licence_status`），",
    "并随 `PUBLIC_RELEASE_MANIFEST.csv` / `RESTRICTED_LAYERS.csv` 一同发布。", "",
    "---", "",
    "## 一、分级总览", "",
    "| 分级 | 含义 | 层数 | 数据集数 | 能否公开分发 |",
    "|---|---|---:|---:|---|")

lab <- c(OPEN = "可自由再分发（CC BY 4.0 / ODbL / Copernicus 等）",
         NC = "仅限非商业使用（CC BY-NC 4.0）——可再分发但须标注",
         RESTRICTED = "明确限制再分发——必须移出公开存放",
         UNVERIFIED = "未读到许可证文本——投稿前必须核实")
for (k in c("OPEN", "NC", "RESTRICTED", "UNVERIFIED")) {
  n <- sum(reg$layers[reg$licence_class == k])
  d <- sum(reg$licence_class == k)
  if (n == 0) next
  yes <- if (k == "OPEN") "✅ 可以" else if (k == "NC") "✅ 可以（须标 NC）" else if (k == "RESTRICTED") "❌ 必须移除" else "⚠️ 待核实"
  add(sprintf("| **%s** | %s | **%s** | %d | %s |", k, lab[k], fmt(n), d, yes))
}
add("")
add(sprintf(paste0("**已确认可分发 %s 层（%.2f%%）**；受限不可分发 %s 层；",
                  "**待核实 %s 层**（未读到许可文本，不等于已确认受限）。"),
            fmt(sum(reg$layers[reg$redistributable])),
            100 * sum(reg$layers[reg$redistributable]) / 21110,
            fmt(sum(reg$layers[reg$licence_class == "RESTRICTED"])),
            fmt(sum(reg$layers[reg$licence_class == "UNVERIFIED"]))), "",
    "---", "",
    "## 二、证据等级", "",
    "| 等级 | 含义 | 层数 |",
    "|---|---|---:|")
for (k in c("verified", "probable", "unverified")) {
  n <- sum(reg$layers[reg$confidence == k])
  d <- if (k == "verified") "读到官方 API / 许可证原文 / 发布方页面明示" else
       if (k == "probable") "有间接依据（如论文声明 CC BY），未读到数据页面许可条款" else
       "没有任何许可文本，标为待审"
  add(sprintf("| `%s` | %s | %s |", k, d, fmt(n)))
}
add("", "**判据：只有 `verified` 才能作为投稿依据；`probable` 与 `unverified` 都需复审。**", "",
    "---", "", "## 三、逐数据集明细", "",
    "| 数据集 | 层数 | 分级 | 许可证 | 版本 | SPDX | 可再分发 | 证据 | 置信 | 处置 |",
    "|---|---:|---|---|---|---|---|---|---|---|")
ord <- order(match(reg$licence_class, c("RESTRICTED", "UNVERIFIED", "NC", "OPEN")), -reg$layers)
for (i in ord) {
  r <- reg[i, ]
  add(sprintf("| `%s` | %s | **%s** | %s | %s | `%s` | %s | %s | `%s` | %s |",
              r$dataset_key, fmt(r$layers), r$licence_class,
              r$licence_name, r$licence_version, r$licence_spdx,
              if (isTRUE(r$redistributable)) "✅" else "❌",
              r$evidence_type, r$confidence, r$action))
}

add("", "---", "", "## 四、许可证链接（逐数据集）", "",
    "| 数据集 | 许可证链接 | 署名文本 |", "|---|---|---|")
for (i in ord) {
  r <- reg[i, ]
  add(sprintf("| `%s` | %s | %s |", r$dataset_key, r$licence_url,
              gsub("|", "/", r$attribution_text, fixed = TRUE)))
}

add("", "---", "", "## 五、必须处理的事项", "")
add("### 5.1 RESTRICTED —— 不进公开存放", "")
for (i in which(reg$licence_class == "RESTRICTED")) {
  r <- reg[i, ]
  add(sprintf("**`%s`（%s 层）**", r$dataset_key, fmt(r$layers)), "",
      sprintf("- 许可证：%s", r$licence_name),
      sprintf("- 链接：%s", r$licence_url),
      sprintf("- 证据：%s", r$evidence_detail),
      sprintf("- 处置：%s", r$action), "")
}
add("### 5.2 UNVERIFIED —— 投稿前必须核实", "",
    "| 数据集 | 层数 | 缺什么 |", "|---|---:|---|")
for (i in which(reg$licence_class == "UNVERIFIED")) {
  r <- reg[i, ]
  add(sprintf("| `%s` | %s | %s |", r$dataset_key, fmt(r$layers),
              sub("^none: ", "", r$evidence_detail)))
}
add("")
add("### 5.3 NC —— 可发布但须标注", "",
    "以下数据集为 CC BY-NC 4.0：再分发允许，但必须在数据记录与文件说明中显著标注",
    "\"NonCommercial use only\"，并保留原始出处与许可声明。", "")
for (i in which(reg$licence_class == "NC")) {
  r <- reg[i, ]
  add(sprintf("- `%s`（%s 层）— %s", r$dataset_key, fmt(r$layers), r$licence_url))
}
add("", "---", "", "## 六、变更记录", "",
    "- **2026-10-21**：本文件改为由 `LICENCE_REGISTRY.csv` 自动生成；",
    "  新增许可证名称、版本、SPDX 标识、链接、署名文本、证据等级与核查日期；",
    "  逐层只注入 4 列（`licence` / `licence_url` / `attribution` / `licence_status`），
  详细证据保留在数据集级的 `LICENCE_REGISTRY.csv`，不复制到 21,110 行。",
    "  `dist/gsw`（1 层）由 UNVERIFIED 改为 **OPEN**：JRC 下载页面明示",
    "  \"free of charge, without restriction of use\"（Copernicus Programme），",
    "  要求署名并引用 Pekel et al. 2016。UNVERIFIED 因此从 233 层降为 232 层。",
    "- **2026-10-21**：`hydro/hydrosheds`（5 层）的置信度由 implied 改为 **unverified**：",
    "  官方 v1 产品页确认许可含再分发限制，但**许可原文未能取到**（PDF 跨域被拦），",
    "  本地也无留存副本。此前引用的 FGDC 原句无法追溯，已标注为待审。")

out <- file.path(PATH_DOCS(), "LICENCE_MATRIX.md")
writeLines(L, out, useBytes = FALSE)
cat(sprintf("已写出 LICENCE_MATRIX.md（%d 行）\n", length(L)))
cat(sprintf("覆盖 %d 个数据集，%s 层\n", nrow(reg), fmt(sum(reg$layers))))
