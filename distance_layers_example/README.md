# CHECO26 distance layers

A minimal, runnable example of how features are converted into distance
surfaces for the raster modelling stack.

The example follows the SMOD feature selection in
`pipeline_r/scripts/09_derive_dist.R` (settlement classes 21/22/23/30 -> 1,
everything else 0, projected onto the grid with max resampling) and then calls
the production helpers:

```r
d <- apply_china_mask(dist_from_feature(feat), NA)
```

`dist_from_feature()` lives in `pipeline_r/scripts/01_common.R` and is the same
function `09_derive_dist.R` uses. Classes, grid, resampling method and NoData
all come from `pipeline_r/config.yaml`.

## Method

```
GHS-SMOD settlement classes (30 arc-sec)
  -> classes 21/22/23/30 -> 1, all other classes -> 0, NoData kept
  -> max aggregation onto the CHECO26 grid (any urban source cell marks the cell)
  -> dist_from_feature(feat) with the exact grid Euclidean transform [metres]
  -> clip to the China mask
```

Feature cells carry distance 0; every other cell carries the Euclidean distance
to the nearest feature cell, in metres. Path distance (elevation-aware) is not
used in CHECO26: the 1-km grid is meant as a national modelling base.

The feature mask marks cells equal to 1. The distance kernel treats zero and missing cells as non-features.

## Production tasks (17 delivered `dist` layers)

| Layer | Feature source |
|---|---|
| `dist_grip4_road` | GRIP4 full road network |
| `dist_grip4_majorroad` | GRIP4 Highways + Primary + Secondary roads |
| `dist_osm_trail` | OpenStreetMap paths / footways |
| `dist_smod_urban` | GHS-SMOD built-up cells (classes 21, 22, 23 and 30, epoch 2020) |
| `dist_gsw_water` | JRC Global Surface Water (seasonal + permanent extent) |
| `dist_h90m_stream-dist-proximity` (+ `_min` / `_max`) | Hydrography90m nearest-stream distance |
| `dist_h90m_stream-dist-up-near` (+ `_min` / `_max`) | Hydrography90m nearest upstream stream |
| `dist_h90m_stream-dist-up-farth` (+ `_min` / `_max`) | Hydrography90m farthest upstream stream |
| `dist_h90m_stream-dist-dw-near` (+ `_min` / `_max`) | Hydrography90m nearest downstream stream |

## Run

```bash
Rscript distance_layers_example/distance_layers.R
```

Requires R with `terra`, `yaml`, `Rcpp` and a C++ toolchain. Both files it needs are in this repository:

- input: `data/source_layers/smod/GHS_SMOD_E2020_china_window.tif`
  (GHS-SMOD 2020 cropped to the China window, CC BY 4.0, 3.4 MB)
- reference: `data/sample_layers/reg/dist/smod/urban/reg_dist_smod_urban.tif`
  (the delivered layer)

## What the example checks

| Check | What it verifies |
|---|---|
| D1 | Evaluates the proportion of delivered feature cells recovered and the mean absolute difference in metres against the delivered 2020 raster. |
| D2 | Compares a 41 × 41 window around a single feature against the analytic Euclidean distances. |

## Applying it to your own features

```r
feat <- terra::rasterize(your_vector, GRID()$rast, field = 1, touches = TRUE,
                         background = 0)
d <- apply_china_mask(dist_from_feature(feat), NA)
atomic_write_raster("dist_mine.tif", d, dtype = "float32")
```

The settlement selection is 21, 22, 23 and 30. The shared distance kernel requires Rcpp and a C++ toolchain.
