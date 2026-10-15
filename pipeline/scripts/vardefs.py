# -*- coding: utf-8 -*-
"""vardefs.py -- variable definitions for the CHECO26 provenance table.
Evidence grading (recorded in the definition string itself):
  [std]  international standard definition (Bioclim, NDVI, ...)
  [doc]  taken verbatim/near-verbatim from the dataset's own documentation
  [name] derived from the variable name + measured value range + unit
  [?]    not determinable from the sources inspected -- needs external input

Sources consulted (all read in this session):
  * ScienceDB 10.57760/sciencedb.13546 + its Documentation.docx   -> bioclim
  * CSDLv2 readme_EN.docx + ESSD 17:517 (2025) + 100-page supplement -> soil
  * Hydrography90m_变量全览.md + h90m/Final/README.md              -> hydro, dist/h90m
  * dataDescrip.pdf (NESDC, NDVI V2)                               -> vege/glassndvi
  * paper PDFs shipped with the NESDC data                          -> vege/agb2019, ch2019
  * glbrc/GRIP4, GSW, GHSL, LandScan, footHII, CATCD docs           -> dist, anthro, vege
"""

import re

# name -> (definition, evidence)
VDEF = {}

# ----------------------------------------------------------------- bioclim
# Definition table from the dataset's own Documentation.docx (Table 1),
# units from the dataset's own machine-readable layer table
# (CHNECO26_datalayers_details_bioclim.csv).
_BIOCLIM = {
    "bio01": ("Annual Mean Temperature", "degC", "std"),
    "bio02": ("Mean Diurnal Range = mean of monthly (tasmax - tasmin)", "degC", "std"),
    "bio03": ("Isothermality = Bio2 / Bio7 x 100", "percent", "std"),
    "bio04": ("Temperature Seasonality = standard deviation of monthly tas, x100", "index_x100", "doc"),
    "bio05": ("Max Temperature of Warmest Month", "degC", "std"),
    "bio06": ("Min Temperature of Coldest Month", "degC", "std"),
    "bio07": ("Temperature Annual Range = Bio5 - Bio6", "degC", "std"),
    "bio08": ("Mean Temperature of Wettest Quarter", "degC", "std"),
    "bio09": ("Mean Temperature of Driest Quarter", "degC", "std"),
    "bio10": ("Mean Temperature of Warmest Quarter", "degC", "std"),
    "bio11": ("Mean Temperature of Coldest Quarter", "degC", "std"),
    "bio12": ("Annual Precipitation", "mm", "std"),
    "bio13": ("Precipitation of Wettest Month", "mm", "std"),
    "bio14": ("Precipitation of Driest Month", "mm", "std"),
    "bio15": ("Precipitation Seasonality = coefficient of variation of monthly pr", "coefficient_of_variation", "doc"),
    "bio16": ("Precipitation of Wettest Quarter", "mm", "std"),
    "bio17": ("Precipitation of Driest Quarter", "mm", "std"),
    "bio18": ("Precipitation of Warmest Quarter", "mm", "std"),
    "bio19": ("Precipitation of Coldest Quarter", "mm", "std"),
    "bio20": ("Accumulated Growing Degree Days, daily temperature > 0 degC (extended variable)", "degC", "doc"),
    "bio21": ("Accumulated Growing Degree Days, daily temperature > 5 degC (extended variable)", "degC", "doc"),
    "bio22": ("Annual Potential Evapotranspiration (extended variable)", "mm", "doc"),
    "bio23": ("Moisture Index = Bio12 / Bio22 (extended variable)", "ratio", "doc"),
    "prec": ("Annual precipitation = sum of 12 monthly pr bands", "mm", "doc"),
    "tave": ("Annual mean temperature = mean of 12 monthly tas bands", "degC", "doc"),
    "tmax": ("Annual mean of monthly maximum temperature = mean of 12 monthly tasmax bands", "degC", "doc"),
    "tmin": ("Annual mean of monthly minimum temperature = mean of 12 monthly tasmin bands", "degC", "doc"),
    "sunp": ("Annual mean percentage of sunshine = mean of 12 monthly sunp bands; only published for the ensemble-mean chain", "percent", "doc"),
}
for _ds in ("cnclim1km", "cnclim1km-bcc-csm2-mr", "cnclim1km-ensmean"):
    for _v, (_d, _u, _e) in _BIOCLIM.items():
        VDEF[("bioclim", _ds, _v)] = ("%s [%s] [%s]" % (_d, _u, _e))

