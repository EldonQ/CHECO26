# R/tools/build_licence_registry.R
# 建立逐数据集的结构化许可登记表，并把许可字段注入溯源表
#
# 动机（2026-10-21）：
#   原许可信息只有四档分级（OPEN / NC / RESTRICTED / UNVERIFIED）加一句话理由，
#   没有许可证名称、版本号、链接、署名文本、证据出处、核查日期。
#   这不足以支撑"CC BY 4.0 可以收录 + 署名"这个判断，也无法审计。
#
# 本脚本产出：
#   1) 00_docs/LICENCE_REGISTRY.csv      逐数据集的结构化许可登记（18 个字段）
#   2) provenance_table.csv 追加 11 个许可列（每层都带可追溯的许可信息）
#   3) PUBLIC_RELEASE_MANIFEST.csv      追加同样的许可列
#   4) RESTRICTED_LAYERS.csv            追加同样的许可列
#
# 证据等级：
#   verified   —— 读到官方 API / 许可证原文 / 发布方页面明示
#   probable   —— 有间接依据（如论文声明 CC BY），但未读到数据页面的许可条款
#   unverified —— 没有读到任何许可文本，标为待审
#
# 用法：Rscript R/tools/build_licence_registry.R [dry|write]
Sys.setenv(CHECO_ROOT = Sys.getenv("CHECO_ROOT", getwd()))
source(file.path(Sys.getenv("CHECO_ROOT", getwd()), "R/_bootstrap.R"), encoding = "UTF-8")

