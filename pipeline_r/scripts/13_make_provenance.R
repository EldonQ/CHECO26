# =============================================================================
# R/13_make_provenance.R  --  溯源表生成
#
# 与早期 Python 版 make_provenance_table.py 逐项对齐；后者已不能重建全表（层域来自
# 一份已删除的迁移映射），已于 2026-11-11 从 scripts/ 删除
#
# 设计：
#   现有 00_docs/provenance_table.csv 的行**已逐行人工校对通过**，
#   故不重推已有行，而是：
#     1) 读入现有表
#     2) 剔除已撤出的 anthro/landscan（125）与 anthro/foothii（100）
#     3) 按各数据集清单生成新行（anthro/hfp 125、lulc/clcd 1,170、lulc/hlu1km 18,440）
#     4) 合并写出
#   这样既保留已校对内容，又保证新数据集元数据完整。
#
#   ⚠ 本脚本产出的新行**不完整**：mk_row() 没有 source_file 与证据等级参数，
#     时间不变性注记也不在这里生成。**生成后必须紧接着运行**
#
#         E:\CHECO26\.venv\Scripts\python.exe scripts/enrich_provenance.py
#
#     该脚本补齐 source_file、variable_definition 的 [doc]/[std]/[name] 等级与类别的
#     源图例代码、hlu1km urban/water 的时间不变性注记，以及 19 个 _max/_min 层的重采样
#     声明。它是幂等的，可反复运行（--check 只报告不写盘）。两步都跑完，表才是
#     溯源和定义证据等级齐全。
#
#     验证：scripts/enrich_provenance.py --check 应输出四项改动数全为 0。
#
# 新数据集的源元数据（全部已核实）：
#   Mu HFP        CC BY 4.0  DOI 10.6084/m9.figshare.16571064.v8
#   CLCD          CC BY 4.0  DOI 10.5281/zenodo.18180184
#   Harmonised    CC BY 4.0  DOI 10.5281/zenodo.15017066
# =============================================================================

suppressPackageStartupMessages({ library(terra) })
source(file.path(Sys.getenv("CHECO_ROOT", "E:/CHECO26/N-SDM"), "R/_bootstrap.R"),
       encoding = "UTF-8")

PROV_PATH <- function() file.path(PATH_DOCS(), "provenance_table.csv")

# ---- 源元数据块（逐字段已核实）--------------------------------------------
META_HFP <- list(
  source_dataset = "Mu et al. annual Human Footprint (HFP) for China, 1 km (figshare 16571064 v8)",
  source_provider = "Mu Haowei, Li Xuecao - China Agricultural University; distributed via figshare",
  source_doi_url = "10.6084/m9.figshare.16571064.v8",
  source_citation = paste0("Mu, H., Li, X., Wen, Y., Huang, J., Du, P., Su, W., Miao, S., Geng, M. (2022). ",
                           "A global record of annual terrestrial Human Footprint dataset from 2000 to 2018. ",
                           "Scientific Data 9, 176. https://doi.org/10.1038/s41597-022-01284-8"),
  source_crs = "ESRI:54009 (World Mollweide)",
  source_resolution = "1000 m",
  source_extent = "global; Mollweide x[-18040095, 18040095] y[-9020047, 9020047]",
  source_nodata = "NaN (declared); ocean and uninhabited areas",
  source_scale_offset = "none (values are the HFP index directly, 0-50)",
  processing_steps = paste0(
    "1) read the per-year source raster hfp<YYYY>.tif. ",
    "2) reproject to the CHECO26 grid (China_Albers equal-area, WGS84 lon_0=105 lat_1=25 lat_2=47, 1 km) ",
    "with GDAL average resampling (area-weighted; verified against exactextractr to 6e-08). ",
    "3) apply the China boundary mask. 4) write float32, DEFLATE, nodata=-9999."),
  missing_boundary_rule = paste0(
    "Source NaN is excluded before averaging, so it never enters a window mean. ",
    "Cells outside the China mask are written as nodata."),
  script_function = "R/04_ingest_timeseries.R : hlu-style warp (warp_to_template) + focal_mean",
  license = "CC BY 4.0"
)