# ----------------------------------------------------------------- lulc (glu1km)
# class definitions: legend in config.yaml, from the source paper (Zhang et al. 2023)
_LULC_CLASS = {
    "cropland": "Cropland",
    "forest": "Forest",
    "grassland": "Grassland",
    "urban": "Urban / built-up",
    "barren": "Barren",
    "water": "Water body",
}
for _c, _name in _LULC_CLASS.items():
    VDEF[("lulc", "glu1km", _c)] = (
        "Areal proportion of land-cover class \"%s\" within the output cell [ratio 0-1] [doc]" % _name)
VDEF[("lulc", "glu1km", "edge")] = (
    "Edge density of the all-class landscape: fraction of the 4-neighbourhood pairs that differ "
    "in land-cover class [ratio 0-1] [doc]")
VDEF[("lulc", "glu1km", "shannon")] = (
    "Shannon diversity index of the land-cover composition, -sum(p*ln(p)) over the 6 classes, "
    "natural logarithm [nats, 0..ln6=1.7918] [doc]")
VDEF[("lulc", "glu1km", "patchdensityAll")] = (
    "Patch density of the all-class landscape: number of 4-connected patches inside the disk "
    "window divided by the window area, x100 [patches per 100 km2] [doc]")
VDEF[("lulc", "glu1km", "patchdensityForest")] = (
    "Patch density of the forest class only (class 2): number of 4-connected forest patches "
    "inside the disk window divided by the window area, x100 [patches per 100 km2] [doc]")
VDEF[("lulc", "glu1km", "patchsizeAll")] = (
    "Mean patch size of the all-class landscape: area of the patch containing the window anchor, "
    "averaged over patches in the window [km2] [doc]")
VDEF[("lulc", "glu1km", "patchsizeForest")] = (
    "Mean patch size of the forest class only (class 2) [km2] [doc]")

# LULC snapshots: the leaf directory is the variable for 2020 / for each SSP, but the
# derived metrics keep their own leaf. Map (snapshot -> metric leaf) so every layer keys
# on its actual metric.
_LULC_METRIC = {
    "cropland": "cropland", "forest": "forest", "grassland": "grassland",
    "urban": "urban", "barren": "barren", "water": "water",
    "edge": "edge", "shannon": "shannon",
    "patchdensityAll": "patchdensityAll", "patchdensityForest": "patchdensityForest",
    "patchsizeAll": "patchsizeAll", "patchsizeForest": "patchsizeForest",
}
for _metric in _LULC_METRIC:
    for _snap in ("2020", "ssp126", "ssp245", "ssp585"):
        VDEF[("lulc", "glu1km", "%s@%s" % (_metric, _snap))] = VDEF[("lulc", "glu1km", _metric)]

