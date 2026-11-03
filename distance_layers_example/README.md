# CHECO26 distance layers

A minimal, runnable example of how features are converted into distance
surfaces for the raster modelling stack.

The example is **not** a re-implementation. It calls `dist_from_feature()` from
`pipeline_r/scripts/01_common.R` — the same helper used by
`pipeline_r/scripts/09_derive_dist.R` — and the production writer:

```r
d <- dist_from_feature(feat)    # flag features as 1, everything else as 0/NA
d <- apply_china_mask(d, NA)    # distance is computed on the full grid, then clipped
```

## Method

```
feature vector (roads / rivers / water / urban / trails)
  -> rasterize onto the CHECO26 grid (all_touched = TRUE, 1 = feature)
  -> terra::distance(ifel(feat == 1, 1, NA), unit = "m")     [metres]
  -> clip to the China mask
```

Feature cells carry distance 0; every other cell carries the Euclidean distance
to the nearest feature cell. Distance is computed on the **full** grid — features
outside China still provide context at the border — and only clipped on write.
Path distance (elevation-aware) is not used in CHECO26: the 1-km grid is meant
as a national modelling base, and the production scope is Euclidean distance.

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

Requires R with `terra` and `yaml`. The demo uses only files in this repository:
the China mask (`data/mask_china.tif`) and the delivered road distance layer
(`data/sample_layers/glo/dist/grip4/road/`). The demo feature is "everything
outside China", so the result is the distance from every interior cell to the
national border.

## What the example checks

| Check | What it verifies |
|---|---|
| D1 | the first interior ring sits exactly 1,000 m from the border (100% of its cells); maximum distance 1,047 km |
| D2 | a single feature cell at the grid centre yields exactly `1000 * hypot(dx, dy)` over a 41 × 41 window (max error 0.002 m, i.e. float32 rounding) |
| D3 | descriptive statistics of the delivered road layer, as a sanity check on the surface being reproduced |

D2 is the strict one: it verifies the geometry of the distance transform against
closed-form values, independent of any delivered layer.

## Applying it to your own features

```r
feat <- terra::rasterize(your_vector, GRID()$rast, field = 1, touches = TRUE,
                         background = 0)
d <- apply_china_mask(dist_from_feature(feat), NA)
atomic_write_raster("dist_mine.tif", d, dtype = "float32")
```
