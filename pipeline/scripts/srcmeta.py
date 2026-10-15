# -*- coding: utf-8 -*-
"""srcmeta.py -- source-dataset provenance for the CHECO26 provenance table.

Every field below was established either by reading the source files themselves
(embedded GDAL tags, sidecar readmes, accompanying papers shipped with the data)
or from the DOI landing page / publisher API. Nothing here is inferred from the
dataset name alone. Fields still unverified are marked "TODO: ..." so they can be
found with a single grep.

Keys are (theme, dataset) as they appear in the delivered covariates paths.
"""

# ---------------------------------------------------------------------------
# Per-source metadata.
#   name       : dataset name + version, as stated by the provider
#   provider   : institution(s) holding/producing the data
#   id         : persistent identifier (DOI preferred) or landing-page URL
#   citation   : citable reference
#   crs / res / extent / nodata / scale : measured from the source rasters
#   note       : anything a reader must know
# ---------------------------------------------------------------------------
SRC = {}

SRC[("bioclim", "cnclim1km")] = dict(
    name="A 1 km monthly dataset of historical and future climate changes over China, "
         "version V8 (8.0.0), historical period 1991-2020",
    provider="Zhejiang Normal University (Xiaofei Hu, Shaolin Shi, Borui Zhou, Jian Ni); "
             "published on Science Data Bank",
    id="10.57760/sciencedb.13546",
    citation="Hu X., Shi S., Zhou B., Ni J. (2025). A 1 km monthly dataset of historical and "
             "future climate changes over China. Science Data Bank. V8. "
             "https://doi.org/10.57760/sciencedb.13546",
    crs="EPSG:4326",
    res="0.01 degree (~1 km)",
    extent="x[73.433, 135.083] y[18.168, 53.548]; China bounding box",
    nodata="-3.4028234663852886e+38",
    scale="none (values already in physical units)",
    note="Historical climatology from the China Surface Climate Standard Dataset, "
         "interpolated with ANUSPLIN. Licence CC BY 4.0. Source layout: "
         "<dataset>/present/1991_2020/<variable>/.",
)

SRC[("bioclim", "cnclim1km-bcc-csm2-mr")] = dict(
    name="A 1 km monthly dataset of historical and future climate changes over China, "
         "version V8 (8.0.0), future CMIP6 chain BCC-CSM2-MR "
         "(one of 10 model datasets published by the source)",
    provider="Zhejiang Normal University; published on Science Data Bank",
    id="10.57760/sciencedb.13546",
    citation="Hu X., Shi S., Zhou B., Ni J. (2025). A 1 km monthly dataset of historical and "
             "future climate changes over China. Science Data Bank. V8. "
             "https://doi.org/10.57760/sciencedb.13546",
    crs="EPSG:4326",
    res="0.01 degree (~1 km)",
    extent="x[73.433, 135.083] y[18.168, 53.548]; China bounding box",
    nodata="-3.4028234663852886e+38",
    scale="none (values already in physical units)",
    note="Future climatology derived from CMIP6 simulations, bias-corrected with the Delta "
         "downscaling method. Ensemble member r1i1p1f1. The source publishes 10 model "
         "datasets (9 GCMs + 1 ensemble mean) x 3 scenarios x 3 periods; THIS DELIVERY USES "
         "2 CHAINS ONLY (cnclim1km-ensmean and cnclim1km-bcc-csm2-mr). The other 9 model "
         "datasets are retained outside the delivery tree in archive/gcm/ "
         "(2268 files, 78.3 GB).",
)