META_CLCD <- list(
  source_dataset = "CLCD v01 annual China Land Cover Dataset, 30 m (Zenodo 18180184)",
  source_provider = "Yang Jie, Huang Xin - Wuhan University; distributed via Zenodo",
  source_doi_url = "10.5281/zenodo.18180184",
  source_citation = paste0("Yang, J., Huang, X. (2021). The 30 m annual land cover dataset and its dynamics ",
                           "in China from 1990 to 2019. Earth System Science Data 13, 3907-3925. ",
                           "https://doi.org/10.5194/essd-13-3907-2021 (dataset v1.0.5)"),
  source_crs = "China_Albers (same parameters as the CHECO26 grid, but xmin differs by 18,375 m)",
  source_resolution = "30 m",
  source_extent = "China; 161,378 x 135,079 cells at 30 m",
  source_nodata = "0 (background / no data)",
  source_scale_offset = "none (integer class codes 1-9)",
  processing_steps = paste0(
    "1) process the source in 25-row output bands; for each band read the corresponding 30 m window ",
    "with a 2-cell margin. 2) set source class 0 to NA and build nine class indicators with ",
    "terra::segregate. 3) reproject the nine-band indicator to the CHECO26 1 km grid with GDAL ",
    "average resampling (area-weighted). 4) write nine areal-proportion layers per year, ",
    "then four focal-mean variants per class. 5) apply the China mask and write float32 nodata=-9999."),
  missing_boundary_rule = paste0(
    "Source class 0 is set to NA before aggregation, so the nine proportions sum to exactly 1 ",
    "within every valid cell. Verified on the complete 2000 reference year over all ",
    "9,471,991 valid cells: max|sum-1| = 5.08e-08 (independent recomputation with exactextractr ",
    "agrees to 5.0e-09). 18,319 cells of the national mask (0.19%) are nodata because the CLCD ",
    "raster does not reach the vector boundary; sampled cells there had zero valid 30 m source ",
    "pixels. Cells outside the China mask are nodata."),
  script_function = "R/06_derive_lulc_clcd.R : band_props + focal_mean",
  license = "CC BY 4.0"
)

META_HLU <- list(
  source_dataset = paste0("Harmonised global land use and land cover maps 1960-2100, 0.01 deg ",
                          "(Zenodo 15017066; HILDA+ v2b historic + LandSyMM/LandScaleR future)"),
  source_provider = paste0("Woodman T.L. (Univ. of Aberdeen), Arendarczyk B. (Univ. of Edinburgh), ",
                           "Winkler K. (KIT), Henry R.C., Eigenbrod F., Burslem D.F.R.P., ",
                           "Alexander P., Travis J.M.J.; distributed via Zenodo"),
  source_doi_url = "10.5281/zenodo.15017066",
  source_citation = paste0("Woodman, T.L., Arendarczyk, B., Winkler, K., Henry, R.C., Eigenbrod, F., ",
                           "Burslem, D.F.R.P., Alexander, P., Travis, J.M.J. (2025). ",
                           "Harmonised global land use and land cover maps between 1960 and 2100 ",
                           "[Data set]. Zenodo. https://doi.org/10.5281/zenodo.15017066"),
  source_crs = "EPSG:4326 (WGS84 geographic)",
  source_resolution = "0.01 degree (about 1 km at the equator)",
  source_extent = "global; 36,000 x 18,000 cells; 141 bands (1960-2100, band = year - 1959)",
  source_nodata = "NaN (declared); class 0 = ocean",
  source_scale_offset = "none (integer class codes 11/22/33/441/442/55/66/77)",
  processing_steps = paste0(
    "1) read band year-1959 from the country-f variant of the matching scenario file ",
    "(country-f chosen over global-f: each country downscaled with its own optimum parameters). ",
    "2) crop to the China window (70-140 E, 12-58 N). 3) set class 0 and out-of-legend values to NA, ",
    "build eight class indicators with terra::segregate. 4) reproject to the CHECO26 1 km grid with ",
    "GDAL average resampling. 5) write eight areal-proportion layers per year, then four focal-mean ",
    "variants per class. 6) apply the China mask and write float32 nodata=-9999."),
  missing_boundary_rule = paste0(
    "Class 0 (ocean) is set to NA before aggregation; the eight proportions sum to exactly 1 ",
    "within every valid cell (verified: max|sum-1| = 4.47e-08 over 9,485,144 cells). ",
    "Historic 1960-2020 is byte-identical across the five scenario files and is always read ",
    "from SSP1_RCP26_country-f.tif. Cells outside the China mask are nodata."),
  script_function = "R/07_derive_lulc_hlu1km.R : hlu_combo + focal_mean",
  license = "CC BY 4.0"
)

# ---- 类别名 --------------------------------------------------------------
HFP_CLS <- "hfp"
CLCD_LEGEND <- c("1" = "cropland", "2" = "forest", "3" = "shrub", "4" = "grassland",
                 "5" = "water", "6" = "snowice", "7" = "barren", "8" = "impervious",
                 "9" = "wetland")
HLU_LEGEND <- c("11" = "urban", "22" = "cropland", "33" = "pasture",
                "441" = "mngforest", "442" = "forest", "55" = "grassshrub",
                "66" = "sparse", "77" = "water")

# ---- 行生成 --------------------------------------------------------------
mk_row <- function(parts, suffix, meta, var_def, units, exp_range, formula, note = "") {
  path <- file.path(paste(parts, collapse = "/"),
                    paste0(paste(parts, collapse = "_"), suffix, ".tif"))
  data.frame(
    layer_path = path, status = "active",
    source_file = NA_character_, source_dataset = meta$source_dataset,
    source_provider = meta$source_provider, source_doi_url = meta$source_doi_url,
    source_citation = meta$source_citation, variable_definition = var_def,
    units = units, source_crs = meta$source_crs,
    source_resolution = meta$source_resolution, source_extent = meta$source_extent,
    source_nodata = meta$source_nodata, source_scale_offset = meta$source_scale_offset,
    processing_steps = meta$processing_steps, derivation_formula = formula,
    missing_boundary_rule = meta$missing_boundary_rule,
    script_function = meta$script_function, expected_range = exp_range,
    actual_range = "not yet computed", notes = note,
    stringsAsFactors = FALSE)
}

