# CHECO26 layer standardization

This directory provides a minimal, runnable example of the CHECO26
standardization procedure: turning an arbitrary source raster into a layer
that shares the CHECO26 grid, CRS, extent, naming and masking conventions. It
reproduces the steps of the CHECO26 production stack
([`pipeline_r/scripts/02_template.R`](../pipeline_r/scripts/02_template.R) and the
ingest stages), run here through a standalone Python / rasterio demo so the
example needs no R installation.

## The standardization workflow

```
source raster (any CRS, any resolution)
  -> 1. pick the resampling rule from the variable type
  -> 2. reproject + resample onto the CHECO26 grid
       (China_Albers equal-area, 1000 m, 4861 x 4062)
  -> 3. clip to the China mask (boundary cells -> NoData)
  -> 4. write GeoTIFF (DEFLATE, tiled, BIGTIFF=IF_SAFER)
  -> 5. verify alignment against the standard grid
```

## Fixed rules ([`config_example.yaml`](config_example.yaml))

| Parameter | Value |
|---|---|
| CRS | China_Albers (WGS84, standard parallels 25N / 47N, central meridian 105E) |
| Resolution | 1000 m (4861 columns x 4062 rows) |
| Extent | -2648000, 1867000, 2213000, 5929000 |
| Mask | `china.shp` rasterized `all_touched=True`, applied to every layer |
| NoData | -9999.0 (float layers), 255 (uint8 categorical layers) |

The resampling method is **variable-type driven** and fixed in the
configuration:

| Variable type | Rule | Rationale |
|---|---|---|
| continuous (climate, soil, DEM, population, hydro aggregates) | `bilinear` | preserves continuous gradients |
| categorical (LULC class, lithology codes) | `nearest` | never interpolates non-existent classes |
| proportion / distance | `bilinear` | derived continuous quantities |
| fine-resolution source (30 m / 90 m) downscaled by a large factor | `average` (continuous) / `mode` (categorical) | aggregate first, then align; no interpolation of block statistics |

Unit scales (e.g. CSDLv2 storage value x 0.01, footHII x 0.01, canopy height
dm -> m) are applied in the same step in the production pipeline; see
`pipeline_r/config.yaml` (`units_scale`).

## Running the example

Requires Python with `rasterio`, `numpy`, `pyyaml`.

```console
python standardization_example.py \
    --source ../data/sample_layers/glo/bioclim/cnclim1km/present/bio01/glo_bioclim_cnclim1km_present_bio01.tif \
    --kind   continuous \
    --output standardized_bio01.tif
```

Expected output (the sample layer is already on the CHECO26 grid, so the
example reproduces the delivered layer exactly):

```text
source : .../glo_bioclim_cnclim1km_present_bio01.tif (China_Albers, 1000 m)
China mask applied: 9490310 of 19745382 cells valid
output : standardized_bio01.tif
         dtype=float32 nodata=-9999.0 valid=9409716 min=-20.6223 max=25.8854
aligned with CHECO26-standardgrid.tif: True
```

`--kind` accepts `continuous`, `categorical`, `proportion` or `distance`;
`--no-mask` skips the China clip (not recommended). Point `--source` at any
GeoTIFF to standardize it onto the CHECO26 grid.
