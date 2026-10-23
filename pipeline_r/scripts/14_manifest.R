# =============================================================================
# R/14_manifest.R  --  SHA-256 完整性清单 + 公开发布清单 + 受限层清单
#
# 对应 Python: qa2/r16_manifest.py、r18_public_release.py
#
# 产出（均在 00_docs/）：
#   MANIFEST.csv                  data/ 下每个文件的 relpath / bytes / sha256 / mtime
#   PUBLIC_RELEASE_MANIFEST.csv   每层的许可证分级（OPEN / NC / UNVERIFIED）
#   RESTRICTED_LAYERS.csv         不可再分发的层及理由
#
# 许可证分级依据（全部已核实，见 LICENCE_MATRIX.md）：
#   OPEN        CC BY 4.0 等可自由再分发
#   NC          仅限非商业使用（CC BY-NC 4.0）——可再分发但须标注
#   RESTRICTED  禁止再分发（机构订阅 / FGDC 明确限制）
#   UNVERIFIED  许可证文本尚未读到——不得对外发布
#
# 关键变更（v2.0）：
#   * anthro/landscan 125 层 → RESTRICTED（移入 archive，不进交付）
#   * anthro/foothii  100 层 → 撤销（被 anthro/hfp 替代，移入 archive）
#   * anthro/hfp      125 层 → OPEN（CC BY 4.0）
#   * lulc/clcd     1,170 层 → OPEN（CC BY 4.0）
#   * lulc/hlu1km  18,440 层 → OPEN（CC BY 4.0）
# =============================================================================

suppressPackageStartupMessages({ library(digest) })
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

# ---- 许可证分级表（按数据集）----------------------------------------------
# 键 = relpath 的前三段（theme/dataset），值 = (class, reason)
LICENCE <- list(
  "bioclim/cnclim1km"             = c("OPEN",   "Derived from CHELSA V2.1 (CC BY 4.0) and China 1 km baseline climate; see LICENCE_MATRIX.md"),
  "bioclim/cnclim1km-ensmean"     = c("OPEN",   "Multi-GCM ensemble mean derived from CMIP6; CMIP6 model output is freely redistributable"),
  "bioclim/cnclim1km-bcc-csm2-mr" = c("OPEN",   "Single-GCM chain derived from CMIP6; freely redistributable"),
  "soil/csdlv2"                   = c("UNVERIFIED", "CSDLv2 licence text has not been read; see LICENCE_MATRIX.md section 2"),
  "lulc/glu1km"                   = c("OPEN",   "Global LULC projection dataset (Zhang et al. 2023, Sci Data); see LICENCE_MATRIX.md"),
  "lulc/clcd"                     = c("OPEN",   "CLCD v1.0.5, CC BY 4.0, DOI 10.5281/zenodo.18180184 (verified)"),
  "lulc/hlu1km"                   = c("OPEN",   "Harmonised LULC 1960-2100, CC BY 4.0, DOI 10.5281/zenodo.15017066 (verified)"),
  "anthro/smod"                   = c("OPEN",   "GHS-SMOD R2023A, CC BY 4.0 (copyright.txt verified)"),
  "anthro/hfp"                    = c("OPEN",   "Mu et al. annual HFP, CC BY 4.0, DOI 10.6084/m9.figshare.16571064.v8 (verified)"),
  "anthro/landscan"               = c("RESTRICTED", "LandScan Global is distributed by ORNL/East View under an institutional subscription licence that prohibits electronic redistribution"),
  "anthro/foothii"                = c("UNVERIFIED", "WCS Human Footprint licence text has not been read; superseded by anthro/hfp in v2.0"),
  "vege/agb2019"                  = c("UNVERIFIED", "Source licence text has not been read"),
  "vege/ch2019"                   = c("UNVERIFIED", "Source licence text has not been read"),
  "vege/catcd"                    = c("UNVERIFIED", "Source licence text has not been read"),
  "vege/glassndvi"                = c("UNVERIFIED", "Source licence text has not been read"),
  "hydro/h90m"                    = c("NC",     "Hydrography90m, CC BY-NC 4.0; redistribution permitted with attribution, commercial use prohibited"),
  "dist/h90m"                     = c("NC",     "Hydrography90m, CC BY-NC 4.0; redistribution permitted with attribution, commercial use prohibited"),
  "hydro/hydrosheds"              = c("RESTRICTED", "HydroSHEDS FGDC metadata states the data shall not be redistributed without explicit written permission"),
  "dist/grip4"                    = c("UNVERIFIED", "GRIP4 licence text has not been read"),
  "dist/osm"                      = c("OPEN",   "OpenStreetMap, ODbL 1.0; attribution and share-alike required"),
  "dist/gsw"                      = c("UNVERIFIED", "JRC Global Surface Water licence text has not been read"),
  "dist/smod"                     = c("OPEN",   "Derived from GHS-SMOD R2023A, CC BY 4.0"),
  "topo/chinadem"                 = c("UNVERIFIED", "Source licence text has not been read")
)