SRC[("bioclim", "cnclim1km-ensmean")] = dict(
    name="A 1 km monthly dataset of historical and future climate changes over China, "
         "version V8 (8.0.0), future multi-model ensemble mean "
         "(mean of the 10 published CMIP6 chains)",
    provider="Zhejiang Normal University; published on Science Data Bank",
    id="10.57760/sciencedb.13546",
    citation="Hu X., Shi S., Zhou B., Ni J. (2025). A 1 km monthly dataset of historical and "
             "future climate changes over China. Science Data Bank. V8. "
             "https://doi.org/10.57760/sciencedb.13546",
    crs="EPSG:4326",
    res="0.01 degree (~1 km)",
    extent="x[73.433, 135.083] y[18.168, 53.548]; China bounding box",
    nodata="-3.4028234663852886e+38",
    scale="none (values already in physical units)",
    note="Arithmetic mean of the 10 published model datasets (build_chneco26_bioclim.py "
         "asserts len(sources) == 10). The 10 members are ACCESS-CM2, BCC-CSM2-MR, "
         "CMCC-ESM2, ESM, GFDL-ESM4, INM-CM5-0, IPSL-CM6A-LR, MIROC6, MPI-ESM1-2-HR, "
         "MRI-ESM2-0 (r1i1p1f1).",
)

SRC[("soil", "csdlv2")] = dict(
    name="A China dataset of soil properties for land surface modelling, version 2 (CSDLv2), "
         "1 km version",
    provider="School of Atmospheric Sciences, Sun Yat-sen University "
             "(Gaosong Shi, Wei Shangguan); distributed by the National Tibetan Plateau / "
             "Third Pole Environment Data Center",
    id="10.11888/Terre.tpdc.301235",
    citation="Shi, G., Shangguan, W. (2024). A China dataset of soil properties for land "
             "surface modeling (version 2, CSDLv2). National Tibetan Plateau / Third Pole "
             "Environment Data Center. https://doi.org/10.11888/Terre.tpdc.301235 "
             "(article: Earth Syst. Sci. Data 17, 517-543, "
             "https://doi.org/10.5194/essd-17-517-2025)",
    crs="EPSG:4326",
    res="1 km (source series also published at 90 m and 10 km)",
    extent="x[73.420, 135.104] y[17.746, 53.580]; China",
    nodata="-32768",
    scale="divide by 10 for AN and AK; divide by 100 for every other property",
    note="The dataset README states 23 physical/chemical properties; supplement sections "
         "S2-S24 reproduce exactly 23 property sections. 28 raster directories are delivered "
         "here because wet and dry soil colour are each encoded twice (RGB and Munsell "
         "hue/value/chroma), and because SOCD is present in the README table and on disk but "
         "is NOT mentioned in the ESSD article or its supplement (verified by full-text "
         "search of the article and the 100-page supplement) - i.e. a repository-only "
         "addition. Each property is delivered at 6 depth intervals plus one "
         "depth-integrated 'profile' layer (28 x 7 = 196).",
)

SRC[("topo", "chinadem")] = dict(
    name="China digital elevation model (1KM) - 中国数字高程图（1KM）; delivered files "
         "chdem_105.tif (elevation) and chdem_Slope.tif (slope)",
    provider="TANG Guoan (汤国安), Nanjing Normal University (南京师范大学); distributed by "
             "the National Tibetan Plateau / Third Pole Environment Data Center "
             "(时空三极环境大数据平台). Contact: tangguoan@njnu.edu.cn",
    id="https://data.tpdc.ac.cn/zh-hans/data/12e91073-0181-44bf-8308-c50e5bd9a734 "
       "(no DOI assigned; TPDC metadata record)",
    citation="汤国安. 中国数字高程图（1KM）. 时空三极环境大数据平台. "
             "https://data.tpdc.ac.cn/zh-hans/data/12e91073-0181-44bf-8308-c50e5bd9a734 "
             "[TANG Guoan. Digital elevation model of China (1KM). A Big Earth Data Platform "
             "for Three Poles.]",
    crs="Albers Conical Equal Area with central meridian 105 and standard parallels 25/47 "
        "(the file declares Krasovsky_1940_Albers, without an EPSG code); the source also "
        "publishes a geographic WGS84 variant",
    res="1000 m",
    extent="x[-3656885.10, 3405114.90] y[1560746.94, 6579746.94]; China (source coverage "
           "73.2-135.5 E, 17.8-53.9 N)",
    nodata="-32768 (elevation, int16) / -3.4028234663852886e+38 (slope, float32)",
    scale="none (elevation in m, slope in degrees)",
    note="Derived from 1:250000 contour lines and elevation points of China; the published "
         "dataset contains DEM, hillshade, slope and aspect. Temporal coverage is stated as "
         "2000 and the record was released 2021-12-16. Funding: Pan-Third Pole Environment "
         "Study for a Green Silk Road (XDA20000000). Two Albers variants (central meridian "
         "105 and 110) plus a geographic variant are published; the 105 variant was used "
         "here. The Shuttle Radar / no-DOI status was verified against DataCite and the "
         "TPDC metadata export. tri and aspect were derived in this project from the same "
         "DEM (see derivation_formula).",
)

