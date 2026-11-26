# Build the human-readable licence matrix from the registry and deposit manifest.
.root <- Sys.getenv("CHECO_ROOT", getwd())
.scripts <- if (dir.exists(file.path(.root, "R"))) "R" else "pipeline_r/scripts"
source(file.path(.root, .scripts, "_bootstrap.R"), encoding = "UTF-8")

render_licence_matrix <- function(docs = PATH_DOCS()) {
  read_docs <- function(name) {
    read.csv(file.path(docs, name), fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
  }
  reg <- read_docs("LICENCE_REGISTRY.csv")
  pub <- read_docs("PUBLIC_RELEASE_MANIFEST.csv")
  inventory <- read_docs("MANIFEST.csv")
  eligible <- reg$confidence == "verified" & reg$licence_class %in% c("OPEN", "NC")
  is_restricted <- reg$licence_class == "RESTRICTED"
  withheld <- reg[!(eligible | is_restricted), ]
  restricted <- reg[is_restricted, ]
  production <- sum(reg$layers)
  files <- inventory[startsWith(inventory$relpath, "covariates/"), ]
  stopifnot(nrow(files) == production)
  quality <- sum(reg$layers[eligible]) - nrow(pub)
  fmt <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
  licence <- ifelse(is.na(reg$licence_url) | !nzchar(reg$licence_url), reg$licence_name,
                    sprintf("[%s](%s)", reg$licence_name, reg$licence_url))
  evidence <- sprintf("[%s](%s)", reg$confidence, reg$evidence_url)

  md <- c(
    "# CHECO26 逐源许可", "",
    "由 `R/tools/render_licence_matrix.R` 根据登记表和发布清单生成。", "",
    sprintf(
      "生产库含 %s 层（%.1f GB）。拟公开 %s 层，其中 %s 层为 OPEN，%s 层延续源数据的非商业许可。%s 层因许可待核实暂缓，%s 层因源许可受限不收录，%s 层因质量保留在内部。栅格公开存档待完成。",
      fmt(production), sum(files$bytes) / 1e9, fmt(nrow(pub)),
      fmt(sum(pub$licence_class == "OPEN")), fmt(sum(pub$licence_class == "NC")),
      fmt(sum(withheld$layers)), fmt(sum(restricted$layers)), fmt(quality)),
    "",
    "| 数据集 | 本地层数 | 分级 | 许可 | 证据 |", "|---|---:|---|---|---|",
    sprintf("| `%s` | %d | %s | %s | %s |",
            reg$dataset_key, reg$layers, reg$licence_class, licence, evidence),
    "", "## 许可待核实", "",
    sprintf("- `%s`（%d 层）。%s [%s](%s)",
            withheld$dataset_key, withheld$layers, withheld$evidence_detail,
            "数据专页", withheld$evidence_url),
    "",
    "NESDC 三组图层须由平台或权利人确认适用协议、1 km 派生栅格的公开再分发条件及署名要求。",
    "",
    "逐层署名和许可见 `provenance_table.csv`，证据细节及各行核查日期见 `LICENCE_REGISTRY.csv`。拟公开范围以 `PUBLIC_RELEASE_MANIFEST.csv` 为准。"
  )
  writeLines(enc2utf8(md), file.path(docs, "LICENCE_MATRIX.md"), useBytes = TRUE)
  invisible(md)
}

main <- function() render_licence_matrix()
if (sys.nframe() == 0L) main()
