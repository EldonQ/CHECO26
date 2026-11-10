# CHECO26 distance layers

A minimal, runnable example of how features are converted into distance
surfaces for the raster modelling stack.

The example is **not** a re-implementation. It reproduces the SMOD step of
`pipeline_r/scripts/09_derive_dist.R` (settlement classes 21/22/23 -> 1,
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
  -> classes 21/22/23 -> 1, all other classes -> 0, NoData kept
  -> max aggregation onto the CHECO26 grid (any urban source cell marks the cell)
  -> terra::distance(ifel(feat == 1, 1, NA), unit = "m")     [metres]
  -> clip to the China mask
```

Feature cells carry distance 0; every other cell carries the Euclidean distance
to the nearest feature cell, in metres. Path distance (elevation-aware) is not
used in CHECO26: the 1-km grid is meant as a national modelling base.

`terra::distance()` measures to the nearest **non-NA** cell, so non-feature cells
must be set to NA rather than 0. Passing a 0/1 raster without NA produces a
meaningless surface (in a minimal test the centre cell came out as 1000 m and
everything else as 0).

## Production tasks (17 delivered `dist` layers)

| Layer | Feature source |
|---|---|
| `dist_grip4_road` | GRIP4 full road network |
| `dist_grip4_majorroad` | GRIP4 Highways + Primary + Secondary roads |
| `dist_osm_trail` | OpenStreetMap paths / footways |
| `dist_smod_urban` | GHS-SMOD built-up cells (classes 21-23, epoch 2020) |
| `dist_gsw_water` | JRC Global Surface Water (seasonal + permanent extent) |
| `dist_h90m_stream-dist-proximity` (+ `_min` / `_max`) | Hydrography90m nearest-stream distance |
| `dist_h90m_stream-dist-up-near` (+ `_min` / `_max`) | Hydrography90m nearest upstream stream |
| `dist_h90m_stream-dist-up-farth` (+ `_min` / `_max`) | Hydrography90m farthest upstream stream |
| `dist_h90m_stream-dist-dw-near` (+ `_min` / `_max`) | Hydrography90m nearest downstream stream |

## Run

```bash
Rscript distance_layers_example/distance_layers.R
```

Requires R with `terra` and `yaml`. Both files it needs are in this repository:

- input: `data/source_layers/smod/GHS_SMOD_E2020_china_window.tif`
  (GHS-SMOD 2020 cropped to the China window, CC BY 4.0, 3.4 MB)
- reference: `data/sample_layers/reg/dist/smod/urban/reg_dist_smod_urban.tif`
  (the delivered layer)

## What the example checks

| Check | What it verifies |
|---|---|
| D1 | 100.00% of the delivered zero-distance cells are reproduced; mean absolute distance difference 0 m over 9,490,310 cells (the largest distance is 390 km) — an exact reproduction |
| D2 | a single feature cell at the grid centre yields exactly `1000 * hypot(dx, dy)` over a 41 × 41 window (max error 0.0017 m, i.e. float32 rounding) |

D2 is the strict check: it verifies the geometry of the distance transform
against closed-form values, independent of any delivered layer.

## Why D1 is now exact

Earlier versions of this example disagreed with the delivered layer on about 2%
of the settlement cells (mean 69 m). The cause was not the example: the
production layer had been built from the **2030** GHS-SMOD epoch, while its
documentation and this example use **2020**. The production layer has since been
rebuilt from the 2020 epoch, so the two now agree pixel for pixel.

## Applying it to your own features

```r
feat <- terra::rasterize(your_vector, GRID()$rast, field = 1, touches = TRUE,
                         background = 0)
d <- apply_china_mask(dist_from_feature(feat), NA)
atomic_write_raster("dist_mine.tif", d, dtype = "float32")
```