licence_of <- function(relpath_short) {
  # relpath 形如 glo/<theme>/<dataset>/...，分级键是 theme/dataset（第 2、3 段）
  parts <- strsplit(relpath_short, "/", fixed = TRUE)[[1]]
  key <- if (length(parts) >= 3) paste(parts[2:3], collapse = "/") else relpath_short
  v <- LICENCE[[key]]
  if (is.null(v)) return(c("UNVERIFIED", "No licence rule registered for this dataset"))
  v
}

# ---- 主流程 --------------------------------------------------------------
main <- function(mode = c("all", "hash", "release"), workers = 8L) {
  mode <- match.arg(mode)
  print_grid()
  data_root <- PATH_DATA()

  # ---- 1) SHA-256 清单 ----
  if (mode %in% c("all", "hash")) {
    fs <- list.files(data_root, recursive = TRUE, full.names = TRUE)
    fs <- fs[!grepl("\\.(aux\\.xml|tmp\\.tif|tif\\.ovr)$", fs)]
    cat(sprintf("扫描 data/ 下文件: %d\n", length(fs)))
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

    # 2026-10-21：优先使用源表里已注入的结构化许可列
    # （由 R/tools/build_licence_registry.R 从 LICENCE_REGISTRY.csv 写入）；
    # 没有时回落到本脚本内置的 LICENCE 列表。
    # 目的：每个发布层都带上可追溯的许可证名称、版本、链接、署名文本与证据等级。
    # 2026-10-21：源表已注入 4 列许可信息
    #   licence / licence_url / attribution / licence_status
    # 其中 licence_status 形如 "VERIFIED (OPEN)"，括号内是分级。
    # 详细证据在 LICENCE_REGISTRY.csv（21 行），不在逐层表里。
    has_cols <- all(c("licence", "licence_url", "attribution", "licence_status") %in% names(prov))
    if (has_cols && all(!is.na(prov$licence_status))) {
      cat("\n\u8bb8\u53ef\u4fe1\u606f\u6765\u6e90: provenance_table.csv \u7684 4 \u4e2a\u8bb8\u53ef\u5217\n")
      cls <- sub("^.*\\(([A-Z]+)\\)$", "\\1", prov$licence_status)
      rel <- data.frame(
        relpath        = prov$layer_path,
        licence_class  = cls,
        licence_status = prov$licence_status,
        licence        = prov$licence,
        licence_url    = prov$licence_url,
        attribution    = prov$attribution,
        source_dataset = prov$source_dataset,
        source_doi_url = prov$source_doi_url,
        stringsAsFactors = FALSE)
    } else {
      cat("\n\u8bb8\u53ef\u4fe1\u606f\u6765\u6e90: \u672c\u811a\u672c\u5185\u7f6e LICENCE \u5217\u8868\uff08\u65e7\u53e3\u5f84\uff09\n")
      cls2 <- t(vapply(prov$layer_path, licence_of, c("", "")))
      rel <- data.frame(
        relpath = prov$layer_path,
        licence_class = cls2[, 1],
        reason = cls2[, 2],
        source_dataset = prov$source_dataset,
        source_doi_url = prov$source_doi_url,
        stringsAsFactors = FALSE)
    }

    # 受限层单独一张表
    res <- rel[rel$licence_class == "RESTRICTED", ]
    write.csv(res, file.path(PATH_DOCS(), "RESTRICTED_LAYERS.csv"),
              row.names = FALSE, fileEncoding = "UTF-8")

    # 公开清单：排除 RESTRICTED
    pub <- rel[rel$licence_class != "RESTRICTED", ]
    write.csv(pub, file.path(PATH_DOCS(), "PUBLIC_RELEASE_MANIFEST.csv"),
              row.names = FALSE, fileEncoding = "UTF-8")

    cat("\n许可证分级统计（active 层）:\n")
    print(table(rel$licence_class))
    cat(sprintf("\n可公开发布: %d 层\n受限不可发布: %d 层\n", nrow(pub), nrow(res)))
  }
  invisible(NULL)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) a[1] else "all")
}