FS <- FOCAL_SPEC()

rows_hfp <- function() {
  out <- list()
  for (y in 2000:2024) {
    parts <- c("reg", "anthro", "hfp", as.character(y), "hfp")
    out[[length(out) + 1L]] <- mk_row(parts, "", META_HFP,
      "Annual Human Footprint index aggregated to 1 km [index 0-50]",
      "index (0-50)", "[0, 50]",
      "area-weighted 1 km mean of the 1 km Mollweide HFP source",
      "figshare record title says '2000 to 2018'; the distributed files cover 2000-2024")
    for (k in seq_len(nrow(FS)))
      out[[length(out) + 1L]] <- mk_row(parts, paste0("_f", FS$radius_km[k] * 1000L), META_HFP,
        sprintf("Focal mean of the Human Footprint index over a %d x %d cell square window (%d km radius)",
                FS$size[k], FS$size[k], FS$radius_km[k]),
        "index (0-50)", "[0, 50]",
        sprintf("square-window mean, %d x %d cells, denominator = valid cells in window", FS$size[k], FS$size[k]),
        "four focal radii: 1, 5, 10, 20 km")
  }
  do.call(rbind, out)
}

rows_clcd <- function() {
  out <- list()
  for (y in 2000:2025) for (cn in unname(CLCD_LEGEND)) {
    parts <- c("reg", "lulc", "clcd", as.character(y), cn)
    out[[length(out) + 1L]] <- mk_row(parts, "_prop", META_CLCD,
      sprintf("Areal proportion of CLCD land-cover class '%s' within the 1 km output cell [ratio 0-1]", cn),
      "ratio (0-1)", "[0, 1]",
      "one-hot areal proportion of the class within the output cell (30 m -> 1 km, area-weighted)")
    for (k in seq_len(nrow(FS)))
      out[[length(out) + 1L]] <- mk_row(parts,
        sprintf("_prop_f%d", FS$radius_km[k] * 1000L), META_CLCD,
        sprintf("Focal mean of the '%s' areal proportion over a %d x %d cell square window (%d km radius)",
                cn, FS$size[k], FS$size[k], FS$radius_km[k]),
        "ratio (0-1)", "[0, 1]",
        sprintf("square-window mean of the class proportion, %d x %d cells", FS$size[k], FS$size[k]),
        "four focal radii: 1, 5, 10, 20 km")
  }
  do.call(rbind, out)
}

rows_hlu <- function() {
  out <- list()
  add_combo <- function(year, ssp) {
    hits <- 0L
    for (cn in unname(HLU_LEGEND)) {
      parts <- if (is.na(ssp)) c("reg", "lulc", "hlu1km", as.character(year), cn)
               else c("reg", "lulc", "hlu1km", "scenario", as.character(year), ssp, cn)
      out[[length(out) + 1L]] <<- mk_row(parts, "_prop", META_HLU,
        sprintf("Areal proportion of harmonised land-use class '%s' in %d%s [ratio 0-1]",
                cn, year, if (is.na(ssp)) " (historic)" else paste0(" under ", ssp)),
        "ratio (0-1)", "[0, 1]",
        "one-hot areal proportion of the class within the output cell (0.01 deg -> 1 km, area-weighted)")
      for (k in seq_len(nrow(FS)))
        out[[length(out) + 1L]] <<- mk_row(parts,
          sprintf("_prop_f%d", FS$radius_km[k] * 1000L), META_HLU,
          sprintf("Focal mean of the '%s' proportion in %d%s over a %d x %d cell square window",
                  cn, year, if (is.na(ssp)) "" else paste0(" (", ssp, ")"), FS$size[k], FS$size[k]),
          "ratio (0-1)", "[0, 1]",
          sprintf("square-window mean of the class proportion, %d x %d cells", FS$size[k], FS$size[k]),
          "four focal radii: 1, 5, 10, 20 km")
    }
  }
  for (y in 1960:2020) add_combo(y, NA_character_)
  for (ssp in c("ssp126", "ssp245", "ssp370", "ssp460", "ssp585"))
    for (y in 2021:2100) add_combo(y, ssp)
  do.call(rbind, out)
}