SRC[("hydro", "h90m")] = dict(
    name="Hydrography90m, China merge (40 variables); source tiles from the global "
         "Hydrography90m release",
    provider="Hydrography90m (Giuseppe Amatulli et al.); China tiles merged and clipped to "
             "china.shp in this project",
    id="10.18728/igb-fred-762.1",
    citation="Amatulli, G., et al. (2022). Hydrography90m: a new high-resolution global "
             "hydrographic dataset. Earth Syst. Sci. Data 14, 4525-4550. "
             "https://doi.org/10.5194/essd-14-4525-2022 (data: "
             "https://doi.org/10.18728/igb-fred-762.1)",
    crs="EPSG:4326",
    res="0.00083333 degree (3 arc-seconds, ~90 m)",
    extent="x[73.4525, 134.975] y[18.1642, 53.5308]; China",
    nodata="-9999 (continuous layers) / 0 (categorical layers; varies by dtype)",
    scale="x0.01 cm->m for the 18 distance and elevation-difference variables; "
          "categorical layers unscaled",
    note="Derived from the MERIT Hydro DEM with the GRASS GIS r.stream.* modules; channel "
         "initiation threshold 0.05 km2. Variable groups: r.watershed (accumulation, basin, "
         "direction, outlet, segment, sub_catchment), r.stream.order (order_hack/horton/"
         "shreve/strahler/topo), r.stream.channel (channel_*), r.stream.slope "
         "(slope_curv_*/slope_elv_dw_cel/slope_grad_dw_cel), r.stream.distance "
         "(outlet_*/stream_*), flow.index (cti, spi, sti). Licence CC BY-NC 4.0. "
         "China merge: 17 tiles (h22v02 ... h32v02) -> gdalbuildvrt -> gdalwarp clipped to "
         "china.shp, NoData=-9999, DEFLATE. SEVEN variables (cti, channel_grad_dw_seg, "
         "channel_grad_up_cel, channel_grad_up_seg, slope_curv_max_dw_cel, "
         "slope_curv_min_dw_cel, accumulation) carry source-side numerical defects and were "
         "WITHDRAWN from delivery (8 archived layers).",
)

SRC[("dist", "h90m")] = dict(
    name="Hydrography90m, China merge - stream-distance subset (4 variables)",
    provider="Hydrography90m (Giuseppe Amatulli et al.); merged and clipped in this project",
    id="10.18728/igb-fred-762.1",
    citation="Amatulli, G., et al. (2022). Hydrography90m: a high-resolution global "
             "hydrographic dataset. Earth Syst. Sci. Data 14, 4525-4550. "
             "https://doi.org/10.5194/essd-14-4525-2022",
    crs="EPSG:4326",
    res="0.00083333 degree (3 arc-seconds, ~90 m)",
    extent="x[73.4525, 134.975] y[18.1642, 53.5308]; China",
    nodata="-9999",
    scale="x0.01 cm->m",
    note="Same source tree as the hydro theme; placed under dist/ because the four "
         "stream_dist_* variables are Euclidean/path distances used as accessibility "
         "covariates. min/max window statistics were added for all four (hydro_stats_addon).",
)

