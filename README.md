# CHECO26

<a href="LICENSE"><img src="https://img.shields.io/badge/licence-CC%20BY%204.0-79C83D.svg" alt="Licence"></a>
<a href="data/CHECO26_datalayers_details.csv"><img src="https://img.shields.io/badge/layers-21%2C110-4E79A7.svg" alt="Layers"></a>
<a href="database_validation/DATA_QUALITY_AUDIT.md"><img src="https://img.shields.io/badge/audited-21%2C110%20%2F%2021%2C110-brightgreen.svg" alt="Audited"></a>
<a href="database_validation/"><img src="https://img.shields.io/badge/FAIR-black.svg" alt="FAIR"></a>

CHECO26 is a China-wide raster database at 1-kilometre resolution for ecological research in China, gathering **21,110 layers** in **21 dataset entries** drawn from **19 distinct source products** across **eight environmental categories**. (GHS-SMOD and Hydrography90m each enter under two categories, so the entry count exceeds the product count.) CHECO26 layers were standardized to a common spatial grid covering all of China, so they all share the same spatial resolution, extent, and geographic coordinate system. CHECO26 includes both the standardized source data and newly calculated layers, such as those obtained by computing focal statistics, distance surfaces, and discrete-to-continuous landscape derivations. The database is designed as a ready-to-use environmental covariate base for species distribution modelling and other cross-thematic ecological applications.

