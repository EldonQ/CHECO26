# CHECO26 layer standardization

A minimal, runnable example of the procedure that turns an arbitrary source
raster into a CHECO26 layer: same grid, same CRS, same extent, same masking,
same file conventions.

The example is **not** a re-implementation. It sources the production scripts
(`pipeline_r/scripts/00_config.R` and `01_common.R`) and calls the function the
archive was built with:

```r
invisible(warp_to_template(
  src        = src_path,                      # any raster
  dst        = dst,
  method     = CFG()$resampling$continuous,   # "bilinear", from config.yaml
  scale      = NULL,
  apply_mask = TRUE,
  dtype      = "float32"))
```

Every parameter comes from `pipeline_r/config.yaml` — grid definition,
resampling rule, NoData value, China mask, output format. Nothing is restated
in the example, so the example cannot drift away from the pipeline.

## The standardization step

```
source raster (any CRS, any resolution)
  -> 1. resampling rule chosen by variable type (config.yaml)
  -> 2. reproject + resample onto the CHECO26 grid
        (China_Albers equal-area, 1000 m, 4861 x 4062)
  -> 3. clip to the China mask (outside -> NoData)
  -> 4. write GeoTIFF (float32, DEFLATE, 256 x 256 tiles, atomic rename)
```

## Fixed rules (`pipeline_r/config.yaml`)

| Parameter | Value |
|---|---|
| CRS | China_Albers (WGS84, standard parallels 25N / 47N, central meridian 105E) |
| Resolution | 1000 m (4861 columns x 4062 rows) |
| Extent | -2648000, 1867000, 2213000, 5929000 |
| Mask | China boundary rasterized `all_touched`, applied to every layer |
| NoData | -9999.0 (float layers), 255 (uint8 categorical layers) |

Resampling is **variable-type driven**:

| Variable type | Rule | Rationale |
|---|---|---|
| continuous (climate, soil, DEM, population, hydro aggregates) | `bilinear` | preserves continuous gradients |
| categorical (LULC class, lithology codes) | `nearest` | never invents classes that do not exist |
| proportion / distance | `bilinear` | derived continuous quantities |
| fine-resolution source (30 m / 90 m) downscaled by a large factor | `average` (continuous) / `mode` (categorical) | aggregate first, then align |

Unit scales (CSDLv2 storage value x 0.01, footHII x 0.01, canopy height dm -> m)
are applied in the same step in production; see `units_scale` in
`pipeline_r/config.yaml`.

## Run

```bash
Rscript layer_standardization_example/standardization_example.R
```

Requires R with `terra` and `yaml`. No download is needed: the input
(`data/source_layers/`, EPSG:4326, 0.01°) and the reference output
(`data/sample_layers/`, the delivered layer) are both in this repository.

## What the example checks

| Check | What it verifies |
|---|---|
| S1 | output is on the CHECO26 grid (4,861 × 4,062 cells, 1,000 m, China_Albers) |
| S2 | no valid cell lies outside the national boundary |
| S3 | the reprojected layer reproduces the delivered one: mean difference 0.015 °C, maximum 0.61 °C at ten coastal cells |

S3 is the point of the example: reprojecting the raw source through the
production function reproduces the layer that ships in the archive.

## Why ten cells differ at the coast

Bilinear interpolation samples the source at each target cell centre; at the
land–sea edge the source carries its own NoData, so a handful of cells cannot
match exactly. The mean difference of 0.015 °C is two orders of magnitude below
the source's own precision.
