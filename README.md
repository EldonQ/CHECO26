## CHECO26 <a href="https://"><img src="https://img.shields.io/static/v1?label=&message=Open+Access&color=#79C83D" alt="Open Access"></a> <a href="https://"><img src="https://img.shields.io/static/v1?label=&message=FAIR&color=black" alt="FAIR"></a> <a href="https://"><img src="https://img.shields.io/static/v1?label=&message=1%2C595+layers&color=#4E79A7" alt="Layers"></a>



CHECO26 is a China-wide raster database at 1-kilometre resolution for ecological research in China, gathering 1,595 layers from 8 main environmental categories. CHECO26 layers were standardized to a common spatial grid covering all of China, so they all share the same spatial resolution, extent, and geographic coordinate system. CHECO26 includes both the standardized source data and newly calculated layers, such as those obtained by computing focal statistics, distance surfaces, and discrete-to-continuous landscape derivations. The database is designed as the environmental covariate base for species distribution modelling with [N-SDM 2.0](https://doi.org/10.1002/ecog.08547).

The [detailed list](https://github.com/EldonQ/CHECO26/blob/main/data/CHECO26_datalayers_details.csv) of every layer present in CHECO26 is available in this repository. The database is described in a data manuscript currently in preparation.

<p align="center">
  <img src="https://github.com/EldonQ/CHECO26/blob/main/figs/china_overview.png" width="800" />
</p>

## Spatial characteristics

| Parameter  | Value |
| ------------- | ------------- |
| GCS                         | China_Albers (WGS84, standard parallels 25N / 47N, central meridian 105E) |
| Extent                      | -2648000, 1867000, 2213000, 5929000 |
| Grid                        | [CHECO26 standard grid](https://github.com/EldonQ/CHECO26/blob/main/data/CHECO26-standardgrid.tif) |
| Spatial resolution (meters) | 1000, 1000  (x, y) |
| Grid size                   | 4861 columns x 4062 rows |
| Valid cells (China mask)    | 9,490,310 (1 cell = 1 km²) |
| Mask                        | [mask_china.tif](https://github.com/EldonQ/CHECO26/blob/main/data/mask_china.tif), `china.shp` rasterized `all_touched=True` (islands and coastlines kept) |

## Layer inventory

| Category | Layers | Content |
|---|---:|---|
| bioclim | 532 | 28 present layers (1991–2020) + 504 future layers (2 climate chains x 3 SSPs x 3 periods x 28 variables) |
| lulc | 540 | 10 land-cover snapshots x 54 continuous derivations (class proportions, Shannon diversity, edge density, patch density / mean patch size x 4 window scales) |
| anthro | 237 | LandScan population (25 years), WCS footHII (20 years), GHS-SMOD built-up proportion (12 epochs), each with focal windows |
| soil | 196 | CSDLv2, 28 attributes x (6 depth layers + 1 whole-profile aggregate) |
| hydro | 39 | Hydrography90m continuous layers (stream power / transport indices, channel geometry, stream and outlet distances) plus selected window statistics |
| vege | 30 | forest aboveground biomass, canopy height, tree canopy cover, GLASS NDVI (3 years), each with focal windows |
| dist | 17 | distance to roads, major roads, trails, urban areas, surface water, and streams |
| topo | 4 | elevation, slope, aspect, terrain ruggedness index |
| **Total** | **1,595** | |

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
6. computation of focal statistics — equal-weight means over four square windows (3 x 3 to 41 x 41 cells, i.e. 3 km to 41 km across)
7. scaling to documented physical units (e.g. CSDLv2 storage values, footHII index, canopy height)
8. clipping to the national boundary (no delivered layer holds cells outside China)
9. saving the final raster layers as GeoTIFF files (DEFLATE, tiled)

For the standardization rules, the focal-window semantics and the distance-surface
method, see the worked examples in
[`layer_standardization_example/`](layer_standardization_example/),
[`focal_statistics_example/`](focal_statistics_example/) and
[`distance_layers_example/`](distance_layers_example/). The complete production
pipeline is in [`pipeline/`](pipeline/).

## Data availability

The CHECO26 database (~32 GB, 1,595 GeoTIFF layers on the China_Albers 1-km
grid) is described in a data manuscript currently in preparation and is not yet
publicly released. This repository provides everything needed to understand,
audit and reproduce the database:

- the full layer manifest ([`data/CHECO26_datalayers_details.csv`](data/CHECO26_datalayers_details.csv), one row per layer with category, dataset, variable, period, scenario, focal radius, unit and path),
- the standard grid and China mask,
- six representative sample layers (one per flagship theme) under [`data/sample_layers/`](data/sample_layers/),
- the complete, idempotent production pipeline ([`pipeline/`](pipeline/)),
- the validation code, result dataframes and figures ([`database_validation/`](database_validation/)).

## Data validation

All 1,595 layers passed the full-library acceptance gates: expected = disk =
1,595 layers, zero missing or extra layers, zero alignment failures against the
standard grid, zero layers with cells outside the China mask, and zero naming
errors. Derived layers additionally pass value-range and empty-window gates, and
sampled cell-by-cell comparisons against the source products show match rates of
0.90–1.00 (sub-threshold values are bilinear-reprojection differences at sharp
gradients, documented per layer). Eight Hydrography90m layers were withdrawn
from the delivery after the source products themselves proved numerically
unusable. See [`database_validation/README.md`](database_validation/README.md)
for the complete evidence chain.

## Repository layout

| Directory | Content |
|---|---|
| [`data/`](data/) | layer manifest, standard grid, China mask, sample layers |
| [`pipeline/`](pipeline/) | complete production pipeline (stages 01–11) and configuration |
| [`database_validation/`](database_validation/) | validation code, result dataframes, figures, forensics |
| [`layer_standardization_example/`](layer_standardization_example/) | minimal standardization worked example |
| [`focal_statistics_example/`](focal_statistics_example/) | focal-window worked example |
| [`distance_layers_example/`](distance_layers_example/) | distance-surface worked example |
| [`figs/`](figs/) | README figures |

## Citation

A data manuscript describing CHECO26 is in preparation. Until it is available,
please cite the database through this repository and the method lineage it
follows:

Külling, N., Adde, A., Fopp, F., Schweiger, A. K., Broennimann, O., Rey, P.-L., Giuliani, G., Goicolea, T., Petitpierre, B., Zimmermann, N. E., Pellissier, L., Altermatt, F., Lehmann, A., & Guisan, A. (2024). SWECO25: A cross-thematic raster database for ecological research in Switzerland. Scientific Data, 11(1), Article 1. https://doi.org/10.1038/s41597-023-02899-1

Adde, A., Goicolea, T., Guisan, A., & Altermatt, F. (2026). N-SDM 2.0: a reengineered software with extended features for nested species distribution modelling. Ecography, e08547. https://doi.org/10.1002/ecog.08547