# ----------------------------------------------------------------- soil (csdlv2)
# 28 attributes. Names/units/definitions from the dataset README table and its
# 100-page supplement (sections S2-S24) plus the ESSD paper.
_SOIL = {
    "bd": ("Bulk density of the fine-earth fraction, oven dried", "g/cm3", "doc"),
    "sand": ("Gravimetric percentage of sand (2-0.05 mm) in the fine-earth fraction", "%", "doc"),
    "silt": ("Gravimetric percentage of silt (0.05-0.02 mm) in the fine-earth fraction", "%", "doc"),
    "clay": ("Gravimetric percentage of clay (<0.02 mm) in the fine-earth fraction", "%", "doc"),
    "gravel": ("Rock fragment content: volumetric content of fragments >2 mm in the whole soil", "% by volume", "doc"),
    "porosity": ("Volume fraction of void space (pores) in the material", "% by volume", "doc"),
    "ph": ("Soil pH in H2O: negative common logarithm of H+ activity", "pH units", "doc"),
    "oc": ("Soil organic carbon content, gravimetric, in the fine-earth fraction", "g/100g", "doc"),
    "socd": ("Soil organic carbon density: mass of organic carbon per unit area in the soil profile. "
             "Present in the dataset README table and on disk, but not mentioned in the ESSD article "
             "or its supplement (verified by full-text search) - repository-only addition.", "kg C/m2", "doc"),
    "cec": ("Cation exchange capacity of the fine-earth fraction", "me/100g", "doc"),
    "tn": ("Total nitrogen (organic, inorganic and ammonium forms)", "g/100g", "doc"),
    "tp": ("Total phosphorus, all organic and inorganic compounds irrespective of plant availability", "g/100g", "doc"),
    "tk": ("Total potassium, exchangeable and non-exchangeable forms", "g/100g", "doc"),
    "an": ("Alkali-hydrolysable nitrogen: nitrogen released by alkali treatment", "mg/kg", "doc"),
    "ak": ("Available potassium: readily plant-accessible portion", "mg/kg", "doc"),
    "ap": ("Available phosphorus: extractable, readily plant-accessible fraction", "mg/kg", "doc"),
    "wet-r": ("Red component of RGB-quantified soil colour, wet soil", "RGB code 0-255", "doc"),
    "wet-g": ("Green component of RGB-quantified soil colour, wet soil", "RGB code 0-255", "doc"),
    "wet-b": ("Blue component of RGB-quantified soil colour, wet soil", "RGB code 0-255", "doc"),
    "dry-r": ("Red component of RGB-quantified soil colour, dry soil", "RGB code 0-255", "doc"),
    "dry-g": ("Green component of RGB-quantified soil colour, dry soil", "RGB code 0-255", "doc"),
    "dry-b": ("Blue component of RGB-quantified soil colour, dry soil", "RGB code 0-255", "doc"),
    "wet-hue": ("Munsell hue of wet soil colour", "Munsell hue code", "doc"),
    "wet-value": ("Munsell value of wet soil colour", "Munsell value code", "doc"),
    "wet-chroma": ("Munsell chroma of wet soil colour", "Munsell chroma code", "doc"),
    "dry-hue": ("Munsell hue of dry soil colour", "Munsell hue code", "doc"),
    "dry-value": ("Munsell value of dry soil colour", "Munsell value code", "doc"),
    "dry-chroma": ("Munsell chroma of dry soil colour", "Munsell chroma code", "doc"),
}
_DEPTH_LABEL = {
    "0": "0-5 cm", "5": "5-15 cm", "15": "15-30 cm",
    "30": "30-60 cm", "60": "60-100 cm", "100": "100-200 cm",
    "profile": "whole profile (0-200 cm, depth-integrated as published by the data provider)",
}
for _a, (_d, _u, _e) in _SOIL.items():
    for _tag, _lab in _DEPTH_LABEL.items():
        VDEF[("soil", "csdlv2", "%s@%s" % (_a, _tag))] = (
            "%s; depth interval %s [%s] [%s]" % (_d, _lab, _u, _e))

