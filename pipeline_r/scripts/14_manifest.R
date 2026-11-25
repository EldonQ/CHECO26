# =============================================================================
# R/14_manifest.R  --  SHA-256 完整性清单 + 公开发布清单 + 受限层清单
#
# 与早期 qa2 工作区的 r16_manifest.py、r18_public_release.py 对齐（两脚本不在交付树内）
#
# 产出（均在 00_docs/）：
#   MANIFEST.csv                  CHECO 生产文件的 relpath / bytes / sha256 / mtime
#                                 （covariates/ + 生产掩膜 mask_china.tif + 网格模板 template_albers1km.tif；
#                                   species/ 物种记录与 masks/ 备选掩膜非本发布内容，不列）
#   PUBLIC_RELEASE_MANIFEST.csv   已核实并通过发布筛选的层（OPEN / NC）
#   RESTRICTED_LAYERS.csv         不可再分发的层及理由
#
# 逐层许可依据见 provenance_table.csv 与 LICENCE_REGISTRY.csv。
#   OPEN        CC BY 4.0 等可自由再分发
#   NC          仅限非商业使用（CC BY-NC 4.0）——可再分发但须标注
#   RESTRICTED  公开存档受源条款限制
#   UNVERIFIED  许可证据不足或相互冲突，暂不发布
#
# 关键变更：
#   * anthro/landscan 125 层 → RESTRICTED（移入 archive，不进交付）
#   * anthro/foothii  100 层 → 撤销（被 anthro/hfp 替代，移入 archive）
#   * anthro/hfp      125 层 → OPEN（CC BY 4.0）
#   * lulc/clcd     1,170 层 → OPEN（CC BY 4.0）
#   * lulc/hlu1km  18,440 层 → OPEN（CC BY 4.0）
# =============================================================================

suppressPackageStartupMessages({ library(digest) })
.root <- Sys.getenv("CHECO_ROOT", getwd())
.scripts <- if (dir.exists(file.path(.root, "R"))) "R" else "pipeline_r/scripts"
source(file.path(.root, .scripts, "_bootstrap.R"), encoding = "UTF-8")

# ---- 主流程 --------------------------------------------------------------
main <- function(mode = c("all", "hash", "release"), workers = 8L) {
  mode <- match.arg(mode)
  print_grid()
  data_root <- PATH_DATA()

  # ---- 1) SHA-256 清单 ----
  if (mode %in% c("all", "hash")) {
    # CHECO 环境变量发布清单：仅 covariates/ + 生产掩膜 mask_china.tif + 网格模板
    # template_albers1km.tif。species/（物种出现记录）与 masks/（备选掩膜）与本发布无关，不列。
    fs <- c(list.files(file.path(data_root, "covariates"), recursive = TRUE, full.names = TRUE),
            file.path(data_root, "mask_china.tif"),
            file.path(data_root, "template_albers1km.tif"))
    fs <- fs[file.exists(fs)]
    fs <- fs[!grepl("\\.(aux\\.xml|tmp\\.tif|tif\\.ovr)$", fs)]
    cat(sprintf("扫描 CHECO 发布文件: %d\n", length(fs)))
    total <- sum(file.size(fs))
    cat(sprintf("总大小: %.2f GB\n", total / 1e9))

    t0 <- Sys.time(); n <- 0L
    out <- vector("list", length(fs))
    for (i in seq_along(fs)) {
      fi <- file.info(fs[i])
      out[[i]] <- data.frame(
        relpath = sub(paste0("^", gsub("\\\\", "/", data_root), "/?"), "",
                      gsub("\\\\", "/", fs[i])),
        bytes = as.numeric(fi$size),
        sha256 = digest::digest(file = fs[i], algo = "sha256", serialize = FALSE),
        mtime = format(fi$mtime, "%Y-%m-%dT%H:%M:%S"),
        stringsAsFactors = FALSE)
      n <- n + 1L
      if (n %% 200 == 0)
        cat(sprintf("  %d / %d  (%.0f s, %.1f GB 已算)\n", n, length(fs),
                    as.numeric(difftime(Sys.time(), t0, units = "secs")),
                    sum(vapply(out[seq_len(n)], function(d) d$bytes, 0)) / 1e9))
    }
    man <- do.call(rbind, out)
    write.csv(man, file.path(PATH_DOCS(), "MANIFEST.csv"), row.names = FALSE,
              fileEncoding = "UTF-8")
    cat(sprintf("已写出 MANIFEST.csv: %d 行，%.0f 秒\n", nrow(man),
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }

  # ---- 2) 公开发布清单 / 受限层清单 ----
  if (mode %in% c("all", "release")) {
    prov <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"),
                     fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
    prov <- prov[prov$status == "active", ]
    cat(sprintf("active 层: %d\n", nrow(prov)))

    required <- c("licence", "licence_url", "attribution", "licence_status")
    missing <- setdiff(required, names(prov))
    if (length(missing)) {
      stop("Missing provenance licence columns: ", paste(missing, collapse = ", "),
           ". Run tools/build_licence_registry.R first.", call. = FALSE)
    }
    status <- prov$licence_status
    valid <- !is.na(status) &
      grepl("^(VERIFIED|PROBABLE|UNVERIFIED) \\((OPEN|NC|RESTRICTED|UNVERIFIED)\\)$", status)
    if (any(!valid)) {
      stop("Invalid or missing licence_status: ",
           paste(head(prov$layer_path[!valid]), collapse = ", "), call. = FALSE)
    }

    rel <- data.frame(
      relpath        = prov$layer_path,
      licence_class  = sub("^.*\\(([A-Z]+)\\)$", "\\1", status),
      licence_status = status,
      licence        = prov$licence,
      licence_url    = prov$licence_url,
      attribution    = prov$attribution,
      source_dataset = prov$source_dataset,
      source_doi_url = prov$source_doi_url,
      stringsAsFactors = FALSE)

    # 受限层单独一张表
    res <- rel[rel$licence_class == "RESTRICTED", ]
    write.csv(res, file.path(PATH_DOCS(), "RESTRICTED_LAYERS.csv"),
              row.names = FALSE, fileEncoding = "UTF-8")

    # Withhold legacy outputs with unusable topology, IDs or all-class patch metrics.
    withheld <- grepl("^reg/hydro/h90m/(direction|segment|sub-catchment)/", rel$relpath) |
      (grepl("^reg/lulc/glu1km/", rel$relpath) &
       grepl("patch(density|size)-all", rel$relpath))
    pub <- rel[rel$licence_status %in% c("VERIFIED (OPEN)", "VERIFIED (NC)") & !withheld, ]
    write.csv(pub, file.path(PATH_DOCS(), "PUBLIC_RELEASE_MANIFEST.csv"),
              row.names = FALSE, fileEncoding = "UTF-8")

    cat("\n许可证分级统计（active 层）:\n")
    print(table(rel$licence_class))
    cat(sprintf("\n拟公开发布: %d 层\n受限不可发布: %d 层\n", nrow(pub), nrow(res)))
  }
  invisible(NULL)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) a[1] else "all")
}
