# R/tools/build_licence_registry.R
# 建立逐数据集的结构化许可登记表，并把许可字段注入溯源表
#
# 动机（2026-10-21）：
#   原许可信息只有四档分级（OPEN / NC / RESTRICTED / UNVERIFIED）加一句话理由，
#   没有许可证名称、版本号、链接、署名文本、证据出处、核查日期。
#   这不足以支撑"CC BY 4.0 可以收录 + 署名"这个判断，也无法审计。
#
# 本脚本产出：
#   1) 00_docs/LICENCE_REGISTRY.csv      逐数据集的结构化许可登记（含生产层数，共 19 列）
#   2) provenance_table.csv 更新逐层许可及 NESDC 核查备注
# 发布与受限清单由 R/14_manifest.R release 生成。
#
# 证据等级：
#   verified   —— 读到官方 API / 许可证原文 / 发布方页面明示
#   probable   —— 有间接依据（如论文声明 CC BY），但未读到数据页面的许可条款
#   unverified —— 许可证据不足或相互冲突
#
# 用法：Rscript R/tools/build_licence_registry.R [dry|write]
.root <- Sys.getenv("CHECO_ROOT", getwd())
.scripts <- if (dir.exists(file.path(.root, "R"))) "R" else "pipeline_r/scripts"
source(file.path(.root, .scripts, "_bootstrap.R"), encoding = "UTF-8")