SRC[("lulc", "glu1km")] = dict(
    name="Global LULC projection dataset from 2020 to 2100 at a 1 km resolution "
         "(snapshots history_2020 and ssp{1_26,2_45,5_85}_{2030,2050,2100})",
    provider="Beijing Normal University, Prof. Changxiu Cheng's group "
             "(Zhang T., Cheng C., Wu X.); distributed via figshare article 23542860",
    id="10.1038/s41597-023-02637-7",
    citation="Zhang, T., Cheng, C., Wu, X. (2023). Mapping the spatial heterogeneity of global "
             "land use and land cover from 2020 to 2100 at a 1 km resolution. Scientific "
             "Data 10, 748. https://doi.org/10.1038/s41597-023-02637-7 "
             "(data: figshare article 23542860)",
    crs="ESRI:54004 (World Mercator) - note the separate Final/ subtree in the source is "
        "EPSG:4326 and is NOT used by this pipeline",
    res="1000 m",
    extent="x[-20037507.84, 20037492.16] y[-7523815.33, 18012184.67]; global",
    nodata="none declared (class value 0 = background, treated as NoData)",
    scale="none",
    note="Six classes, legend 1=cropland 2=forest 3=grassland 4=urban 5=barren 6=water. "
         "The source publishes 5 SSPs x 4 periods; this delivery uses the 3 SSPs "
         "(126/245/585) x 3 periods (2030/2050/2100) that match the climate scenarios, plus "
         "the 2020 historical snapshot. The source's own Final/ subtree contains a different, "
         "pre-derived set of layers (lu_*_r5cell.tif) that this project does not use.",
)

SRC[("vege", "glassndvi")] = dict(
    name="2000-2022 China 30 m annual maximum NDVI dataset, version V2 "
         "(delivery uses 2020, 2021, 2022 - the latest three years of the source)",
    provider="Institute of Geographic Sciences and Natural Resources Research, Chinese "
             "Academy of Sciences - Land Use and Global Change Remote Sensing group; "
             "distributed by the National Ecosystem Science Data Center (NESDC)",
    id="10.12199/nesdc.ecodb.rs.2021.012.",
    citation="Yang, J., Dong, J., Xiao, X., et al. (2019). Divergent shifts in peak "
             "photosynthesis timing of temperate and alpine grasslands in China. Remote "
             "Sensing of Environment 233, 111395. "
             "https://doi.org/10.1016/j.rse.2019.111395 "
             "(dataset: NESDC 10.12199/nesdc.ecodb.rs.2021.012.)",
    crs="EPSG:4326",
    res="0.00026949 degree (1 arc-second, ~30 m)",
    extent="x[73.44105, 135.08713] y[18.15962, 53.56178]; China (clipped to provincial "
           "boundaries by the provider on 2023-08-13)",
    nodata="32767",
    scale="x0.0001 (stored int16 = NDVI x 10000; valid storage range -10000..10000)",
    note="Computed on Google Earth Engine from Landsat 5/7/8/9 Collection 2; V2 adds a "
         "five-year NDVI/DOY median reference that replaces the annual maximum when its "
         "day-of-year deviates by more than one month. Delivered files are int16 with an "
         "overview pyramid (.ovr) written by ArcGIS 10.8.",
)

SRC[("vege", "agb2019")] = dict(
    name="2019 China forest aboveground biomass spatial distribution dataset",
    provider="Peking University, Prof. Qinghua Guo's group (Qiuli Yang et al.); distributed "
             "by the National Ecosystem Science Data Center (NESDC) as part of the China "
             "Vegetation Data Product collection (CVP)",
    id="10.12199/nesdc.ecodb.rs.2024.026.",
    citation="Yang, Q., Niu, C., Liu, X., Feng, Y., Ma, Q., Wang, X., Tang, H., Guo, Q. "
             "(2023). Mapping high-resolution forest aboveground biomass of China using "
             "multisource remote sensing data. GIScience & Remote Sensing 60(1), 2203303. "
             "https://doi.org/10.1080/15481603.2023.2203303 "
             "(dataset: NESDC 10.12199/nesdc.ecodb.rs.2024.026.)",
    crs="EPSG:4326",
    res="0.00027778 degree (1 arc-second, ~30 m; source grid "
        "226802 x 129601)",
    extent="x[72.99972, 136.00028] y[17.99986, 54.00014]; China",
    nodata="none declared in the GeoTIFF; zero-valued cells are forest-free",
    scale="none (values already in Mg/ha)",
    note="Mapped from multisource remote sensing. The dataset ships its own paper PDF "
         "(Mapping+high-resolution+forest+aboveground+biomass+...pdf), which is the source "
         "of the citation above.",
)

