# CHECO26 distance layers

This directory provides a minimal, runnable example of how linear and areal
features are converted into distance surfaces for the raster SDM stack. It
mirrors the role of `distance_toolbox/` in SWECO25 (Euclidean and path
distance), implemented with the CHECO26 production stack
(`pipeline/scripts/05_derive_dist.py`) instead of ArcGIS ModelBuilder.

## Method

```
feature vector (roads / rivers / water / urban / trails)
  -> rasterize onto the CHECO26 grid (all_touched=True, 1 = feature)
  -> distance_transform_edt(feature == 0) * grid_resolution      [metres]
  -> clip to the China mask
```

Feature cells carry distance 0; every other cell carries the Euclidean
distance to the nearest feature cell. Path distance (elevation-aware) is not
used in CHECO26: the 1-km grid is intended as a national modelling base, and
the production scope is Euclidean distance only.

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

## Running the example

Requires Python with `rasterio`, `numpy`, `scipy`.

Demo mode (no external data needed): the distance from every in-China cell to
the national boundary -- "distance to the coast or border" -- derived from the
China mask shipped in `../data/`:

```console
python distance_layers.py --from-mask --output dist_to_boundary.tif
```

```text
resolution        : 1000 m
target cells      : 10255072 of 19745382
distance range    : [1000.0, 1047408.2] m
output            : dist_to_boundary.tif
```

Production mode: point `--source` at any binary feature raster (1 = feature,
0 = background) on any grid; the output is written on the CHECO26 grid:

```console
python distance_layers.py --source feature.tif --output dist.tif
```