# ---------------------------------------------------------------------------
# 许可登记：每个数据集一行。字段含义见文件头。
# ---------------------------------------------------------------------------
registry <- function() {
  D <- function(key, label, cls, name, ver, spdx, url, attr, attr_text, sa,
                comm, redist, ev_type, ev_detail, ev_url, conf, action, checked = "2026-10-21") {
    data.frame(dataset_key = key, dataset_label = label, licence_class = cls,
               licence_name = name, licence_version = ver, licence_spdx = spdx,
               licence_url = url, attribution_required = attr,
               attribution_text = attr_text, share_alike = sa,
               commercial_use = comm, redistributable = redist,
               evidence_type = ev_type, evidence_detail = ev_detail,
               evidence_url = ev_url, checked_date = checked,
               confidence = conf, action = action, stringsAsFactors = FALSE)
  }
  nesdc <- function(key, label, citation, doi, record_id) {
    D(key, label, "UNVERIFIED", "NESDC data licence pending confirmation",
      "unknown", "NOASSERTION", "", NA, paste0(citation, "; NESDC dataset ", doi),
      NA, "unconfirmed", FALSE, "publisher_page_conflict",
      paste("The NESDC record labels its data-use licence CC BY-NC 4.0 but links to",
            "https://creativecommons.org/licenses/by/4.0/ (CC BY 4.0). The page also",
            "states that modification and redistribution require written permission."),
      paste0("https://www.nesdc.org.cn/sdo/detail?id=", record_id), "unverified",
      "Withhold; request confirmation of the applicable terms and permission for public redistribution of the 1 km derivatives",
      checked = "2026-11-25")
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
    "Copernicus", "https://storage.googleapis.com/water-world/downloads_ancillary/DataUsersGuidev2024_v.5.pdf#page=18", TRUE,
    "Source: EC JRC/Google. Pekel J.-F. et al., Nature 540, 418-422 (2016), doi:10.1038/nature20584",
    FALSE, "allowed", TRUE,
    "licence_text",
    "JRC Data Users Guide v5, page 18, states: 'All data here is produced under the Copernicus Programme and is provided free of charge, without restriction of use', with acknowledgement and citation required",
    "https://global-surface-water.appspot.com/download", "verified",
    "include with attribution and required citation", checked = "2026-11-25"),
  D("bioclim/chelsa21", "Present-day bioclimatic variables (CHELSA v2.1, 1981-2010)",
    "OPEN", "Creative Commons Zero 1.0 Universal", "1.0", "CC0-1.0",
    "https://creativecommons.org/publicdomain/zero/1.0/", FALSE,
    "Karger D.N. et al. (2021), CHELSA v2.1, EnviDat 10.16904/envidat.228.v2.1 (CC0-1.0; citation recommended)",
    FALSE, "allowed", TRUE,
    "publisher_page", "CHELSA official site (chelsa-climate.org) and EnviDat metadata record state CC0-1.0 (No Rights Reserved); verified 2026-11-13",
    "https://doi.org/10.16904/envidat.228.v2.1", "verified",
    "include; citation recommended (CC0 waives attribution requirement)"),
  D("bioclim/chelsa21-gfdl-esm4", "Future bioclimatic, CHELSA-downscaled GFDL-ESM4",
    "OPEN", "Creative Commons Zero 1.0 Universal", "1.0", "CC0-1.0",
    "https://creativecommons.org/publicdomain/zero/1.0/", FALSE,
    "Karger D.N. et al. (2021), CHELSA v2.1 (GFDL-ESM4), EnviDat 10.16904/envidat.228.v2.1 (CC0-1.0)",
    FALSE, "allowed", TRUE,
    "publisher_page", "CHELSA v2.1 downscaled CMIP6 GFDL-ESM4; CHELSA product CC0-1.0, CMIP6 model output freely redistributable; verified 2026-11-13",
    "https://doi.org/10.16904/envidat.228.v2.1", "verified",
    "include; citation recommended"),
  D("bioclim/chelsa21-ipsl-cm6a-lr", "Future bioclimatic, CHELSA-downscaled IPSL-CM6A-LR",
    "OPEN", "Creative Commons Zero 1.0 Universal", "1.0", "CC0-1.0",
    "https://creativecommons.org/publicdomain/zero/1.0/", FALSE,
    "Karger D.N. et al. (2021), CHELSA v2.1 (IPSL-CM6A-LR), EnviDat 10.16904/envidat.228.v2.1 (CC0-1.0)",
    FALSE, "allowed", TRUE,
    "publisher_page", "CHELSA v2.1 downscaled CMIP6 IPSL-CM6A-LR; CHELSA product CC0-1.0; verified 2026-11-13",
    "https://doi.org/10.16904/envidat.228.v2.1", "verified",
    "include; citation recommended"),
  D("bioclim/chelsa21-mpi-esm1-2-hr", "Future bioclimatic, CHELSA-downscaled MPI-ESM1-2-HR",
    "OPEN", "Creative Commons Zero 1.0 Universal", "1.0", "CC0-1.0",
    "https://creativecommons.org/publicdomain/zero/1.0/", FALSE,
    "Karger D.N. et al. (2021), CHELSA v2.1 (MPI-ESM1-2-HR), EnviDat 10.16904/envidat.228.v2.1 (CC0-1.0)",
    FALSE, "allowed", TRUE,
    "publisher_page", "CHELSA v2.1 downscaled CMIP6 MPI-ESM1-2-HR; CHELSA product CC0-1.0; verified 2026-11-13",
    "https://doi.org/10.16904/envidat.228.v2.1", "verified",
    "include; citation recommended"),
  D("bioclim/chelsa21-mri-esm2-0", "Future bioclimatic, CHELSA-downscaled MRI-ESM2-0",
    "OPEN", "Creative Commons Zero 1.0 Universal", "1.0", "CC0-1.0",
    "https://creativecommons.org/publicdomain/zero/1.0/", FALSE,
    "Karger D.N. et al. (2021), CHELSA v2.1 (MRI-ESM2-0), EnviDat 10.16904/envidat.228.v2.1 (CC0-1.0)",
    FALSE, "allowed", TRUE,
    "publisher_page", "CHELSA v2.1 downscaled CMIP6 MRI-ESM2-0; CHELSA product CC0-1.0; verified 2026-11-13",
    "https://doi.org/10.16904/envidat.228.v2.1", "verified",
    "include; citation recommended"),
  D("bioclim/chelsa21-ukesm1-0-ll", "Future bioclimatic, CHELSA-downscaled UKESM1-0-LL",
    "OPEN", "Creative Commons Zero 1.0 Universal", "1.0", "CC0-1.0",
    "https://creativecommons.org/publicdomain/zero/1.0/", FALSE,
    "Karger D.N. et al. (2021), CHELSA v2.1 (UKESM1-0-LL), EnviDat 10.16904/envidat.228.v2.1 (CC0-1.0)",
    FALSE, "allowed", TRUE,
    "publisher_page", "CHELSA v2.1 downscaled CMIP6 UKESM1-0-LL; CHELSA product CC0-1.0; verified 2026-11-13",
    "https://doi.org/10.16904/envidat.228.v2.1", "verified",
    "include; citation recommended"),
  D("bioclim/chelsa21-ensmean", "Future bioclimatic, ensemble mean of 5 CHELSA-downscaled GCMs",
    "OPEN", "Creative Commons Zero 1.0 Universal", "1.0", "CC0-1.0",
    "https://creativecommons.org/publicdomain/zero/1.0/", FALSE,
    "Karger D.N. et al. (2021), CHELSA v2.1 ensemble mean (GFDL-ESM4/IPSL-CM6A-LR/MPI-ESM1-2-HR/MRI-ESM2-0/UKESM1-0-LL), EnviDat 10.16904/envidat.228.v2.1 (CC0-1.0)",
    FALSE, "allowed", TRUE,
    "publisher_page", "Equal-weight mean of 5 CHELSA v2.1 downscaled CMIP6 GCMs (CC0-1.0); derived by CHECO26 pipeline; verified 2026-11-13",
    "https://doi.org/10.16904/envidat.228.v2.1", "verified",
    "include; citation recommended"),
  D("lulc/glu1km", "Global land use projection 2020-2100 (Zhang et al.)",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Zhang T., Cheng C. & Wu X., Mapping the spatial heterogeneity of global land use and land cover from 2020 to 2100 at a 1 km resolution, Sci Data 10, 748 (2023), 10.1038/s41597-023-02637-7",
    FALSE, "allowed", TRUE,
    "api", "The figshare version 1 data record explicitly assigns CC BY 4.0.",
    "https://api.figshare.com/v2/articles/23542860", "verified",
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
    "RESTRICTED", "HydroSHEDS Version 1 License Agreement (WWF)", "1", "LicenseRef-HydroSHEDS-Core-V1",
    "https://data.hydrosheds.org/file/technical-documentation/HydroSHEDS_TechDoc_v1_4.pdf#page=24", TRUE,
    "HydroSHEDS (WWF); Lehner B., Verdin K. & Jarvis A., New global hydrography derived from spaceborne elevation data, EOS Trans. 89(10), 93-94 (2008), doi:10.1029/2008EO100001",
    FALSE, "allowed for use subject to the agreement", FALSE, "licence_text",
    "Technical Documentation v1.4 for data version 1.1, Appendix A sections 1.2 and 2.1.2. Distribution of licensed materials incorporated in derivatives requires protective end-user or authorised distributor terms. Section 2.2 and Exhibit B specify attribution.",
    "https://www.hydrosheds.org/products/hydrosheds", "verified",
    "Withhold from the public deposit under the HydroSHEDS v1 agreement", checked = "2026-11-25"),
  D("soil/csdlv2", "China soil properties CSDLv2, 28 variables",
    "OPEN", "Creative Commons Attribution 4.0 International", "4.0", "CC-BY-4.0",
    "https://creativecommons.org/licenses/by/4.0/", TRUE,
    "Shi G. & Shangguan W., A China dataset of soil properties for land surface modelling (version 2, CSDLv2), National Tibetan Plateau / Third Pole Environment Data Center, 10.11888/Terre.tpdc.301235 (CC BY 4.0)",
    FALSE, "allowed", TRUE,
    "publisher_page",
    "The TPDC record page (data.tpdc.ac.cn/en/data/46ddd893-3b2b-4bb3-b9e6-b043f3c5c3a2) displays a 'License agreement' section reading 'Attribution 4.0 International (CC BY 4.0)'. NOTE: this licence field is NOT present in the Word-2003 XML metadata export from the same record (67 fields, no rights/license element), and the page itself is a JavaScript application that could not be fetched programmatically - the value was read from the rendered page on 2026-10-21. The local readme_EN.docx and 数据文档_CN.docx also state no licence.",
    "https://data.tpdc.ac.cn/en/data/46ddd893-3b2b-4bb3-b9e6-b043f3c5c3a2", "verified",
    "include with attribution"),
  D("topo/chinadem", "Copernicus DEM GLO-90 2021 and 1 km terrain derivatives",
    "OPEN", "Copernicus DEM GLO-90 licence", "GLO-90", "LicenseRef-Copernicus-DEM-GLO90",
    "https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf", TRUE,
    "Produced using Copernicus WorldDEM-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.",
    FALSE, "allowed", TRUE, "licence_text",
    "Copernicus WorldDEM-90 terms, including attribution for modified data.",
    "https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf", "verified",
    "include with required Copernicus attribution"),
  nesdc("vege/ch2019", "Forest canopy height 2019 (GEDI + ICESat-2)",
        "Liu X., Su Y., Hu T., Yang Q. et al., Neural network guided interpolation for mapping canopy height of China's forests by integrating GEDI and ICESat-2 data, Remote Sensing of Environment 269, 112844 (2022)",
        "10.12199/nesdc.ecodb.rs.2024.027", "672d67777e28174998e63250"),
  nesdc("vege/agb2019", "Forest aboveground biomass 2019",
        "Yang Q., Niu C., Liu X. et al., Mapping high-resolution forest aboveground biomass of China using multisource remote sensing data, GIScience & Remote Sensing 60(1), 2203303 (2023)",
        "10.12199/nesdc.ecodb.rs.2024.026", "672d67777e28174998e6324d"),
  nesdc("vege/glassndvi", "GLASS NDVI 2020-2022",
        "Yang J., Dong J., Xiao X. et al., Divergent shifts in peak photosynthesis timing of temperate and alpine grasslands in China, Remote Sensing of Environment 233, 111395 (2019)",
        "10.12199/nesdc.ecodb.rs.2021.012", "60f68d757e28174f0e7d8d49"),
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
  key <- vapply(strsplit(sub("^reg/", "", act$layer_path), "/"),
                function(x) if (length(x) >= 2) paste(x[1], x[2], sep = "/") else x[1], "")
  tab <- table(key)
  reg$layers <- as.integer(tab[reg$dataset_key])
  reg$layers[is.na(reg$layers)] <- 0L

  # ---- 校验：登记表覆盖所有 active 数据集 ----
  missing <- setdiff(names(tab), reg$dataset_key)
  extra   <- setdiff(reg$dataset_key, names(tab))
  cat(sprintf("登记表 %d 个数据集；磁盘 %d 个 active 数据集\n", nrow(reg), length(tab)))
  if (length(missing) || anyDuplicated(reg$dataset_key)) {
    stop("Invalid licence registry coverage. Missing: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  if (length(extra))   cat("  **登记表有但磁盘无**: ", paste(extra, collapse = ", "), "\n")
  cat(sprintf("层数合计: %s （应为 %s）\n",
              format(sum(reg$layers), big.mark = ","),
              format(nrow(act), big.mark = ",")))

  cat("\n按许可分级:\n"); print(table(reg$licence_class))
  cat("\n按证据等级:\n"); print(table(reg$confidence))
  cat(sprintf("\n登记为可按许可分发的生产层数: %s\n", format(sum(reg$layers[reg$redistributable]), big.mark = ",")))
  cat(sprintf("许可受限或待核实的生产层数: %s\n", format(sum(reg$layers[!reg$redistributable]), big.mark = ",")))

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
  # 完整证据留在 LICENCE_REGISTRY.csv，冲突摘要同步至涉及图层的 notes。
  m <- match(key, reg$dataset_key)
  add <- data.frame(
    licence        = reg$licence_spdx[m],
    licence_url    = reg$licence_url[m],
    attribution    = reg$attribution_text[m],
    licence_status = sprintf("%s (%s)", toupper(reg$confidence[m]), reg$licence_class[m]),
    stringsAsFactors = FALSE
  )
  cols <- names(add)
  for (cc in setdiff(cols, names(prov))) prov[[cc]] <- NA_character_
  active <- which(prov$status == "active")
  prov[active, cols] <- add

  marker <- " [Licence audit] "
  notes <- prov$notes[active]
  notes[is.na(notes)] <- ""
  previous <- grepl(marker, notes, fixed = TRUE)
  notes[previous] <- sub(" \\[Licence audit\\] .*$", "", notes[previous])
  conflict <- reg$evidence_type[m] == "publisher_page_conflict"
  needs_update <- previous | conflict
  notes[conflict] <- paste0(notes[conflict], marker, reg$evidence_detail[m[conflict]],
                            " Source: ", reg$evidence_url[m[conflict]])
  prov$notes[active[needs_update]] <- notes[needs_update]

  # Correct the source identifiers verified in this licence audit.
  hydro <- active[key == "hydro/hydrosheds"]
  prov$source_doi_url[hydro] <- sub("2008EO150004", "2008EO100001", prov$source_doi_url[hydro], fixed = TRUE)
  prov$source_citation[hydro] <- sub("2008EO150004", "2008EO100001", prov$source_citation[hydro], fixed = TRUE)
  nesdc_rows <- active[conflict]
  prov$source_doi_url[nesdc_rows] <- sub("\\.$", "", prov$source_doi_url[nesdc_rows])
  prov$source_citation[nesdc_rows] <- sub("(10[.]12199/nesdc[.]ecodb[.]rs[.][0-9]{4}[.][0-9]{3})[.]", "\\1",
                                         prov$source_citation[nesdc_rows])

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