SRC[("vege", "ch2019")] = dict(
    name="2019 China forest canopy height spatial distribution dataset (30 m)",
    provider="Institute of Botany, Chinese Academy of Sciences / Peking University "
             "(Xiaoqiang Liu, Yanjun Su et al.); distributed by the National Ecosystem "
             "Science Data Center (NESDC); also published on PlantPlus as "
             "10.12282/plantdata.164",
    id="10.12199/nesdc.ecodb.rs.2024.027.",
    citation="Liu, X., Su, Y., Hu, T., Yang, Q., Liu, B., Deng, Y., Tang, H., Tang, Z., "
             "Fang, J., Guo, Q. (2022). Neural network guided interpolation for mapping "
             "canopy height of China's forests by integrating GEDI and ICESat-2 data. "
             "Remote Sensing of Environment 269, 112844. "
             "https://doi.org/10.1016/j.rse.2021.112844 "
             "(dataset: NESDC 10.12199/nesdc.ecodb.rs.2024.027.; "
             "PlantPlus 10.12282/plantdata.164)",
    crs="EPSG:4326",
    res="0.00027778 degree (1 arc-second, ~30 m; source grid 221716 x 128020)",
    extent="x[73.50097, 135.08875] y[17.99986, 53.56097]; China",
    nodata="65535",
    scale="x0.1 (stored in decimetres, delivered in metres)",
    note="GEDI + ICESat-2 guided neural-network interpolation. The dataset ships its own "
         "paper PDF, which is the source of the citation above.",
)

SRC[("vege", "catcd")] = dict(
    name="CATCD_2025 - China annual tree-cover dataset, 2025 edition "
         "(band description 'TreeCover')",
    provider="Sun Yat-sen University (Yao-Tong Cai et al.); distributed via Zenodo",
    id="10.1016/j.isprsjprs.2024.08.001",
    citation="Cai, Y., et al. (2024). Revealing the temporal dynamics of woody cover in China "
             "from 1985 to 2023 with 30 m Landsat-based tree cover mapping. ISPRS Journal "
             "of Photogrammetry and Remote Sensing 216, 240-258. "
             "https://doi.org/10.1016/j.isprsjprs.2024.08.001 "
             "(data: https://zenodo.org/records/19160322)",
    crs="EPSG:4326",
    res="0.00026949 degree (1 arc-second, ~30 m; source grid 228538 x 133826)",
    extent="x[73.50007, 135.08982] y[17.90333, 53.96872]; China",
    nodata="-128",
    scale="none (tree cover already in percent)",
    note="Source GeoTIFF carries system->index = CATCD_2025 and time_start = 1735689600000 "
         "(2025-01-01). A companion Uncertainty layer exists in the source but is not "
         "delivered here.",
)

SRC[("anthro", "foothii")] = dict(
    name="Human Footprint Index, annual 2001-2020 (20 layers)",
    provider="Wildlife Conservation Society (WCS)",
    id="https://wcshumanfootprint.org/data-access",
    citation="Sanderson, E. W., Fisher, K., Robinson, N., Sampson, D., Duncan, A., "
             "Royte, L. (2022). The March of the Human Footprint. EcoEvoRxiv preprint, "
             "2022-09-29. https://ecoevorxiv.org/repository/view/3641/ "
             "(data: https://wcshumanfootprint.org/data-access, licence CC BY-NC-SA 3.0)",
    crs="EPSG:4326",
    res="0.00269495 degree (~9.7 arc-seconds, ~300 m)",
    extent="global x[-180.00082, 180.00082] y[-58.00062, 84.00146]",
    nodata="-32768",
    scale="x0.01 (stored int16 = index x 100; stored range 0-5900 -> index 0-59)",
    note="20 annual layers (2001-2020). The source publishes no 2021 file, so the delivery "
         "faithfully contains 20 years and not 21. Files are distributed one GeoTIFF per "
         "date from https://storage.googleapis.com/hii-export/<YYYY-MM-DD>/hii_<YYYY-MM-DD>.tif, "
         "which matches the delivered source filenames exactly. Licence CC BY-NC-SA 3.0 - "
         "non-commercial use only, attribution required.",
)