# ----------------------------------------------------------------- hydro + dist (h90m)
# Definitions from Hydrography90m_变量全览.md (Chinese) and h90m/Final/README.md,
# both of which document the GRASS GIS module that produced each layer.
_H90M = {
    "cti": ("Compound Topographic Index (wetness index), ln(accumulation / tan(slope)). "
            "WITHDRAWN from delivery: the source values are unusable (|values| up to 1.7e9 "
            "where the index cannot exceed a few tens; 99.7% of source cells negative)",
            "dimensionless", "doc"),
    "accumulation": ("Flow accumulation: upstream contributing area [km2]. WITHDRAWN from delivery: "
                     "the source raster contains negative values although the unit is an area",
                     "km2", "doc"),
    "channel-grad-dw-seg": ("Mean gradient of the downstream segment between focal cell and the "
                            "node/outlet. WITHDRAWN from delivery: source median ~9e4 cm/m against a "
                            "physical limit near 100 cm/m", "cm/m (source)", "doc"),
    "channel-grad-up-cel": ("Upstream gradient from focal cell to the next cell. WITHDRAWN from "
                            "delivery: source values exceed the physical limit", "cm/m (source)", "doc"),
    "channel-grad-up-seg": ("Mean gradient of the upstream segment between focal cell and the "
                            "init/node. WITHDRAWN from delivery: source values exceed the physical limit",
                            "cm/m (source)", "doc"),
    "slope-curv-max-dw-cel": ("Maximum curvature between the highest upstream cell, the focal cell and "
                              "the downstream cell. WITHDRAWN from delivery: source saturates at "
                              "+/-384900 (unit 1/m)", "1/m", "doc"),
    "slope-curv-min-dw-cel": ("Minimum curvature between the highest upstream cell, the focal cell and "
                              "the downstream cell. WITHDRAWN from delivery: source saturates at "
                              "+/-384900 (unit 1/m)", "1/m", "doc"),
    "basin": ("Drainage basin identifier (unique per basin)", "class code", "doc"),
    "sub-catchment": ("Sub-catchment identifier (shared with its stream segment)", "class code", "doc"),
    "segment": ("Stream segment identifier (globally unique)", "class code", "doc"),
    "outlet": ("Drainage-basin outlet marker", "class code", "doc"),
    "direction": ("Flow direction, D8 encoding (1=NE, 2=N, 3=NW, 4=W, 5=SW, 6=S, 7=SE, 8=E; "
                  "negative values encode the corresponding diagonal (flow into the DEM edge))", "class code", "doc"),
    "order-strahler": ("Strahler stream order", "class code", "doc"),
    "order-shreve": ("Shreve stream magnitude", "class code", "doc"),
    "order-horton": ("Horton stream order", "class code", "doc"),
    "order-hack": ("Hack stream order", "class code", "doc"),
    "order-topo": ("Topological dimension of the stream network", "class code", "doc"),
    "channel-curv-cel": ("Channel curvature at the focal cell", "dimensionless", "doc"),
    "channel-dist-dw-seg": ("Distance from focal cell to the downstream segment node/outlet", "m", "doc"),
    "channel-dist-up-cel": ("Upstream distance from focal cell to the next cell", "m", "doc"),
    "channel-dist-up-seg": ("Distance from focal cell to the upstream segment init/node", "m", "doc"),
    "channel-elv-dw-cel": ("Elevation difference from focal cell to the next downstream cell", "m", "doc"),
    "channel-elv-dw-seg": ("Elevation difference from focal cell to the downstream segment node/outlet", "m", "doc"),
    "channel-elv-up-cel": ("Elevation difference from focal cell to the next upstream cell", "m", "doc"),
    "channel-elv-up-seg": ("Elevation difference from focal cell to the upstream segment init/node", "m", "doc"),
    "slope-elv-dw-cel": ("Elevation difference between focal cell and downstream cell", "m", "doc"),
    "slope-grad-dw-cel": ("Focal-cell gradient (elevation difference / distance)", "dimensionless", "doc"),
    "stream-dist-up-near": ("Shortest upstream distance from focal cell to the sub-catchment drainage divide", "m", "doc"),
    "stream-dist-up-farth": ("Longest upstream distance from focal cell to the sub-catchment drainage divide", "m", "doc"),
    "stream-dist-dw-near": ("Distance from focal cell to its nearest downstream stream cell", "m", "doc"),
    "stream-dist-proximity": ("Euclidean distance from focal cell to the stream network", "m", "doc"),
    "stream-diff-up-near": ("Elevation difference along the shortest path from focal cell to the drainage divide", "m", "doc"),
    "stream-diff-up-farth": ("Elevation difference along the longest path from focal cell to the drainage divide", "m", "doc"),
    "stream-diff-dw-near": ("Elevation difference between focal cell and its nearest downstream stream cell", "m", "doc"),
    "outlet-dist-dw-basin": ("Distance from focal cell to the outlet cell of the basin", "m", "doc"),
    "outlet-dist-dw-scatch": ("Distance from focal cell to the downstream stream node cell", "m", "doc"),
    "outlet-diff-dw-basin": ("Elevation difference from focal cell to the basin outlet cell", "m", "doc"),
    "outlet-diff-dw-scatch": ("Elevation difference from focal cell to the downstream stream node cell", "m", "doc"),
    "spi": ("Stream Power Index: erosive power of flowing water, ln(accumulation * tan(slope))", "dimensionless", "doc"),
    "sti": ("Sediment Transport Index: (accumulation/22.13)^0.6 * (sin(slope)/0.0896)^1.3", "dimensionless", "doc"),
}
for _v, (_d, _u, _e) in _H90M.items():
    VDEF[("hydro", "h90m", _v)] = ("%s [%s] [%s]" % (_d, _u, _e))