# ---------------------------------------------------------------------------
# 许可登记：每个数据集一行。字段含义见文件头。
# ---------------------------------------------------------------------------
registry <- function() {
  D <- function(key, label, cls, name, ver, spdx, url, attr, attr_text, sa,
                comm, redist, ev_type, ev_detail, ev_url, conf, action) {
    data.frame(dataset_key = key, dataset_label = label, licence_class = cls,
               licence_name = name, licence_version = ver, licence_spdx = spdx,
               licence_url = url, attribution_required = attr,
               attribution_text = attr_text, share_alike = sa,
               commercial_use = comm, redistributable = redist,
               evidence_type = ev_type, evidence_detail = ev_detail,
               evidence_url = ev_url, checked_date = "2026-10-21",
               confidence = conf, action = action, stringsAsFactors = FALSE)
  }
  rbind(
  D("lulc/hlu1km", "Harmonised global land use 1960-2100 (Woodman et al.)",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Woodman et al., Harmonised global land use and land cover maps 1960-2100, Zenodo 10.5281/zenodo.15017066 (CC BY 4.0)",
    FALSE, "allowed", TRUE,
    "api", "Zenodo API returned license.id = cc-by-4.0; local file size matches the official record byte-for-byte",
    "https://doi.org/10.5281/zenodo.15017066", "verified",
    "include with attribution"),
  D("lulc/clcd", "CLCD annual land cover 2000-2025 (Yang & Huang)",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Yang J. & Huang X., CLCD v1.0.5, Zenodo 10.5281/zenodo.18180184 (CC BY 4.0)",
    FALSE, "allowed", TRUE,
    "api", "Zenodo API returned CC BY 4.0; md5 of 2000/2010/2020/2025 local files identical to the official records",
    "https://doi.org/10.5281/zenodo.18180184", "verified",
    "include with attribution"),
  D("anthro/hfp", "Annual Human Footprint 2000-2024 (Mu et al.)",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Mu H. et al., A global record of annual terrestrial Human Footprint dataset, figshare 10.6084/m9.figshare.16571064.v8 (CC BY 4.0)",
    FALSE, "allowed", TRUE,
    "api", "figshare API returned license.name = 'CC BY 4.0'",
    "https://doi.org/10.6084/m9.figshare.16571064.v8", "verified",
    "include with attribution"),
  D("anthro/smod", "GHS-SMOD settlement layers (JRC)",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Schiavina M., Melchiorri M. & Pesaresi M., GHS-SMOD R2023A, European Commission JRC, 10.2905/A0DF7A6F-49DE-46EA-9BDE-563437A6E2BA (CC BY 4.0)",
    FALSE, "allowed", TRUE,
    "licence_text", "copyright.txt shipped in the GHSL download package, read locally",
    "https://doi.org/10.2905/A0DF7A6F-49DE-46EA-9BDE-563437A6E2BA", "verified",
    "include with attribution"),
  D("dist/smod", "Distance to settlements (derived from GHS-SMOD)",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Derived from GHS-SMOD R2023A (CC BY 4.0); see anthro/smod",
    FALSE, "allowed", TRUE,
    "licence_text", "Inherits the licence of the parent dataset anthro/smod",
    "https://doi.org/10.2905/A0DF7A6F-49DE-46EA-9BDE-563437A6E2BA", "verified",
    "include with attribution"),
  D("dist/osm", "Distance to the OSM road network",
    "OPEN", "Open Database License", "1.0", "ODbL-1.0",
    "https://opendatacommons.org/licenses/odbl/1-0/", TRUE,
    "OpenStreetMap contributors, ODbL 1.0, https://www.openstreetmap.org/copyright",
    TRUE, "allowed", TRUE,
    "publisher_page", "OpenStreetMap official copyright page states ODbL 1.0 with share-alike",
    "https://www.openstreetmap.org/copyright", "verified",
    "include with attribution and ODbL share-alike notice"),
  D("dist/gsw", "Distance to surface water (JRC Global Surface Water)",
    "OPEN", "Copernicus data policy (free, without restriction of use)", "n/a",
    "Copernicus", "http://www.copernicus.eu/main/data-access/", TRUE,
    "Source: EC JRC/Google. Pekel J.-F. et al., Nature 540, 418-422 (2016), doi:10.1038/nature20584",
    FALSE, "allowed", TRUE,
    "publisher_page",
    "JRC download page states: 'All data here is produced under the Copernicus Programme and is provided free of charge, without restriction of use', with acknowledgement and citation required",
    "https://global-surface-water.appspot.com/download", "verified",
    "include with attribution and required citation"),
  D("bioclim/cnclim1km", "Present-day bioclimatic variables (cnclim1km)",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Hu X. et al., A 1 km monthly dataset of historical and future climate changes over China V8, Science Data Bank 10.57760/sciencedb.13546 (CC BY 4.0)",
    FALSE, "allowed", TRUE,
    "record_text", "Source record states 'Licence CC BY 4.0' (transcribed in scripts/srcmeta.py)",
    "https://doi.org/10.57760/sciencedb.13546", "probable",
    "include with attribution"),
  D("bioclim/cnclim1km-ensmean", "Future bioclimatic, multi-GCM ensemble mean",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Derived from cnclim1km V8 (CC BY 4.0) and CMIP6 model output; see bioclim/cnclim1km",
    FALSE, "allowed", TRUE,
    "record_text", "Inherits the licence of the parent dataset bioclim/cnclim1km",
    "https://doi.org/10.57760/sciencedb.13546", "probable",
    "include with attribution"),
  D("bioclim/cnclim1km-bcc-csm2-mr", "Future bioclimatic, single-GCM chain",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Derived from cnclim1km V8 (CC BY 4.0) and CMIP6 model output; see bioclim/cnclim1km",
    FALSE, "allowed", TRUE,
    "record_text", "Inherits the licence of the parent dataset bioclim/cnclim1km",
    "https://doi.org/10.57760/sciencedb.13546", "probable",
    "include with attribution"),
  D("lulc/glu1km", "Global land use projection 2020-2100 (Zhang et al.)",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Zhang T., Cheng C. & Wu X., Mapping the spatial heterogeneity of global land use and land cover from 2020 to 2100 at a 1 km resolution, Sci Data 10, 748 (2023), 10.1038/s41597-023-02637-7",
    FALSE, "allowed", TRUE,
    "journal_article", "Scientific Data is fully open access under CC BY 4.0; the data record itself was not re-read in this check",
    "https://doi.org/10.1038/s41597-023-02637-7", "probable",
    "include with attribution"),
  D("hydro/h90m", "Hydrography90m, 39 delivered variables (Amatulli et al.)",
    "NC", "Creative Commons Attribution-NonCommercial 4.0 International", "4.0",
    "CC-BY-NC-4.0", "https://creativecommons.org/licenses/by-nc/4.0/", TRUE,
    "Amatulli G. et al., Hydrography90m, Earth Syst. Sci. Data 14, 4525-4550 (2022), data 10.18728/igb-fred-762.1 (CC BY-NC 4.0)",
    FALSE, "not allowed", TRUE,
    "licence_text", "Original licence text read locally; CC BY-NC 4.0",
    "https://doi.org/10.18728/igb-fred-762.1", "verified",
    "include with attribution and NonCommercial notice"),
  D("dist/h90m", "Distance to the Hydrography90m network",
    "NC", "Creative Commons Attribution-NonCommercial 4.0 International", "4.0",
    "CC-BY-NC-4.0", "https://creativecommons.org/licenses/by-nc/4.0/", TRUE,
    "Derived from Hydrography90m (CC BY-NC 4.0); see hydro/h90m",
    FALSE, "not allowed", TRUE,
    "licence_text", "Inherits the licence of the parent dataset hydro/h90m",
    "https://doi.org/10.18728/igb-fred-762.1", "verified",
    "include with attribution and NonCommercial notice"),
  D("hydro/hydrosheds", "Flow accumulation from HydroSHEDS Core v1.1 (ACC)",
    "RESTRICTED", "HydroSHEDS Version 1 License Agreement (WWF)", "1.1", "NOASSERTION",
    "https://www.hydrosheds.org/hydrosheds-core-downloads", TRUE,
    "HydroSHEDS (WWF); Lehner B., Verdin K. & Jarvis A., New global hydrography derived from spaceborne elevation data, EOS Trans. 89(10), 93-94 (2008), doi:10.1029/2008EO150004",
    FALSE, "allowed for use; not for redistribution", FALSE,
    "licence_text", "LICENCE TEXT OBTAINED AND READ, 2026-10-21. Source: HydroSHEDS Technical Documentation v1.4 (April 2022, 29 pp, downloaded from data.hydrosheds.org), Appendix A - 'HYDROSHEDS VERSION 1 - LICENSE AGREEMENT'. This is a commercial-style distribution licence, not an open licence. The operative clauses are: s1.2 - 'End Users' means parties licensed the Licensed Materials 'for such party's use and not for redistribution'; s2.1.1 - the grant is 'worldwide, nonexclusive, non-transferable' and runs to the Licensee, not to the public; s2.1.2 - Licensee may distribute the Licensed Materials only 'incorporated into any Derivative Works to End Users, subject to ... an end user license agreement with terms that are at least as protective', and 'In no event shall Licensee license or distribute the Licensed Materials as a stand-alone product'; further distribution to other distributors is prohibited. s7.1 states the core data are 'free for non-commercial and commercial USE' but refers all redistribution questions to Appendix A. CONSEQUENCE FOR CHECO26: our 1 km averaged and focal layers are Derivative Works that we may use and may distribute under a protective end-user agreement, but we hold no right to deposit them in a public repository under an open licence, and recipients may not redistribute them. They are therefore withheld from the public deposit. Written permission from WWF would be required to release them openly.",
    "https://www.hydrosheds.org/products/hydrosheds", "verified",
    "WITHHOLD from public deposit - the licence grants no right to redistribute under an open licence; written WWF permission required to release"),
  D("soil/csdlv2", "China soil properties CSDLv2, 28 variables",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Shi G. & Shangguan W., A China dataset of soil properties for land surface modelling (version 2, CSDLv2), National Tibetan Plateau / Third Pole Environment Data Center, 10.11888/Terre.tpdc.301235 (CC BY 4.0)",
    FALSE, "allowed", TRUE,
    "publisher_page",
    "The TPDC record page (data.tpdc.ac.cn/en/data/46ddd893-3b2b-4bb3-b9e6-b043f3c5c3a2) displays a 'License agreement' section reading 'Attribution 4.0 International (CC BY 4.0)'. NOTE: this licence field is NOT present in the Word-2003 XML metadata export from the same record (67 fields, no rights/license element), and the page itself is a JavaScript application that could not be fetched programmatically - the value was read from the rendered page on 2026-10-21. The local readme_EN.docx and 数据文档_CN.docx also state no licence.",
    "https://data.tpdc.ac.cn/en/data/46ddd893-3b2b-4bb3-b9e6-b043f3c5c3a2", "verified",
    "include with attribution"),
  D("topo/chinadem", "China 1 km DEM (elevation, slope, aspect, TRI)",
    "NC", "Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International",
    "4.0", "CC-BY-NC-SA-4.0", "https://creativecommons.org/licenses/by-nc-sa/4.0/",
    TRUE,
    "Tang G., Digital elevation model of China (1 km), A Big Earth Data Platform for Three Poles, National Tibetan Plateau Data Center (CC BY-NC-SA 4.0)",
    TRUE, "not allowed", TRUE,
    "publisher_page",
    "The TPDC record page (data.tpdc.ac.cn/en/data/12e91073-0181-44bf-8308-c50e5bd9a734) displays a 'License agreement' section reading 'Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)'. As with CSDLv2 this field is NOT in the Word-2003 XML metadata export (63 fields, no rights element) - the value was read from the rendered page on 2026-10-21. SHARE-ALIKE CONSEQUENCE: aspect and TRI are our own derivatives of the elevation layer, so all four topo layers inherit CC BY-NC-SA 4.0 and any further derivative must carry the same licence. The NC condition also means these four layers cannot be used commercially.",
    "https://data.tpdc.ac.cn/en/data/12e91073-0181-44bf-8308-c50e5bd9a734", "verified",
    "include with attribution, NonCommercial notice and ShareAlike notice"),
  D("vege/ch2019", "Forest canopy height 2019 (GEDI + ICESat-2)",
    "NC", "Creative Commons Attribution-NonCommercial 4.0 International", "4.0", "CC-BY-NC-4.0",
    "https://creativecommons.org/licenses/by-nc/4.0/", TRUE,
    "Liu X., Su Y., Hu T., Yang Q. et al., Neural network guided interpolation for mapping canopy height of China's forests by integrating GEDI and ICESat-2 data, Remote Sensing of Environment 269, 112844 (2022); data via NESDC, CC BY-NC 4.0",
    FALSE, "not allowed", TRUE,
    "publisher_page",
    "The NESDC record page displays a '数据使用许可协议' (data use licence agreement) field reading CC BY-NC 4.0, read from the rendered page on 2026-10-21. IMPORTANT DISTINCTION: the bundled ftp_download_*.txt states '仅限个人使用，请勿传播' (personal use only, do not propagate) - that clause governs the ACCESS CREDENTIALS, not the data. The data itself is licensed CC BY-NC 4.0, which permits redistribution provided the non-commercial restriction is stated. An earlier pass of this audit mis-read the credential clause as a data restriction and classified these layers as restricted; corrected here.",
    "http://www.nesdc.org.cn/", "verified",
    "include with attribution and NonCommercial notice"),
  D("vege/agb2019", "Forest aboveground biomass 2019",
    "NC", "Creative Commons Attribution-NonCommercial 4.0 International", "4.0", "CC-BY-NC-4.0",
    "https://creativecommons.org/licenses/by-nc/4.0/", TRUE,
    "Yang Q., Niu C., Liu X. et al., Mapping high-resolution forest aboveground biomass of China using multisource remote sensing data, GIScience & Remote Sensing 60(1), 2203303 (2023); data via NESDC, CC BY-NC 4.0",
    FALSE, "not allowed", TRUE,
    "publisher_page",
    "The NESDC record page displays a '数据使用许可协议' (data use licence agreement) field reading CC BY-NC 4.0, read from the rendered page on 2026-10-21. IMPORTANT DISTINCTION: the bundled ftp_download_*.txt states '仅限个人使用，请勿传播' (personal use only, do not propagate) - that clause governs the ACCESS CREDENTIALS, not the data. The data itself is licensed CC BY-NC 4.0, which permits redistribution provided the non-commercial restriction is stated. An earlier pass of this audit mis-read the credential clause as a data restriction and classified these layers as restricted; corrected here.",
    "http://www.nesdc.org.cn/", "verified",
    "include with attribution and NonCommercial notice"),
  D("vege/glassndvi", "GLASS NDVI 2020-2022",
    "NC", "Creative Commons Attribution-NonCommercial 4.0 International", "4.0", "CC-BY-NC-4.0",
    "https://creativecommons.org/licenses/by-nc/4.0/", TRUE,
    "Yang J., Dong J., Xiao X. et al., Divergent shifts in peak photosynthesis timing of temperate and alpine grasslands in China, Remote Sensing of Environment 233, 111395 (2019); data via NESDC, CC BY-NC 4.0",
    FALSE, "not allowed", TRUE,
    "publisher_page",
    "The NESDC record page displays a '数据使用许可协议' (data use licence agreement) field reading CC BY-NC 4.0, read from the rendered page on 2026-10-21. IMPORTANT DISTINCTION: the bundled ftp_download_*.txt states '仅限个人使用，请勿传播' (personal use only, do not propagate) - that clause governs the ACCESS CREDENTIALS, not the data. The data itself is licensed CC BY-NC 4.0, which permits redistribution provided the non-commercial restriction is stated. An earlier pass of this audit mis-read the credential clause as a data restriction and classified these layers as restricted; corrected here.",
    "http://www.nesdc.org.cn/", "verified",
    "include with attribution and NonCommercial notice"),
  D("vege/catcd", "Annual tree cover 1985-2025 (CATCD)",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Cai Y., Xu X., Nie S., Wang C., Zhu P., Xiong Y. & Liu X., CATCD: the first 30 m China annual tree cover dataset, Zenodo 10.5281/zenodo.19160322 (CC BY 4.0); article: ISPRS J. Photogramm. Remote Sens. 216, 240-258 (2024)",
    FALSE, "allowed", TRUE,
    "api", "Zenodo API record 19160322 returned license.id = cc-by-4.0 (access_right = open)",
    "https://doi.org/10.5281/zenodo.19160322", "verified",
    "include with attribution"),
  D("dist/grip4", "Distance to roads (GRIP4)",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Meijer J.R., Huijbregts M.A.J., Schotten K.C.G.J. & Schipper A.M., Global patterns of current and future road infrastructure, Environ. Res. Lett. 13, 064006 (2018); data: GRIP4 v4, Zenodo 10.5281/zenodo.6420961 (CC BY 4.0)",
    FALSE, "allowed", TRUE,
    "api", "Zenodo API record 6420961 ('Global patterns of current and future road infrastructure - Supplementary spatial data') returned license.id = cc-by-4.0 and access_right = open. PROVENANCE VERIFIED BYTE-FOR-BYTE: the two local downloads match the record's own checksums exactly - GRIP4_Region6_vector_shp.zip 710,996,606 bytes md5 e2f3ec7515284cdc8b812a6a7e76e089, and GRIP4_density_total.zip 3,641,668 bytes md5 24d3ed5c079f7a898fbc4a5d68be337a. NOTE A DISCREPANCY IN THE RECORD ITSELF: its structured license field says cc-by-4.0 while its description text says 'GRIP4 is provided under a Creative Commons License (CC-0)'. CC-0 is a public domain dedication and is strictly more permissive, so we adopt the stricter reading - CC BY 4.0 with attribution - which satisfies both statements.",
    "https://doi.org/10.5281/zenodo.6420961", "verified",
    "include with attribution")
  )
}

