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
#     21,118 行 × 25 列全部填充的状态。
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

# ---- 主流程 --------------------------------------------------------------
main <- function(fill_actual = FALSE) {
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
  align <- function(d) { for (nm in names(base)) if (!nm %in% names(d)) d[[nm]] <- NA
                         d[, names(base), drop = FALSE] }
  out <- rbind(align(base), align(new))
  cat(sprintf("\n合并后: %d 行（期望 21,796 = 21,788 active + 8 withdrawn）\n", nrow(out)))
  stopifnot(!anyDuplicated(out$layer_path))

  # 可选：读取已存在层填 actual_range
  if (fill_actual) {
    cat("填充 actual_range（读取已存在层）...\n")
    root <- PATH_COV()
    n <- 0L
    for (i in seq_len(nrow(out))) {
      if (!is.na(out$actual_range[i]) && out$actual_range[i] != "not yet computed") next
      p <- file.path(root, out$layer_path[i])
      if (!file.exists(p)) next
      st <- tryCatch(raster_stats(p), error = function(e) NULL)
      if (is.null(st) || st$n == 0) next
      out$actual_range[i] <- sprintf("[%.6g, %.6g] over %d valid cells", st$min, st$max, st$n)
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
  main(identical(a[1], "fill"))
}