# ---- CHELSA v2.1 bioclim（2026-11-12 替换 cnclim1km）----------------------
META_CHELSA <- list(
  source_dataset = "CHELSA v2.1 bioclimatic variables (global, 30 arc-sec; WSL/EnviDat)",
  source_provider = "Karger D.N. et al., Swiss Federal Institute for Forest, Snow and Landscape Research (WSL)",
  source_doi_url = "10.16904/envidat.228.v2.1",
  source_citation = paste0("Karger, D.N., Conrad, O., Bohner, J., Kawohl, T., Kreft, H., Soria-Auza, R.W., ",
                           "Zimmermann, N.E., Linder, H.P., Kessler, M. (2021). Climatologies at high resolution ",
                           "for the earth's land surface areas. EnviDat. https://doi.org/10.16904/envidat.228 ",
                           "(v2.1: https://doi.org/10.16904/envidat.228.v2.1, CC0-1.0)"),
  source_crs = "EPSG:4326",
  source_resolution = "0.00833333 degree (30 arc-seconds, ~1 km)",
  source_extent = "global; 43200 x 20880 cells (84N to 90S)",
  source_nodata = "65535 (UInt16)",
  source_scale_offset = paste0("per-variable GDAL scale/offset applied by terra to physical units ",
                               "(temperature scale 0.1 offset -273.15 -> degC; bio03 scale 0.001 -> fraction, ",
                               "then x100 -> percent; precipitation mm; gdd degree-days)"),
  processing_steps = paste0("1) read CHELSA v2.1 source raster. 2) crop to China window (70-138E, 15-56N). ",
                            "3) reproject to the CHECO26 grid (China_Albers equal-area, WGS84 lon_0=105 lat_1=25 lat_2=47, 1 km) ",
                            "with terra::project bilinear; terra applies the source scale/offset to physical units. ",
                            "4) bio03 multiplied by 100 to percent (WorldClim convention). 5) mask to the national boundary ",
                            "(mask_china.tif). 6) write float32, nodata -9999, DEFLATE, 256x256 tiles. ",
                            "Future ensmean = pixel-wise equal-weight arithmetic mean of the 5 GCM layers."),
  missing_boundary_rule = paste0("Source nodata 65535 is excluded before reprojection; cells outside the China mask ",
                                 "are nodata in every delivered layer."),
  script_function = "R/03_ingest_static.R : warp_to_template",
  license = "CC0-1.0"
)

# 22 个变量的标准定义 / 单位 / 物理值域（CHELSA 与 WorldClim 标准 BioClim 口径一致）
CHELSA_VARS <- list(
  bio01 = list(def="Annual mean temperature", unit="degC", rng="[-90, 60]"),
  bio02 = list(def="Mean diurnal range (mean of monthly max temp - min temp)", unit="degC", rng="[0, 50]"),
  bio03 = list(def="Isothermality (bio02/bio07 x 100)", unit="percent", rng="[0, 100]"),
  bio04 = list(def="Temperature seasonality (standard deviation x 100)", unit="degC x100", rng="[0, 20000]"),
  bio05 = list(def="Max temperature of warmest month", unit="degC", rng="[-90, 60]"),
  bio06 = list(def="Min temperature of coldest month", unit="degC", rng="[-90, 60]"),
  bio07 = list(def="Temperature annual range (bio05 - bio06)", unit="degC", rng="[0, 100]"),
  bio08 = list(def="Mean temperature of wettest quarter", unit="degC", rng="[-90, 60]"),
  bio09 = list(def="Mean temperature of driest quarter", unit="degC", rng="[-90, 60]"),
  bio10 = list(def="Mean temperature of warmest quarter", unit="degC", rng="[-90, 60]"),
  bio11 = list(def="Mean temperature of coldest quarter", unit="degC", rng="[-90, 60]"),
  bio12 = list(def="Annual precipitation", unit="mm", rng="[0, 20000]"),
  bio13 = list(def="Precipitation of wettest month", unit="mm", rng="[0, 20000]"),
  bio14 = list(def="Precipitation of driest month", unit="mm", rng="[0, 20000]"),
  bio15 = list(def="Precipitation seasonality (coefficient of variation)", unit="percent", rng="[0, 300]"),
  bio16 = list(def="Precipitation of wettest quarter", unit="mm", rng="[0, 20000]"),
  bio17 = list(def="Precipitation of driest quarter", unit="mm", rng="[0, 20000]"),
  bio18 = list(def="Precipitation of warmest quarter", unit="mm", rng="[0, 20000]"),
  bio19 = list(def="Precipitation of coldest quarter", unit="mm", rng="[0, 20000]"),
  gdd0  = list(def="Growing degree days above 0 degC", unit="degC day", rng="[0, 20000]"),
  gdd5  = list(def="Growing degree days above 5 degC", unit="degC day", rng="[0, 20000]"),
  gdd10 = list(def="Growing degree days above 10 degC", unit="degC day", rng="[0, 20000]")
)