main <- function(mode = c("write", "dry")) {
  mode <- match.arg(mode)
  reg <- registry()

  # ---- 从磁盘取每数据集的层数 ----
  prov <- read.csv(file.path(PATH_DOCS(), "provenance_table.csv"),
                   fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE,
                   check.names = FALSE)
  act <- prov[prov$status == "active", ]
  key <- vapply(strsplit(sub("^glo/", "", act$layer_path), "/"),
                function(x) if (length(x) >= 2) paste(x[1], x[2], sep = "/") else x[1], "")
  tab <- table(key)
  reg$layers <- as.integer(tab[reg$dataset_key])
  reg$layers[is.na(reg$layers)] <- 0L

  # ---- 校验：登记表覆盖所有 active 数据集 ----
  missing <- setdiff(names(tab), reg$dataset_key)
  extra   <- setdiff(reg$dataset_key, names(tab))
  cat(sprintf("登记表 %d 个数据集；磁盘 %d 个 active 数据集\n", nrow(reg), length(tab)))
  if (length(missing)) cat("  **磁盘有但登记表缺**: ", paste(missing, collapse = ", "), "\n")
  if (length(extra))   cat("  **登记表有但磁盘无**: ", paste(extra, collapse = ", "), "\n")
  cat(sprintf("层数合计: %s （应为 %s）\n",
              format(sum(reg$layers), big.mark = ","),
              format(nrow(act), big.mark = ",")))

  cat("\n按许可分级:\n"); print(table(reg$licence_class))
  cat("\n按证据等级:\n"); print(table(reg$confidence))
  cat(sprintf("\n可再分发层数: %s\n", format(sum(reg$layers[reg$redistributable]), big.mark = ",")))
  cat(sprintf("不可再分发层数: %s\n", format(sum(reg$layers[!reg$redistributable]), big.mark = ",")))

  if (mode == "dry") { cat("\n[dry] 未写入。\n"); return(invisible(reg)) }

  # ---- 1) 写登记表 ----
  out <- file.path(PATH_DOCS(), "LICENCE_REGISTRY.csv")
  write.csv(reg, out, row.names = FALSE, fileEncoding = "UTF-8")
  cat("\n已写出 LICENCE_REGISTRY.csv\n")

  # ---- 2) 注入源表（只加 4 列）----
  # 2026-10-21 修：初版加了 13 列，其中 name/version/spdx 是同一件事的三种写法，
  # attribution_required 可由 attribution 是否为空推出，class/redistributable/action
  # 可由分级推出，evidence/checked 是数据集级信息。
  # 每层只需四列：licence（含版本）/ licence_url / attribution / licence_status。
  # 详细证据留在 LICENCE_REGISTRY.csv（21 行），不复制到 21,110 行里。
  m <- match(key, reg$dataset_key)
  lic <- ifelse(is.na(reg$licence_version[m]) | reg$licence_version[m] %in% c("n/a", "unknown"),
                reg$licence_spdx[m],
                paste0(reg$licence_spdx[m]))
  add <- data.frame(
    licence        = reg$licence_spdx[m],
    licence_url    = reg$licence_url[m],
    attribution    = reg$attribution_text[m],
    licence_status = ifelse(reg$confidence[m] == "unverified",
                            paste0("UNVERIFIED (", reg$licence_class[m], ")"),
                            paste0(toupper(reg$confidence[m]), " (", reg$licence_class[m], ")")),
    stringsAsFactors = FALSE
  )
  cols <- names(add)
  for (cc in cols) prov[[cc]] <- NA
  prov[prov$status == "active", cols] <- add

  prov_out <- file.path(PATH_DOCS(), "provenance_table.csv")
  bak <- paste0(prov_out, ".bak_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  file.copy(prov_out, bak, overwrite = FALSE)
  write.csv(prov, prov_out, row.names = FALSE, fileEncoding = "UTF-8")
  cat(sprintf("\n已注入 %d 列许可信息到 provenance_table.csv（%d 列 -> %d 列）\n",
              length(cols), ncol(prov) - length(cols), ncol(prov)))
  cat("  新增: ", paste(cols, collapse = ", "), "\n")
  cat(sprintf("  备份: %s\n", basename(bak)))
  invisible(reg)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(if (length(a) >= 1) a[1] else "write")
}