for _v in ("stream-dist-dw-near", "stream-dist-proximity", "stream-dist-up-farth", "stream-dist-up-near"):
    _d, _u, _e = _H90M[_v]
    VDEF[("dist", "h90m", _v)] = ("%s [%s] [%s]" % (_d, _u, _e))

# ----------------------------------------------------------------- dist (others)
VDEF[("dist", "grip4", "road")] = (
    "Euclidean distance to the nearest GRIP4 road of any type [m] [name]")
VDEF[("dist", "grip4", "majorroad")] = (
    "Euclidean distance to the nearest GRIP4 major road (GP_RTP in {Highways 1, Primary 2, Secondary 3}) [m] [name]")
VDEF[("dist", "gsw", "water")] = (
    "Euclidean distance to the nearest JRC Global Surface Water cell classified as water "
    "(seasonal or permanent; class 255 excluded) [m] [name]")
VDEF[("dist", "osm", "trail")] = (
    "Euclidean distance to the nearest OpenStreetMap trail "
    "(highway in {path, footway}) [m] [name]")
VDEF[("dist", "smod", "urban")] = (
    "Euclidean distance to the nearest GHS-SMOD urban centre (class 21/22/23) [m] [name]")

# ----------------------------------------------------------------- anthro
VDEF[("anthro", "foothii", "hii")] = (
    "Human Footprint Index of the human-footprint project (WCS): summed, standardised human "
    "pressure score; stored 0-5900 and rescaled x0.01 to the index 0-59. "
    "Units: index 0-59. Evidence: [doc]")
VDEF[("anthro", "landscan", "pop")] = (
    "Ambient population count per 30 arc-second cell (average over 24 h) [persons per cell] [doc]")
VDEF[("anthro", "smod", "urbanprop")] = (
    "Areal proportion within the output cell of GHS-SMOD urban classes 21 (low-density), "
    "22 (moderate-density) and 23 (high-density) built-up [ratio 0-1] [doc]")

# ----------------------------------------------------------------- topo (chinadem)
VDEF[("topo", "chinadem", "elev")] = ("Terrain elevation [m above sea level] [name]")
VDEF[("topo", "chinadem", "slope")] = ("Terrain slope angle [degrees] [name]")
VDEF[("topo", "chinadem", "aspect")] = ("Terrain aspect, 0 deg = north, clockwise [degrees 0-360] [name]")
VDEF[("topo", "chinadem", "tri")] = (
    "Terrain Ruggedness Index, Riley et al. (1999): root-mean-square of the elevation "
    "difference to the 8 neighbours in a 3x3 window [m] [doc]")

# ----------------------------------------------------------------- vege
VDEF[("vege", "glassndvi", "ndvimax")] = (
    "Annual maximum NDVI from Landsat 5/7/8/9 valid observations (dataset V2); stored as "
    "int16 = NDVI x 10000 [NDVI -1..1] [doc]")
VDEF[("vege", "agb2019", "agb")] = (
    "Forest aboveground biomass, 2019, mapped from multisource remote sensing [Mg/ha] [doc]")