rows_chelsa <- function() {
  clim <- CFG()$climate
  vars <- c(sprintf("bio%02d", 1:as.integer(clim$n_bio)), as.character(unlist(clim$extra_vars)))
  chains <- as.character(unlist(clim$chains))
  ssps <- as.character(unlist(clim$ssps))
  cyears <- names(clim$periods)
  src <- as.character(clim$source)
  pp <- as.character(clim$present_period)
  out <- list()
  add <- function(parts, v, script_fn, src_file, note = "") {
    cv <- CHELSA_VARS[[v]]
    r <- mk_row(parts, "", META_CHELSA,
                sprintf("%s [CHELSA v2.1 standard definition]", cv$def),
                cv$unit, cv$rng,
                "reprojected to 1 km China_Albers (bilinear); standard CHELSA bioclimatic definition",
                note)
    r$script_function <- script_fn
    r$source_file <- src_file
    if (startsWith(v, "gdd")) {
      if (parts[3] == "chelsa21-ensmean") {
        r$source_file <- sprintf("[selector] Five CHECO26 GCM chains, all gdd0/gdd5/gdd10 at %s/%s",
                                 parts[5], parts[6])
        r$source_crs <- "CHECO26 China Albers"
        r$source_resolution <- "1000 metres"
        r$source_extent <- "CHECO26 1 km China delivery grid"
        r$source_nodata <- "-9999 (CHECO26 member layers)"
        r$source_scale_offset <- "None (CHECO26 members in degree-days)"
        r$processing_steps <- "For each target cell, retain only models with values at all three thresholds and average selected members."
        r$derivation_formula <- "Equal-weight mean using the same per-cell subset of models for all three GDD thresholds."
        r$missing_boundary_rule <- "NoData outside mask or when no member supplies all three thresholds."
      } else {
        r$source_nodata <- "2147483647 (Int32)"
        r$source_scale_offset <- "Scale 0.1, offset 0"
        r$processing_steps <- paste("Decode the GDD source to degree-days, crop and project bilinearly",
                                    "to China Albers, apply the national mask and write float32.")
        r$missing_boundary_rule <- "Exclude source Int32 NoData 2147483647 before resampling."
      }
    }
    out[[length(out) + 1L]] <<- r
  }
  for (v in vars) {
    parts <- c("reg", "bioclim", src, "present", v)
    sf <- sprintf("[path] %s/bioclim/%s/%s/CHELSA_%s_%s_V.2.1.tif", P("chelsa"), v, pp, v, pp)
    add(parts, v, "R/03_ingest_static.R : warp_to_template", sf, "present climatology 1981-2010")
  }
  for (chain in chains) {
    is_ens <- chain == "ensmean"
    dsname <- paste0(src, "-", chain)
    for (cy in cyears) {
      sp <- as.character(clim$periods[[cy]])
      for (ssp in ssps) for (v in vars) {
        parts <- c("reg", "bioclim", dsname, "scenario", cy, ssp, v)
        if (is_ens) {
          sf <- paste0("[selector] equal-weight mean of 5 GCM layers ",
                       "(GFDL-ESM4, IPSL-CM6A-LR, MPI-ESM1-2-HR, MRI-ESM2-0, UKESM1-0-LL)")
          add(parts, v, "R/10_future_chains.R : run_ensmean", sf,
              sprintf("ensemble mean of 5 CMIP6 GCMs; %s %s", ssp, sp))
        } else {
          sf <- sprintf("[path] %s/bioclim/%s/%s/%s/%s/CHELSA_%s_%s_%s_%s_V.2.1.tif",
                        P("chelsa"), v, sp, toupper(chain), ssp, chain, ssp, v, sp)
          add(parts, v, "R/10_future_chains.R : run_gcm", sf,
              sprintf("CMIP6 %s; %s %s", chain, ssp, sp))
        }
      }
    }
  }
  do.call(rbind, out)
}

