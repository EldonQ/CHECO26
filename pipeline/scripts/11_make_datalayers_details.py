#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the public layer manifest ``CHECO26_datalayers_details.csv``.

The manifest uses the same 14-column, semicolon-separated layout as
``SWECO25_datalayers_details.csv``, so that
both databases can be inventoried with the same tooling:

    category;dataset;variable;period;scenario;sub_period;start_year;end_year;
    attribute;focal;variable_long;unit;path;valid

Input is the fact-driven per-layer dictionary produced by ``09_make_docs.py``
(``00_docs/variable_dictionary.csv``), one row per delivered layer.

Usage:
    python 11_make_datalayers_details.py \
        --input  ../../00_docs/variable_dictionary.csv \
        --output ../data/CHECO26_datalayers_details.csv
"""
import argparse
import csv
import os
import re
import sys

# ---------------------------------------------------------------------------
# Controlled vocabularies (English long names for the public manifest)
# ---------------------------------------------------------------------------

BIO_LONG = {
    "bio01": "Annual mean temperature",
    "bio02": "Mean diurnal range (mean of monthly max-min temperature)",
    "bio03": "Isothermality (bio02 / bio07 x 100)",
    "bio04": "Temperature seasonality (standard deviation x 100)",
    "bio05": "Max temperature of warmest month",
    "bio06": "Min temperature of coldest month",
    "bio07": "Temperature annual range (bio05 - bio06)",
    "bio08": "Mean temperature of wettest quarter",
    "bio09": "Mean temperature of driest quarter",
    "bio10": "Mean temperature of warmest quarter",
    "bio11": "Mean temperature of coldest quarter",
    "bio12": "Annual precipitation",
    "bio13": "Precipitation of wettest month",
    "bio14": "Precipitation of driest month",
    "bio15": "Precipitation seasonality (coefficient of variation)",
    "bio16": "Precipitation of wettest quarter",
    "bio17": "Precipitation of driest quarter",
    "bio18": "Precipitation of warmest quarter",
    "bio19": "Precipitation of coldest quarter",
    "bio20": "Bioclimatic variable bio20",
    "bio21": "Bioclimatic variable bio21",
    "bio22": "Bioclimatic variable bio22",
    "bio23": "Bioclimatic variable bio23",
    "prec": "Precipitation",
    "sunp": "Sunshine duration",
    "tave": "Mean temperature",
    "tmax": "Max temperature",
    "tmin": "Min temperature",
}

SOIL_LONG = {
    "ph": "Soil pH",
    "oc": "Soil organic carbon",
    "tn": "Soil total nitrogen",
    "tp": "Soil total phosphorus",
    "tk": "Soil total potassium",
    "ak": "Soil available potassium",
    "an": "Soil alkali-hydrolyzable nitrogen",
    "ap": "Soil available phosphorus",
    "bd": "Soil bulk density",
    "cec": "Soil cation exchange capacity",
    "clay": "Soil clay content",
    "silt": "Soil silt content",
    "sand": "Soil sand content",
    "gravel": "Soil gravel content",
    "porosity": "Soil porosity",
    "socd": "Soil organic carbon density",
    "dry-r": "Soil colour, red component (dry)",
    "dry-g": "Soil colour, green component (dry)",
    "dry-b": "Soil colour, blue component (dry)",
    "dry-hue": "Soil colour, Munsell hue (dry)",
    "dry-value": "Soil colour, Munsell value (dry)",
    "dry-chroma": "Soil colour, Munsell chroma (dry)",
    "wet-r": "Soil colour, red component (wet)",
    "wet-g": "Soil colour, green component (wet)",
    "wet-b": "Soil colour, blue component (wet)",
    "wet-hue": "Soil colour, Munsell hue (wet)",
    "wet-value": "Soil colour, Munsell value (wet)",
    "wet-chroma": "Soil colour, Munsell chroma (wet)",
}

DEPTH_LABEL = {
    "0": "0-5 cm",
    "5": "5-15 cm",
    "15": "15-30 cm",
    "30": "30-60 cm",
    "60": "60-100 cm",
    "100": "100-200 cm",
}

TOPO_LONG = {
    "elev": "Elevation",
    "slope": "Slope",
    "aspect": "Aspect",
    "tri": "Terrain ruggedness index",
}

VEGE_LONG = {
    "agb": "Forest aboveground biomass",
    "ch": "Forest canopy height",
    "treecover": "Tree canopy cover",
    "ndvimax": "Annual maximum NDVI",
}

ANTHRO_LONG = {
    "hii": "Human Footprint Index",
    "pop": "Population count",
    "urbanprop": "Built-up area proportion",
}

HYDRO_LONG = {
    "spi": "Stream power index",
    "sti": "Sediment transport index",
    "channel-curv-cel": "Channel curvature (cell)",
    "channel-dist-dw-seg": "Distance to downstream channel (segment)",
    "channel-dist-up-cel": "Distance to upstream channel (cell)",
    "channel-dist-up-seg": "Distance to upstream channel (segment)",
    "channel-elv-dw-cel": "Downstream channel elevation (cell)",
    "channel-elv-dw-seg": "Downstream channel elevation (segment)",
    "channel-elv-up-cel": "Upstream channel elevation (cell)",
    "channel-elv-up-seg": "Upstream channel elevation (segment)",
    "channel-grad-dw-seg": "Downstream channel gradient (segment)",
    "channel-grad-up-cel": "Upstream channel gradient (cell)",
    "channel-grad-up-seg": "Upstream channel gradient (segment)",
    "outlet-diff-dw-basin": "Elevation difference to basin outlet",
    "outlet-diff-dw-scatch": "Elevation difference to sub-catchment outlet",
    "outlet-dist-dw-basin": "Distance to basin outlet",
    "outlet-dist-dw-scatch": "Distance to sub-catchment outlet",
    "slope-elv-dw-cel": "Downstream slope elevation (cell)",
    "slope-grad-dw-cel": "Downstream slope gradient (cell)",
    "stream-diff-dw-near": "Elevation difference to nearest downstream stream",
    "stream-diff-up-farth": "Elevation difference to farthest upstream stream",
    "stream-diff-up-near": "Elevation difference to nearest upstream stream",
    "stream-dist-dw-near": "Distance to nearest downstream stream",
    "stream-dist-proximity": "Distance to nearest stream (proximity)",
    "stream-dist-up-farth": "Distance to farthest upstream stream",
    "stream-dist-up-near": "Distance to nearest upstream stream",
    "order-hack": "Stream order (Hack)",
    "order-horton": "Stream order (Horton)",
    "order-shreve": "Stream order (Shreve)",
    "order-strahler": "Stream order (Strahler)",
    "order-topo": "Stream order (topological)",
    "basin": "Basin identifier (network index, not a continuous predictor)",
    "direction": "Flow direction (network index, not a continuous predictor)",
    "segment": "River segment identifier (network index, not a continuous predictor)",
    "sub-catchment": "Sub-catchment identifier (network index, not a continuous predictor)",
    "outlet": "Outlet marker (sparse network index, not a continuous predictor)",
}

DIST_LONG = {
    "road": "Distance to roads",
    "majorroad": "Distance to major roads",
    "trail": "Distance to trails",
    "water": "Distance to surface water",
    "urban": "Distance to urban areas",
    "stream-dist-proximity": "Distance to nearest stream (proximity)",
    "stream-dist-dw-near": "Distance to nearest downstream stream",
    "stream-dist-up-near": "Distance to nearest upstream stream",
    "stream-dist-up-farth": "Distance to farthest upstream stream",
}

LULC_CLASS_LONG = {
    "cropland": "Cropland",
    "forest": "Forest",
    "grassland": "Grassland",
    "urban": "Urban",
    "barren": "Barren",
    "water": "Water",
}

LULC_METRIC_LONG = {
    "shannon": "Landscape Shannon diversity",
    "edge": "Landscape edge density",
    "patchdensity": "Landscape patch density",
    "patchsize": "Mean patch size",
}

DATASET_LONG = {
    "cnclim1km": "CNClim1km China climate",
    "cnclim1km-ensmean": "CNClim1km ensemble-mean future climate",
    "cnclim1km-bcc-csm2-mr": "CNClim1km BCC-CSM2-MR future climate",
    "csdlv2": "CSDLv2 China soil database",
    "chinadem": "China DEM 1 km",
    "agb2019": "Forest aboveground biomass 2019",
    "ch2019": "Forest canopy height 2019",
    "catcd": "CATCD 2025 tree canopy cover",
    "glassndvi": "GLASS NDVI",
    "h90m": "Hydrography90m",
    "glu1km": "Global LULC projection 1 km",
    "foothii": "WCS footHII human footprint",
    "landscan": "LandScan population",
    "smod": "GHS-SMOD built-up areas",
    "grip4": "GRIP4 roads",
    "gsw": "JRC Global Surface Water",
    "osm": "OpenStreetMap trails",
}

UNIT_EN = {
    "指数(0-59)": "index (0-59)",
    "人/像元": "people per cell",
    "比例(0-1)": "proportion (0-1)",
    "degC": "degC",
    "(-)": "(-)",
    "mm": "mm",
    "%": "%",
    "m": "m",
    "类别编码": "class code",
    "个/100km2": "patches per 100 km2",
    "km2": "km2",
    "mg/kg": "mg/kg",
    "g/cm3": "g/cm3",
    "me/100g": "me/100g",
    "RGB B(编码)": "RGB B (code)",
    "RGB G(编码)": "RGB G (code)",
    "RGB R(编码)": "RGB R (code)",
    "Munsell chroma(编码)": "Munsell chroma (code)",
    "Munsell hue(编码)": "Munsell hue (code)",
    "Munsell value(编码)": "Munsell value (code)",
    "g/100g": "g/100g",
    "pH(-)": "pH (-)",
    "kg C/m2": "kg C/m2",
    "deg(0-360,北=0顺时针)": "deg (0-360, north=0, clockwise)",
    "deg": "deg",
    "Mg/ha": "Mg/ha",
    "NDVI(-)": "NDVI (-)",
}

# Future climate centre year -> source sub-period folder and year range
CLIMATE_PERIOD = {
    "2030": ("2021_2040", 2021, 2040),
    "2055": ("2041_2070", 2041, 2070),
    "2085": ("2071_2100", 2071, 2100),
}

BIOCLIM_PRESENT = ("1991_2020", 1991, 2020)

NA = "NA"

HEADER = ["category", "dataset", "variable", "period", "scenario", "sub_period",
          "start_year", "end_year", "attribute", "focal", "variable_long",
          "unit", "path", "valid"]


def split_suffix(suffix):
    """Split a dictionary suffix into (derivation, focal_m).

    ``_prop_f5000`` -> ("prop", 5000); ``_patchdensity-all_f1000`` ->
    ("patchdensity-all", 1000); ``-`` -> ("", None); ``_min`` -> ("min", None).
    """
    s = suffix.strip()
    if s in ("", "-"):
        return "", None
    m = re.search(r"_f(\d+)$", s)
    focal = int(m.group(1)) if m else None
    base = s[:m.start()] if m else s
    base = base.lstrip("_")
    return base, focal


def variable_long(theme, variable, derivation, attribute, dataset):
    """English long name for the manifest."""
    if theme == "bioclim":
        return BIO_LONG.get(variable, variable)
    if theme == "soil":
        base = SOIL_LONG.get(variable, variable)
        if attribute in DEPTH_LABEL:
            return "%s (%s)" % (base, DEPTH_LABEL[attribute])
        if attribute == "profile":
            return "%s (whole-profile aggregate)" % base
        return base
    if theme == "topo":
        return TOPO_LONG.get(variable, variable)
    if theme == "vege":
        return VEGE_LONG.get(variable, variable)
    if theme == "anthro":
        return ANTHRO_LONG.get(variable, variable)
    if theme == "hydro":
        return HYDRO_LONG.get(variable, variable)
    if theme == "dist":
        return DIST_LONG.get(variable, variable)
    if theme == "lulc":
        if derivation == "prop":
            return "%s proportion" % LULC_CLASS_LONG.get(variable, variable)
        if variable in LULC_METRIC_LONG:
            return LULC_METRIC_LONG[variable]
        return variable
    return variable


def parse_row(row):
    """One dictionary row -> one manifest row (dict)."""
    rel = row["relpath"].replace("\\", "/")
    parts = rel.split("/")
    theme = parts[1]
    derivation, focal = split_suffix(row.get("suffix", "-"))
    unit = UNIT_EN.get(row["unit"], row["unit"])

    category = theme
    dataset = NA
    variable = NA
    period = NA
    scenario = NA
    sub_period = NA
    start_year = NA
    end_year = NA
    attribute = NA

    if theme == "bioclim":
        dataset = parts[2]
        if parts[3] == "present":
            variable = parts[4]
            period = "present"
            sub_period, start_year, end_year = BIOCLIM_PRESENT
        elif parts[3] == "scenario":
            year, ssp = parts[4], parts[5]
            variable = parts[6]
            period = "future"
            scenario = ssp
            sub_period = year  # delivery folder = centre year; source range below
            start_year, end_year = CLIMATE_PERIOD[year][1], CLIMATE_PERIOD[year][2]
        else:
            raise ValueError("unexpected bioclim path: %s" % rel)
    elif theme == "soil":
        dataset = "csdlv2"
        variable = parts[3]
        period = "present"
        if len(parts) > 5:  # depth-specific layer
            attribute = parts[4]
        elif derivation == "profile":
            attribute = "profile"
    elif theme == "topo":
        dataset = "chinadem"
        variable = parts[3]
        period = "present"
    elif theme == "vege":
        dataset = parts[2]
        variable = parts[-2]  # folder directly above the file (agb / ch / treecover / ndvimax)
        period = "present"
    elif theme == "hydro":
        dataset = "h90m"
        variable = parts[3]
        period = "present"
    elif theme == "dist":
        dataset = parts[2]
        variable = parts[3]
        period = "present"
    elif theme == "anthro":
        dataset = parts[2]
        year = parts[3]
        variable = parts[4]
        period = "present"
        sub_period = year
        start_year = end_year = year
    elif theme == "lulc":
        dataset = "glu1km"
        if parts[3] == "scenario":
            year, ssp = parts[4], parts[5]
            rest = parts[6:]
            period = "future"
            scenario = ssp
            sub_period = year
            start_year = end_year = year
        else:
            year = parts[3]
            rest = parts[4:]
            period = "present"
            sub_period = year
            start_year = end_year = year
        if rest and not rest[0].endswith(".tif"):
            variable = rest[0]           # class-specific proportion layer
            attribute = "prop"
        else:
            # whole-landscape metric: shannon / edge / patchdensity / patchsize
            head = derivation.split("-")[0]
            variable = head
            if head in ("patchdensity", "patchsize"):
                attribute = derivation.split("-")[1]
    else:
        raise ValueError("unexpected theme: %s" % rel)

    # window statistics for aggregated hydro / distance layers
    if derivation in ("min", "max"):
        attribute = derivation

    return {
        "category": category,
        "dataset": dataset,
        "variable": variable,
        "period": period,
        "scenario": scenario,
        "sub_period": str(sub_period),
        "start_year": str(start_year),
        "end_year": str(end_year),
        "attribute": str(attribute),
        "focal": str(focal) if focal is not None else NA,
        "variable_long": variable_long(theme, variable, derivation, attribute, dataset),
        "unit": unit,
        "path": "./" + rel,
        "valid": "yes",
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", required=True, help="variable_dictionary.csv")
    ap.add_argument("--output", required=True, help="CHECO26_datalayers_details.csv")
    args = ap.parse_args()

    with open(args.input, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        sys.exit("no rows in %s" % args.input)

    manifest = [parse_row(r) for r in rows]
    manifest.sort(key=lambda r: r["path"])

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    # utf-8-sig keeps Excel happy with the semicolon-separated layout
    with open(args.output, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=HEADER, delimiter=";", lineterminator="\n")
        w.writeheader()
        w.writerows(manifest)

    # fact-driven sanity summary
    import collections
    by_cat = collections.Counter(r["category"] for r in manifest)
    print("manifest rows: %d" % len(manifest))
    for cat, n in sorted(by_cat.items()):
        print("  %-8s %4d" % (cat, n))
    bad = [r for r in manifest if r["variable"] == NA]
    if bad:
        sys.exit("ERROR: %d rows without variable" % len(bad))
    print("written: %s" % args.output)


if __name__ == "__main__":
    main()