VDEF[("vege", "ch2019", "ch")] = (
    "Forest canopy height, 2019, from GEDI + ICESat-2 guided interpolation; stored in dm and "
    "rescaled x0.1 to metres [m] [doc]")
VDEF[("vege", "catcd", "treecover")] = (
    "Annual tree-cover fraction of the CATCD dataset (tree cover in percent of the cell) "
    "[% 0-100] [doc]")


# =====================================================================
# Path -> variable key resolution.
#
# A delivered layer path looks like  glo/<theme>/<dataset>/.../<leaf>/<file>.tif
# with the variable normally carried by the leaf directory:
#   glo/dist/grip4/majorroad/x.tif                        leaf = variable
#   glo/anthro/foothii/2001/hii/x.tif                     leaf = variable (2001 = year)
#   glo/lulc/glu1km/2020/cropland/x.tif                   leaf = metric, 2020 = snapshot
#   glo/soil/csdlv2/ak/0/x.tif                            attr + depth  ->  "ak@0"
#   glo/soil/csdlv2/ak/x.tif                              profile layer ->  "ak@profile"
#
# IMPORTANT -- the 240 "flat" LULC layers.
# 04_derive_lulc.py writes its six derived metrics with an EMPTY folder suffix
# (write(snapshot_parts(cfg, snap, []), ...)), so the metric name lives in the
# FILENAME and the layer sits directly in the snapshot directory:
#   glo/lulc/glu1km/2020/glo_lulc_glu1km_2020_edge.tif
#   glo/lulc/glu1km/scenario/2030/ssp126/glo_lulc_glu1km_scenario_2030_ssp126_edge.tif
# This is self-consistent -- common.layer_path() guarantees
# basename == folder-path-joined-by-underscore + suffix -- and it passes
# nsdm.datacheck. But nsdm.covinfo, which takes the IMMEDIATE PARENT folder as
# `variable`, therefore records variable = "2020" / "ssp126" for these layers.
# They are kept exactly as the pipeline produced them (renaming would put the
# disk out of sync with the script); the metric is recovered from the filename
# here so that the provenance table still names it correctly.
# =====================================================================

_SNAPSHOTS = ("2020", "ssp126", "ssp245", "ssp585")
_FLAT_METRIC = {                       # filename metric -> canonical VDEF metric key
    "edge": "edge",
    "shannon": "shannon",
    "patchdensity-all": "patchdensityAll",
    "patchdensity-forest": "patchdensityForest",
    "patchsize-all": "patchsizeAll",
    "patchsize-forest": "patchsizeForest",
}


def unit_for(relpath):
    """Return the unit advertised inside the definition, or None.

    Every definition ends either with "... Units: X. Evidence: [tag]" or with a
    trailing "[unit] [tag]". This reads that unit back out, which matters for the
    8 withdrawn layers: they are no longer in variable_dictionary.csv (that file
    only covers the delivery tree), so their unit has to come from here.
    """
    d = definition_for(relpath)
    m = re.search(r"Units:\s*(.+?)\.\s*Evidence:\s*\[", d)
    if m:
        return m.group(1).strip()
    m = re.search(r"\[([^\[\]]+)\]\s*\[(?:std|doc|name|\?)\]\s*$", d)
    if m:
        return m.group(1).strip()
    return None