SRC[("anthro", "landscan")] = dict(
    name="LandScan Global, annual 2000-2024 (25 layers)",
    provider="Oak Ridge National Laboratory (Edward Bright, Phillip Coleman)",
    id="10.48690/1524196",
    citation="Bright, E., Coleman, P. (2001-). LandScan Global. Oak Ridge National "
             "Laboratory, Oak Ridge, TN. https://doi.org/10.48690/1524196 "
             "(landscan.ornl.gov)",
    crs="EPSG:4326",
    res="0.00833333 degree (30 arc-seconds, ~1 km)",
    extent="global x[-180, 180] y[-90, 86]",
    nodata="-2147483647",
    scale="none (persons per cell)",
    note="Ambient population (24 h average) from a dasymetric model. Each annual release "
         "ships an *_assets folder containing the raster plus an XML/RIS citation record; the "
         "RIS record is the source of the citation above. A colourised uint8 GeoTIFF in the "
         "same folder is for display only and is not used.",
)

SRC[("anthro", "smod")] = dict(
    name="GHS-SMOD R2023A (GHS_SMOD_E<year>_GLOBE_R2023A_4326_30ss_V2_0), epochs 1975-2030",
    provider="European Commission, Joint Research Centre (Global Human Settlement Layer); "
             "Schiavina M., Melchiorri M., Pesaresi M.",
    id="10.2905/A0DF7A6F-49DE-46EA-9BDE-563437A6E2BA",
    citation="Schiavina, M., Melchiorri, M., Pesaresi, M. (2023). GHS-SMOD R2023A - GHS "
             "settlement layers, application of the Degree of Urbanisation methodology "
             "(stage I) to GHS-POP R2023A and GHS-BUILT-S R2023A, multitemporal "
             "(1975-2030). European Commission, Joint Research Centre. "
             "https://doi.org/10.2905/A0DF7A6F-49DE-46EA-9BDE-563437A6E2BA "
             "Licence CC BY 4.0",
    crs="EPSG:4326",
    res="0.00833333 degree (30 arc-seconds, ~1 km)",
    extent="global x[-180.0079, 180.0087] y[-89.1004, 89.0996]",
    nodata="-200",
    scale="none (categorical class codes)",
    note="Classes present over China: 10 (water), 11 (very low density rural), 12 (low "
         "density rural), 13 (rural cluster), 21 (suburban / low-density urban), "
         "22 (semi-dense urban cluster), 23 (dense urban cluster), 30 (urban centre). "
         "The urban proportion layer uses classes 21, 22, 23. 12 epochs delivered.",
)

SRC[("dist", "gsw")] = dict(
    name="JRC Global Surface Water v1.5 (2024 update), 'extent' layer, "
         "42 China tiles merged",
    provider="European Commission, Joint Research Centre (Jean-Francois Pekel et al.)",
    id="10.1038/nature20584",
    citation="Pekel, J.-F., Cottam, A., Gorelick, N., Belward, A. S. (2016). High-resolution "
             "mapping of global surface water and its long-term changes. Nature 540, 418-422. "
             "https://doi.org/10.1038/nature20584 "
             "(data: https://global-surface-water.appspot.com/download)",
    crs="EPSG:4326",
    res="0.00025 degree (~1 arc-second, ~30 m); each tile 40000 x 40000",
    extent="42 tiles covering China; e.g. extent_100E_10N covers x[100, 110] y[0, 10]",
    nodata="none declared; value 255 marks land/no-water and is excluded",
    scale="none (values {0, 1, 255}, 1 = water)",
    note="Only the water mask is used, to build a Euclidean distance-to-water layer. "
         "Version string v1_5_2024 appears in the source filenames.",
)

