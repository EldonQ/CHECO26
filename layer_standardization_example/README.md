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
(`data/source_layers/`, EPSG:4326, 30 arc-sec) and the reference output
(`data/sample_layers/`, the delivered layer) are both in this repository.

## What the example checks

| Check | What it verifies |
|---|---|
| S1 | output CRS, resolution, extent and dimensions all match the CHECO26 grid (each asserted explicitly before PASS) |
| S2 | no valid cell lies outside the national boundary |
| S3 | the reprojected layer reproduces the delivered one within the acceptance thresholds below |

S3 is the point of the example: reprojecting the raw source through the
production function reproduces the layer that ships in the archive.

### S3 acceptance thresholds

S3 fails (non-zero exit) if either bound is exceeded:

| Quantity | Threshold |
|---|---|
| maximum absolute difference | > 10 °C |
| standard deviation of the signed difference | > 0.5 °C |

### Measured result and the versions behind it

Input: `data/source_layers/chelsa21/CHELSA_bio01_1981-2010_V.2.1.tif` — a
pre-clipped CHELSA v2.1 bio01 window (8,160 × 4,920 cells, EPSG:4326, 30 arc-sec,
INT2U, scale 0.1 / offset −273.15), mean annual temperature 1981–2010.

Software: R 4.4.3, terra 1.8.54, GDAL 3.10.1, PROJ 9.5.1, GEOS 3.13.0 (the
production stack; see `../pipeline_r/README.md`). With this input and stack S3
reports:

| Quantity | Value |
|---|---|
| mean absolute difference | 0.224 °C |
| maximum absolute difference | 7.13 °C |
| sd of signed difference | 0.40 °C |
| cells identical to 1e-6 | 10.2 % of 9,490,310 |
| signed mean | ≈ 0 (no systematic offset) |

Both bounds are satisfied (7.13 < 10, 0.40 < 0.5), so S3 passes.

## Why the public input leaves a small residual

The repository ships a **pre-clipped** CHELSA bio01 window to keep the download
small. Its cell edges snap slightly differently from the production crop of the
**full global** CHELSA file (cropped to 70–138 E, 15–56 N with `snap = "out"`
before warping), so bilinear sampling differs at boundary cells and a coastal
residual remains.

This is a property of the public input clip, **not** a software-version artifact:
warping the full global source with the production crop under the same GDAL
3.10.1 reproduces the delivered layer **exactly** (maximum absolute difference 0,
100 % of 9,490,310 cells identical to 1e-6). The signed mean of the example
residual is ≈ 0, confirming there is no systematic offset.