reconcile_source_lineage <- function(d) {
  paths <- d$layer_path
  focal <- FOCAL_SPEC()
  for (snap in glu_snapshots()) {
    stem <- if (is.na(snap$ssp)) paste0("reg/lulc/glu1km/", snap$y, "/")
            else paste0("reg/lulc/glu1km/scenario/", snap$y, "/", snap$ssp, "/")
    i <- which(d$status == "active" & startsWith(paths, stem))
    if (!length(i)) next
    d$source_file[i] <- paste("[path]", file.path(P("lulc_raw"), snap$f))
    d$script_function[i] <- "R/05_derive_lulc.R : derive_snapshot"
    d$processing_steps[i] <- paste("Exclude source class 0. Reproject classes by nearest neighbour",
      "to the CHECO26 grid, keep the six valid land-cover classes inside the national mask,",
      "and compute the named indicator or landscape metric. Focal proportions use",
      "square-window averages of one-hot indicators. Shannon uses those proportions.",
      "Edge layers use four-neighbour class differences; patch layers use disk windows and anchors.")
    for (j in i) {
      name <- basename(paths[j])
      part <- basename(dirname(paths[j]))
      f <- which(endsWith(name, paste0(focal$suffix, ".tif")))
      if (length(f)) {
        radius <- focal$radius_cells[f]
        window <- sprintf("%d x %d cells, %d km radius along each axis", 2L * radius + 1L,
                          2L * radius + 1L, radius)
      }
      d$derivation_formula[j] <- if (startsWith(part, "patch")) {
        statistic <- if (startsWith(part, "patchdensity")) "100 * patch count / (pi * radius^2)"
                     else "sum of full included patch areas / patch count"
        sprintf("%s. Use a disk of radius %d km, four-neighbour patches, and an anchor with an own-patch correction.",
                statistic, radius)
      } else if (part == "shannon") {
        sprintf("-sum(p * ln(p)) over nonzero class proportions from the square window (%s).", window)
      } else if (part == "edge") {
        edge <- "Flag a valid cell if at least one valid four-neighbour has a different class."
        if (length(f)) paste(edge, sprintf("Average flags over valid cells in the square window (%s).", window))
        else edge
      } else if (length(f)) {
        sprintf("Average the class indicator over valid cells in the square window (%s).", window)
      } else "Class indicator on the 1 km nearest-neighbour class grid (0 or 1)."
      if (startsWith(part, "patch")) {
        d$missing_boundary_rule[j] <- paste("Only valid class cells may belong to a patch.",
          "NoData where no patch is counted or outside the national mask. A forest window may contain",
          "forest cells and still have no counted patch under the anchor rule.")
      } else {
        d$missing_boundary_rule[j] <- paste("Class 0 and classes outside the legend are excluded.",
          "A focal denominator counts valid cells only. Apply the national mask.")
      }
    }
  }

  i <- which(d$status == "active" & startsWith(paths, "reg/bioclim/chelsa21-ensmean/"))
  if (length(i)) {
    d$source_crs[i] <- "CHECO26 China Albers"
    d$source_resolution[i] <- "1000 metres"
    d$source_extent[i] <- "CHECO26 1 km China delivery grid"
    d$source_nodata[i] <- "-9999 (CHECO26 member layers)"
    d$source_scale_offset[i] <- "None (CHECO26 members already in physical units)"
    nongdd <- i[!grepl("/gdd(0|5|10)/", paths[i])]
    d$source_file[nongdd] <- vapply(strsplit(paths[nongdd], "/", fixed = TRUE), function(parts)
      sprintf("[selector] Five CHECO26 GCM chains at scenario/%s/%s/%s, see R/10_future_chains.R",
              parts[5], parts[6], parts[7]), "")
    d$processing_steps[nongdd] <- "Average matching standardized GCM layers and apply the national mask."
    d$derivation_formula[nongdd] <- "Equal-weight mean of available standardized GCM members."
    d$missing_boundary_rule[nongdd] <- "Ignore missing members. NoData when no member is available or outside the national mask."
  }
  joint_keys <- as.character(unlist(CFG()$climate$joint_temperature_groups))
  joint <- which(d$status == "active" & grepl(
    "^reg/bioclim/chelsa21-[^/]+/scenario/[0-9]{4}/[^/]+/bio0[567]/", paths))
  joint <- joint[sub("^reg/bioclim/chelsa21-([^/]+)/scenario/([^/]+/[^/]+)/.*$", "\\1/\\2",
                     paths[joint]) %in% joint_keys]
  d$script_function[joint] <- "R/10_future_chains.R : warp_joint_temperature"
  d$processing_steps[joint] <- paste("Decode aligned native BIO05, BIO06 and BIO07 into a float32",
    "stack, jointly project with bilinear resampling, and apply the national mask.")
  d$derivation_formula[joint] <- "BIO05, BIO06 and BIO07 share bilinear interpolation support."
  d$source_scale_offset[joint] <- ifelse(grepl("/bio07/", paths[joint]),
    "Scale 0.1, offset 0 (annual temperature difference)",
    "Scale 0.1, offset -273.15 (degrees Celsius)")
  d$source_nodata[joint] <- "65535 (native packed inputs)"
  d$notes[joint] <- "The three native inputs use the same grid and are projected as one decoded stack."

  smod <- which(d$status == "active" & startsWith(paths, "reg/dist/smod/"))
  d$source_dataset[smod] <- "GHS-SMOD R2023A, 2020 epoch; settlement classes 21, 22, 23 and 30"
  d$source_scale_offset[smod] <- "None (categorical class codes)"
  projected_smod <- which(d$status == "active" & grepl("^reg/anthro/smod/(2025|2030)/", paths))
  d$notes[projected_smod] <- "Future projection in the JRC GHSL 2023 Data Package."

  catcd <- which(d$status == "active" & startsWith(paths, "reg/vege/catcd/"))
  d$source_doi_url[catcd] <- "10.5281/zenodo.19160322"
  d$source_citation[catcd] <- paste(
    "Cai et al., China Annual Tree Cover Dataset, Part VI, version 3 (2026),",
    "CATCD_2025.tif, https://doi.org/10.5281/zenodo.19160322.",
    "Methods: https://doi.org/10.1016/j.isprsjprs.2024.08.001.")
  d$script_function[catcd] <- "R/03_ingest_static.R : warp_to_template"
  focal_catcd <- catcd[grepl("_f[0-9]+[.]tif$", paths[catcd])]
  d$script_function[focal_catcd] <- "R/04_ingest_timeseries.R : focal_mean (standardized 2025 layer)"
  d$notes[catcd] <- "Delivered coverage is the 2025 TreeCover band and its focal means."
  d
}