SRC[("dist", "grip4")] = dict(
    name="GRIP4 (Global Roads Inventory Project), region 6 shapefile, version 4 (2018); "
         "attribute GP_RTP",
    provider="PBL Netherlands Environmental Assessment Agency (Meijer et al.); "
             "GRIP4_Region6_vector_shp",
    id="10.1088/1748-9326/aabd42",
    citation="Meijer, J. R., Huijbregts, M. A. J., Schotten, K. C. G. J., Schipper, A. M. "
             "(2018). Global patterns of current and future road infrastructure. "
             "Environmental Research Letters 13, 064006. "
             "https://doi.org/10.1088/1748-9326/aabd42 "
             "(data: https://zenodo.org/records/6420961)",
    crs="EPSG:4326 (shapefile)",
    res="vector",
    extent="region 6 shapefile covering the study area",
    nodata="not applicable",
    scale="not applicable",
    note="GP_RTP codes: 1 = Highways, 2 = Primary roads, 3 = Secondary roads, 4 = Tertiary, "
         "5 = Local, 0 = Unspecified. The two delivered distance layers use all roads and "
         "the subset {1,2,3} respectively.",
)

SRC[("dist", "osm")] = dict(
    name="OpenStreetMap extract china-260805.osm.pbf (2026-08-05 snapshot of the China "
         "extract)",
    provider="OpenStreetMap contributors",
    id="https://www.openstreetmap.org",
    citation="OpenStreetMap contributors. OpenStreetMap extract, china-260805.osm.pbf, "
             "downloaded 2026-08-05. https://www.openstreetmap.org "
             "(licence ODbL: https://opendatacommons.org/licenses/odbl/)",
    crs="EPSG:4326",
    res="vector",
    extent="China extract as delivered by the provider",
    nodata="not applicable",
    scale="not applicable",
    note="Trails selected with highway IN ('path','footway'); 793636 matching ways were "
         "found in the extract. Licence ODbL - attribution required.",
)

SRC[("dist", "smod")] = dict(
    name="GHS-SMOD R2023A, epoch 2020, urban classes 21/22/23 used as the urban mask",
    provider="European Commission, Joint Research Centre (Global Human Settlement Layer)",
    id="10.2905/A0DF7A6F-49DE-46EA-9BDE-563437A6E2BA",
    citation="Schiavina, M., Melchiorri, M., Pesaresi, M. (2023). GHS-SMOD R2023A - GHS "
             "settlement layers, application of the Degree of Urbanisation methodology "
             "(stage I) to GHS-POP R2023A and GHS-BUILT-S R2023A, multitemporal "
             "(1975-2030). European Commission, Joint Research Centre. "
             "https://doi.org/10.2905/A0DF7A6F-49DE-46EA-9BDE-563437A6E2BA "
             "Licence CC BY 4.0",
    crs="EPSG:4326",
    res="0.00833333 degree (30 arc-seconds, ~1 km)",
    extent="global x[-180.0079, 180.0087] y[-89.1004, 89.0996]",
    nodata="-200",
    scale="none",
    note="Same source raster as the anthro/smod theme; used here to build a "
         "distance-to-urban-centre layer.",
)

# mask / template provenance, not a delivered covariate theme
MASK_SRC = dict(
    name="china.shp + dashline.shp (national boundary and dashed boundary lines)",
    provider="project-supplied boundary vectors",
    id="TODO: boundary source not stated",
    citation="TODO: citation required",
    crs="geographic input, rasterised to the China_Albers 1 km template",
    res="vector",
    extent="x[-2637869.7, 2202732.4] y[1877231.8, 5918789.7] after projection to China_Albers",
    nodata="not applicable",
    scale="not applicable",
    note="Rasterised with all_touched=True onto the 1 km template, producing "
         "data/mask_china.tif (9490310 valid cells). Every delivered layer is clipped to "
         "this mask.",
)