The [detailed list](https://github.com/EldonQ/CHECO26/blob/main/data/CHECO26_datalayers_details.csv) of every layer present in CHECO26 is available in this repository — one semicolon-separated row per delivered layer, with category, dataset, variable, period, scenario, year range, focal radius, physical unit and path. The database is described in a data manuscript currently in preparation.

<p align="center">
  <img src="https://github.com/EldonQ/CHECO26/blob/main/figs/china_overview.png" width="800" />
</p>

## Spatial characteristics
<img src="https://github.com/EldonQ/CHECO26/blob/main/figs/china_boundary.png" data-canonical-src="https://github.com/EldonQ/CHECO26/blob/main/figs/china_boundary.png" width="500"  />

| Parameter  | Value |
| ------------- | ------------- |
| GCS                         | China_Albers (WGS84, standard parallels 25N / 47N, central meridian 105E) |
| Extent                      | -2648000, 1867000, 2213000, 5929000 |
| Grid                        | [CHECO26 standard grid](https://github.com/EldonQ/CHECO26/blob/main/data/CHECO26-standardgrid.tif) |
| Spatial resolution (meters) | 1000, 1000  (x, y) |
| Grid size                   | 4861 columns x 4062 rows |
| Valid cells (China mask)    | 9,490,310 of 19,745,382 (48.1%) |
| Mask                        | [mask_china.tif](https://github.com/EldonQ/CHECO26/blob/main/data/mask_china.tif), `china.shp` rasterized `all_touched=True` (islands and coastlines kept) |
| Data type                   | float32, every layer without exception |
| NoData                      | -9999, every layer |
| Storage                     | GeoTIFF, DEFLATE compressed, 256 x 256 tiles |
| Volume                      | 169.4 GB (157.8 GiB) |

## Layer inventory

| Category | Layers | Content |
|---|---:|---|
| lulc | 20,150 | Three complementary products: **clcd** annual observed cover 2000–2025 (1,170 = 26 years x 9 classes x 5 scales) · **glu1km** China-relevant projection 2020 + 2030/2050/2100 under three SSPs (540) · **hlu1km** harmonised yearly reconstruction 1960–2020 plus 2021–2100 under five SSP-RCPs (18,440) |
| bioclim | 532 | **cnclim1km** 28 present layers (1991–2020) plus two future chains — a 10-model CMIP6 ensemble mean and BCC-CSM2-MR — at 2030/2055/2085 under three SSPs (252 + 252) |
| soil | 196 | **csdlv2** 28 attributes x (six standard depths + one whole-profile aggregate) |
| anthro | 137 | **hfp** annual Human Footprint 2000–2024 x 5 scales (125) · **smod** built-up proportion 1975–2030 x 12 epochs (12) |
| hydro | 44 | **h90m** 39 continuous Hydrography90m layers · **hydrosheds** 5 flow-accumulation layers |
| vege | 30 | forest aboveground biomass (**agb2019**), forest canopy height (**ch2019**), tree canopy cover (**catcd**), GLASS NDVI 2020–2022 (**glassndvi**), each with focal windows |
| dist | 17 | distance to roads and major roads (**grip4**), trails (**osm**), urban areas (**smod**), surface water (**gsw**), and four stream-distance surfaces (**h90m**) |
| topo | 4 | elevation, slope, aspect, terrain ruggedness index (**chinadem**) |
| **Total** | **21,110** | **21 dataset entries from 19 source products** |

Of the 21,110 layers, 4,824 are delivered at the native 1-km resolution and 16,286 are focal variants — 4,064 at 1 km and 4,074 at each of 5, 10 and 20 km. 3,982 of the native-resolution layers are class proportions; the remaining 842 are source layers plus 18 multi-source extrema. 16,990 layers describe a future scenario and 4,120 describe the present. Every one of these counts is reproducible from the manifest's `focal`, `attribute` and `period` columns.

<p align="center">
  <img src="https://github.com/EldonQ/CHECO26/blob/main/database_validation/figures/layers_per_theme.png" width="520" />
</p>

## Layer processing

Individual layers from the selected source products were processed following a
fixed, variable-type-driven standardization procedure:

1. rasterization of vector layers (roads, trails, water bodies, urban areas, stream networks)
2. reprojection to the China_Albers equal-area geographic reference system
3. resampling to the common 1-km grid — `bilinear` for continuous, proportion and distance layers; `nearest` for categorical layers; `average` / `mode` window aggregation when downscaling fine-resolution sources (30 m / 90 m)
4. transformation of discrete data to continuous ones — land-cover classes become class proportions, edge density, Shannon diversity, and patch density / mean patch size over square windows
5. computation of distance statistics for linear and areal features (Euclidean distance, metres)
6. computation of focal statistics — equal-weight means over four square windows (3 x 3 to 41 x 41 cells, i.e. 1, 5, 10 and 20 km radii); a window containing no valid cell receives NoData rather than zero
7. unification of the five NoData conventions found in the sources (0, 255, 65535, -9999, NaN) to -9999, setting class-0 source pixels to NoData before aggregation where 0 doubles as both a class value and the background
8. clipping to the national boundary with an `all_touched` mask (no delivered layer holds valid cells outside China)
9. saving the final raster layers as float32 GeoTIFF (DEFLATE, 256 x 256 tiled, atomic write)

For the standardization rules, the focal-window semantics and the distance-surface
method, see the worked examples in
[`layer_standardization_example/`](layer_standardization_example/),
[`focal_statistics_example/`](focal_statistics_example/) and
[`distance_layers_example/`](distance_layers_example/). The complete production
pipeline is in [`pipeline_r/`](pipeline_r/).

## Data availability

The CHECO26 v2.0 database (169.4 GB, 21,110 float32 GeoTIFF layers on the
China_Albers 1-km grid) is described in a data manuscript currently in preparation
and is not yet publicly released. This repository provides everything needed to
understand, audit and reproduce the database:

- the full layer manifest ([`data/CHECO26_datalayers_details.csv`](data/CHECO26_datalayers_details.csv), one row per layer with category, dataset, variable, period, scenario, year range, focal radius, unit and path),
- the standard grid and China mask,
- six representative sample layers under [`data/sample_layers/`](data/sample_layers/),
- the production pipeline ([`pipeline_r/`](pipeline_r/)) and its configuration,
- the validation code, result dataframes and figures ([`database_validation/`](database_validation/)).

## Data validation

The v2.0 delivery was checked along four independent lines, each answering a
different question. Tables and code are in [`database_validation/`](database_validation/).

**Full-archive audit — exhaustive, every pixel, second toolchain.** 21,110 / 21,110
layers pass ten checks: opens with one band, float32, NoData −9999, grid invariants
(CRS, transform, 4,861 x 4,062), DEFLATE with 256 x 256 tiles, no valid cell outside
the China mask, no Inf/NaN among valid cells, values inside the documented range,
agreement with `variable_dictionary.csv`, and agreement with the `MANIFEST.csv`
SHA-256. **Zero layers failed.** The audit ran on Python + rasterio, while the
production validator is R + terra, so the result is not a property of one
implementation. Report: [`DATA_QUALITY_AUDIT.md`](database_validation/DATA_QUALITY_AUDIT.md).

**Composition identities — exhaustive.** All **497** base proportion groups (3,982
layers) sum to 1: max |Σ − 1| is 5.215 x 10⁻⁸ for clcd, 4.843 x 10⁻⁸ for hlu1km, and
exactly 0 for the product built on integer percentages. Focal maxima fall
monotonically with window size (1.0000 → 1.0000 → 0.9989 → 0.9947 → 0.9836).

**Source fidelity — sampled cells.** Five cross-theme layers were compared point by
point with their original sources at 3,000 random cells: r = 0.983–0.9999, mean
bias ≈ 0.

**Independent recomputation.** A second implementation sharing no code with the
pipeline re-derives 16 properties from the delivered files, including a full rerun
of the composition identity on the 2008 reference year, and reports no failure.

Resampling was quantified per theme: the 1-km product reproduces the area-weighted
source mean with a median relative difference of 0.00% for canopy height, 2.40% for
distance to rivers and 7.75% for flow accumulation, while the within-cell
coefficient of variation of the sources is 77–277% — the 1-km value is an average
over a heterogeneous neighbourhood, not a statement about every point inside it.

Counting distinct SHA-256 digests, 14,047 of the 21,110 layers are byte-distinct
(66.5%); the redundancy is confined to the projected land-use family, where the
projected urban extent is frozen across scenarios.

See [`database_validation/README.md`](database_validation/README.md) for the
evidence chain and the list of known source-level limitations, including the eight
Hydrography90m layers withdrawn after the source products proved numerically
unusable.

## Repository layout

| Directory | Content |
|---|---|
| [`data/`](data/) | layer manifest, standard grid, China mask, sample layers |
| [`pipeline_r/`](pipeline_r/) | **v2.0 production pipeline (R)** — 20 stage scripts, 19 tools, 70 tests, configuration |
| [`database_validation/`](database_validation/) | validation code, result dataframes, figures, verification reports, and the [layer-by-layer data quality audit](database_validation/DATA_QUALITY_AUDIT.md) |
| [`layer_standardization_example/`](layer_standardization_example/) | minimal standardization worked example |
| [`focal_statistics_example/`](focal_statistics_example/) | focal-window worked example |
| [`distance_layers_example/`](distance_layers_example/) | distance-surface worked example |
| [`figs/`](figs/) | README figures |

The delivered rasters are not in this repository: 169.4 GB cannot live in git.
What ships here is the layer manifest, the grid definition, the pipeline that
produced the layers, and the validation evidence — enough to understand, audit
and reproduce the database without holding a copy of it.

## Citation

A data manuscript describing CHECO26 is in preparation. Until it is available,
please cite the database through this repository:

CHECO26: A China-wide cross-thematic raster database at 1-km resolution for ecological research. https://github.com/EldonQ/CHECO26