h90m_provenance <- function(d) {
  path <- file.path(PATH_DOCS(), "H90M_SOURCE_MANIFEST.csv")
  if (!file.exists(path)) stop("Missing pinned h90m source inventory: ", path)
  catalog <- read.csv(path, stringsAsFactors = FALSE)
  registry <- catalog[catalog$kind == "native", ]
  layer <- d$layer_path
  internal <- grepl("^reg/hydro/h90m/(direction|segment|sub-catchment)/", layer)
  i <- which(d$status == "active" & grepl("^reg/(dist|hydro)/h90m/", layer) &
             !grepl("/channel-elv-up-cel/", layer) & !internal)
  for (j in i) {
    var <- gsub("-", "_", strsplit(layer[j], "/", fixed = TRUE)[[1]][4])
    ref <- registry[registry$variable == var, ]
    expected <- as.character(unlist(CFG()$hydro90m_vars$tile_ids))
    stopifnot(nrow(ref) == length(expected), setequal(ref$tile, expected),
              length(unique(ref$nodata)) == 1L, length(unique(ref$data_type)) == 1L)
    method <- if (endsWith(layer[j], "_min.tif")) "min"
      else if (endsWith(layer[j], "_max.tif")) "max"
      else if (var %in% unlist(CFG()$hydro90m_vars$categorical)) "mode" else "average"
    scale <- CFG()$hydro90m_vars$scale_by_var[[var]]
    if (is.null(scale)) scale <- 1
    d$source_file[j] <- sprintf("[selector] H90M_SOURCE_MANIFEST.csv, kind=native, variable=%s (20 files), and kind=boundary", var)
    d$source_crs[j] <- "EPSG:4326 (native Hydrography90m grid)"
    d$source_resolution[j] <- "3 arc-seconds (approximately 90 m)"
    d$source_extent[j] <- "Twenty source tiles listed in H90M_SOURCE_MANIFEST.csv; then clipped to China"
    d$source_nodata[j] <- sprintf("%s (%s native source)", ref$nodata[1], ref$data_type[1])
    d$source_scale_offset[j] <- sprintf("Multiply the aggregated value by %.9g; offset 0", scale)
    d$processing_steps[j] <- paste("Mosaic the pinned native rasters. Clip on the 90 m grid, including",
      "cells whose centres intersect the historical China boundary. Apply the",
      method, "resampling statistic on the 1 km CHECO26 grid, then the configured",
      "scale and national mask. Store float32 with NoData -9999.")
    d$derivation_formula[j] <- sprintf("1 km %s of eligible native cells, multiplied by %.9g.", method, scale)
    d$missing_boundary_rule[j] <- paste("Exclude source NoData and native cells outside the",
      "historical boundary before aggregation. Apply the CHECO26 national mask after reprojection.")
    d$script_function[j] <- "R/19_rebuild_h90m_legacy.R : rebuild_h90m_legacy"
    if (method == "average") {
      d$source_file[j] <- paste0("[historical] Deleted E:/h90m/Final/", var, "/", var,
        "_china.tif; native tile and boundary lineage in H90M_SOURCE_MANIFEST.csv (variable=", var, ").")
      d$source_extent[j] <- "Published legacy China intermediate; the native lineage spans twenty pinned tiles"
      d$processing_steps[j] <- paste("The historical China mosaic was averaged to the 1 km CHECO26 grid,",
        "then scaled and masked. Stage 19 reproduces the method from pinned raw inputs, with small",
        "localized differences from this version of the historical delivery.")
      d$missing_boundary_rule[j] <- paste("Exclude source NoData. The historical native China clip",
        "precedes aggregation. Apply the CHECO26 national mask after reprojection.")
      d$script_function[j] <- paste("Historical R/03_ingest_static.R : warp_to_template;",
        "R/19_rebuild_h90m_legacy.R : replay from pinned native inputs")
    }
  }
  modern <- which(d$status == "active" & grepl("^reg/hydro/h90m/channel-elv-up-cel/", layer))
  d$source_file[modern] <-
    "[selector] H90M_SOURCE_MANIFEST.csv, variable=channel_elv_up_cel (20 tiles), and kind=boundary"
  h90_active <- c(i, modern, which(d$status == "active" & internal))
  d$source_dataset[h90_active] <- "Hydrography90m, global 3-arc-second rasters, China subset"
  d$source_provider[h90_active] <- "Giuseppe Amatulli et al. (Hydrography90m)"
  d$notes[h90_active] <- "Raw raster lineage and historical China boundary are versioned in H90M_SOURCE_MANIFEST.csv."
  average <- i[grepl("^\\[historical\\]", d$source_file[i])]
  d$notes[average] <- paste("The historical 1 km mean is retained. The native-tile reconstruction",
    "preserves the valid mask; localized boundary differences remain. See CODE_REVIEW_NOTES.md.")
  d$notes[modern] <- "Stage 17 uses one cleaned 20-tile mosaic for the mean, minimum and maximum."
  d$source_nodata[modern] <- "-9999999 (native Int32) and values >= 50000"
  d$source_scale_offset[modern] <- "None (metres already)"
  legacy_only <- which(d$status == "active" & internal)
  d$source_file[legacy_only] <- paste0("[selector] Native tile lineage in H90M_SOURCE_MANIFEST.csv ",
    "(variable=", gsub("-", "_", vapply(strsplit(layer[legacy_only], "/", fixed = TRUE), function(p) p[4], "")),
    "). Historical export used the deleted E:/h90m/Final intermediates.")
  d$processing_steps[legacy_only] <- paste("Historical 1 km categorical exports preserved internally.",
    "The native tiles can be located from the inventory. Integer identities, flow direction and",
    "connectivity on the resampled grid require separate validation.")
  for (j in legacy_only) {
    var <- gsub("-", "_", basename(dirname(layer[j])))
    ref <- registry[registry$variable == var, ]
    stopifnot(nrow(ref) == 20L, length(unique(ref$nodata)) == 1L, length(unique(ref$data_type)) == 1L)
    d$source_extent[j] <- "Twenty pinned native tiles; historical intermediate clipped to China"
    d$source_nodata[j] <- sprintf("%s (%s native source)", ref$nodata[1], ref$data_type[1])
    d$source_scale_offset[j] <- "None (categorical code)"
    d$derivation_formula[j] <- "1 km mode of eligible native cells."
    d$missing_boundary_rule[j] <- "Exclude source NoData and apply the national mask."
    d$notes[j] <- "Internal only. The historical output and native-tile replay have identical value and NoData arrays."
  }
  d$script_function[legacy_only] <- "R/19_rebuild_h90m_legacy.R : native-tile reconstruction (historical delivery retained)"
  outlet <- i[basename(dirname(layer[i])) == "outlet"]
  d$variable_definition[outlet] <- "Sparse raster flag for Hydrography90m outlet cells aggregated to 1 km. [proc]"
  d$missing_boundary_rule[outlet] <- paste("Exclude native NoData and cells outside the historical boundary.",
    "A 1 km cell with no eligible outlet flag is NoData. Apply the national mask.")
  d$notes[outlet] <- paste("Valid cells have value 1. Use as a reference flag;",
    "the layer does not define a continuous covariate or outlet network topology.")
  d
}