# ---------------------------------------------------------------------------
# Unit vocabulary, English.
#
# The pipeline's internal variable_dictionary.csv labels units in Chinese
# (比例(0-1), 人/像元, 类别编码, ...). The provenance table is metadata destined for
# an English-language database, so units are translated here. The mapping is
# explicit and complete: unit_en() raises on an unknown label rather than passing
# Chinese text through.
# ---------------------------------------------------------------------------
UNIT_EN = {
    "比例(0-1)": "ratio (0-1)",
    "degC": "degrees Celsius",
    "mm": "millimetres",
    "(-)": "dimensionless",
    "人/像元": "persons per cell",
    "指数(0-59)": "index (0-59)",
    "km2": "square kilometres",
    "个/100km2": "patches per 100 square kilometres",
    "%": "percent",
    "m": "metres",
    "g/100g": "grams per 100 grams",
    "mg/kg": "milligrams per kilogram",
    "NDVI(-)": "NDVI (dimensionless, -1 to 1)",
    "RGB B(编码)": "RGB blue code (0-255)",
    "RGB G(编码)": "RGB green code (0-255)",
    "RGB R(编码)": "RGB red code (0-255)",
    "Munsell hue(编码)": "Munsell hue code",
    "Munsell value(编码)": "Munsell value code",
    "Munsell chroma(编码)": "Munsell chroma code",
    "类别编码": "class code (integer)",
    "g/cm3": "grams per cubic centimetre",
    "me/100g": "milliequivalents per 100 grams",
    "pH(-)": "pH units",
    "kg C/m2": "kilograms of carbon per square metre",
    "Mg/ha": "megagrams per hectare",
    "cm/m (source)": "centimetres per metre (as stored in the source)",
    "1/m": "per metre",
    "dimensionless": "dimensionless",
    "deg(0-360,北=0顺时针)": "degrees (0-360, 0 = north, clockwise)",
    "deg": "degrees",
}


def unit_en(label):
    """English unit for a pipeline unit label. Unknown labels are surfaced, not hidden."""
    if label is None:
        return None
    s = str(label).strip()
    if not s:
        return None
    if s in UNIT_EN:
        return UNIT_EN[s]
    if s in UNIT_EN.values():          # already English
        return s
    raise KeyError("no English unit registered for %r -- add it to UNIT_EN" % s)


# ---------------------------------------------------------------------------
# Focal geometry. `_f<metres>` layers are equal-weight SQUARE windows of
# radius_cells = metres / 1000, i.e. size = 2*radius_cells + 1 cells.
# ---------------------------------------------------------------------------
FOCAL_WINDOW = {
    1000: (3, 3),
    5000: (11, 11),
    10000: (21, 21),
    20000: (41, 41),
}


def focal_window_text(metres):
    """e.g. 1000 -> '3x3 square window (3 km x 3 km)'."""
    n = FOCAL_WINDOW.get(metres)
    if not n:
        return None
    return "%dx%d square window (%d km x %d km)" % (n[0], n[1], metres // 1000, metres // 1000)


def parse_layer(relpath):
    """Return (theme, dataset, varkey, flat_flag).

    varkey is the canonical VDEF key (e.g. 'ak@0', 'edge@2020').
    flat_flag marks the LULC layers whose metric lives in the filename.
    """
    p = relpath.replace("\\", "/")
    ds = p.split("/")[1:-1]                 # drop level folder + filename
    theme, dataset = ds[0], ds[1]

    if theme == "soil":
        attr = ds[2]
        depth = ds[3] if len(ds) > 3 else "profile"
        return theme, dataset, "%s@%s" % (attr, depth), False

    if theme == "lulc":
        leaf = ds[-1]
        if leaf in _SNAPSHOTS:
            stem = re.sub(r"_f\d+$", "", p.rsplit("/", 1)[1][:-4])
            m = re.match(r"^glo_lulc_glu1km_(?:scenario_\d+_)?(?:ssp\d+|20\d\d)_(.+)$", stem)
            metric = _FLAT_METRIC.get(m.group(1)) if m else None
            if metric:
                return theme, dataset, "%s@%s" % (metric, leaf), True
            return theme, dataset, "UNPARSED@%s" % leaf, True
        snap = ds[-2] if ds[-2] in _SNAPSHOTS else None
        return theme, dataset, ("%s@%s" % (leaf, snap)) if snap else leaf, False

    return theme, dataset, ds[-1], False


def definition_for(relpath):
    """Return the graded definition string, or a [?] placeholder if unresolved."""
    theme, dataset, varkey, _ = parse_layer(relpath)
    key = (theme, dataset, varkey)
    if key in VDEF:
        return VDEF[key]
    return "UNDEFINED (%s) [?]" % (key,)