# ---- 主流程 --------------------------------------------------------------
main <- function(fill_actual = FALSE, refresh_paths = character()) {
  base <- read.csv(PROV_PATH(), fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE,
                   check.names = FALSE)
  cat(sprintf("现有溯源表: %d 行 x %d 列\n", nrow(base), ncol(base)))

  drop <- grepl("^reg/anthro/(landscan|foothii)/", base$layer_path)
  drop_bio <- grepl("^reg/bioclim/cnclim1km", base$layer_path)
  cat(sprintf("  剔除 LandScan/footHII: %d 行；旧 cnclim1km bioclim: %d 行\n", sum(drop), sum(drop_bio)))
  base <- base[!drop & !drop_bio, ]

  cat("生成新数据集行...\n")
  t0 <- Sys.time()
  hfp  <- rows_hfp();  cat(sprintf("  anthro/hfp      %5d 行\n", nrow(hfp)))
  clcd <- rows_clcd(); cat(sprintf("  lulc/clcd       %5d 行\n", nrow(clcd)))
  hlu  <- rows_hlu();  cat(sprintf("  lulc/hlu1km     %5d 行\n", nrow(hlu)))
  chelsa <- rows_chelsa(); cat(sprintf("  bioclim/chelsa21 %5d 行\n", nrow(chelsa)))

  # 幂等：若基准表已含某层（重复运行时），跳过该层
  new <- do.call(rbind, list(hfp, clcd, hlu, chelsa))
  dup <- new$layer_path %in% base$layer_path
  if (any(dup)) cat(sprintf("  基准表已含，跳过 %d 行（幂等）\n", sum(dup)))
  new <- new[!dup, , drop = FALSE]

  # 列对齐（按 base 的列顺序）
  align <- function(d) { for (nm in names(base)) if (!nm %in% names(d)) d[[nm]] <- rep(NA_character_, nrow(d))
                         d[, names(base), drop = FALSE] }
  out <- h90m_provenance(reconcile_source_lineage(rbind(align(base), align(new))))
  cat(sprintf("\n合并后: %d 行（期望 21,796 = 21,788 active + 8 withdrawn）\n", nrow(out)))
  stopifnot(!anyDuplicated(out$layer_path))

  # 可选：读取已存在层填 actual_range
  if (fill_actual || length(refresh_paths)) {
    stopifnot(all(refresh_paths %in% out$layer_path[out$status == "active"]))
    cat("填充 actual_range（读取已存在层）...\n")
    root <- PATH_COV()
    n <- 0L
    for (i in seq_len(nrow(out))) {
      refresh <- out$layer_path[i] %in% refresh_paths
      if (!refresh && !is.na(out$actual_range[i]) && out$actual_range[i] != "not yet computed") next
      p <- file.path(root, out$layer_path[i])
      if (refresh && !file.exists(p)) stop("Missing raster to refresh: ", p)
      if (!file.exists(p)) next
      st <- tryCatch(raster_stats(p), error = function(e) NULL)
      if (refresh && (is.null(st) || st$n == 0)) stop("Cannot refresh raster statistics: ", p)
      if (is.null(st) || st$n == 0) next
      out$actual_range[i] <- sprintf("[%.16g, %.16g] over %d valid cells", st$min, st$max, st$n)
      n <- n + 1L
    }
    cat(sprintf("  已填 %d / %d 行\n", n, nrow(out)))
  }

  write.csv(out, PROV_PATH(), row.names = FALSE, fileEncoding = "UTF-8")
  cat(sprintf("已写出: %s  (%.0f 秒)\n", PROV_PATH(),
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  invisible(out)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  main(identical(a[1], "fill"), a[-1])
}
