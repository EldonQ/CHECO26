# CHECO26 pipeline (R)

This is the pipeline that produced the delivered archive: 21,788 layers, 183.2 GB,
float32 on the China_Albers 1-km grid.

It supersedes an earlier Python pipeline that produced a 1,595-layer delivery. That
pipeline is not included here; the delivery documentation records which layers it
produced, per layer, in the `script_function` column of the provenance table. The
numbers in this repository all refer to the current delivery.

## Layout

```
pipeline_r/
├── config.yaml              project configuration: grid, CRS, NoData, radii, source paths
├── scripts/
│   ├── _bootstrap.R         resolves CHECO_ROOT and sources 00_config + 01_common
│   ├── 00_config.R          reads config.yaml, defines the path and grid helpers
│   ├── 01_common.R          shared raster utilities (write, mask, focal, reproject)
│   ├── 01b_ccl.R            connected-component labelling used by the landscape metrics
│   ├── 02_template.R        builds the 1-km template and the all-touched China mask
│   ├── 02b_hydro_stats.R    hydrographic window statistics
│   ├── 03_ingest_static.R   static sources: climate, soil, DEM, vegetation
│   ├── 04_ingest_timeseries.R  annual series: human footprint, settlement epochs
│   ├── 05_derive_lulc.R     land-cover proportions and landscape metrics
│   ├── 06_derive_lulc_clcd.R        CLCD annual cover
│   ├── 07_derive_lulc_hlu1km.R      harmonised 1960–2100 reconstruction
│   ├── 08_derive_topo_vege.R        soil profiles and legacy terrain helpers
│   ├── 09_derive_dist.R             distance surfaces
│   ├── 10_future_chains.R           future climate chains
│   ├── 11_validate.R                whole-library validation (V1–V6)
│   ├── 12_make_docs.R               variable dictionary and layer index
│   ├── 13_make_provenance.R         per-layer provenance table
│   ├── 14_manifest.R                SHA-256 manifest (CHECO release: covariates + mask_china.tif + template)
│   ├── 16_ingest_hydrosheds_accum.R   HydroSHEDS accumulation reproduction (scratch)
│   ├── 17_rebuild_h90m_upstream.R    upstream-cell elevation mean, min and max
│   ├── 18_ingest_copdem90.R          Copernicus GLO-90 terrain
│   ├── run_all.R                    runs the stages in order
│   ├── run_bioclim_chelsa.R         CHELSA bioclim production entry (present + future)
│   ├── run_bioclim_shard.R          sharded CHELSA future production
│   ├── run_metadata_chelsa.R        post-CHELSA metadata regeneration entry
│   ├── tools/               verification and reporting utilities (incl. accept_chelsa.R)
│   ├── tests/               67 unit and integration tests
│   └── figs/                8 figure scripts used by the manuscript
└── tools/
    └── make_datalayers_details.py   renders ../data/CHECO26_datalayers_details.csv
```

## Running it

The scripts resolve their paths from a single root, `CHECO_ROOT`, and read
`<CHECO_ROOT>/scripts/config.yaml`. That layout is the delivery layout, which is
wider than this repository: the delivery root also holds `data/covariates/`,
`logs/` and `00_docs/`. A checkout of this repository alone therefore documents
the pipeline but cannot execute it — the rasters are not here.

```bash
export CHECO_ROOT=/path/to/delivery      # or set it in scripts/_bootstrap.R
Rscript scripts/02_template.R
Rscript scripts/run_all.R 04 09 10 17 18  # revised stages with their production sources
```

`config.yaml` in this folder is a copy of the delivery configuration, so the grid
definition, the NoData conventions and the four focal radii are inspectable
without the archive.

## Requirements

The delivery was produced with the following stack (versions verified on the
production machine):

| Component | Version |
|---|---|
| R | 4.4.3 (2025-02-28 ucrt) |
| terra | 1.8.54 |
| GDAL | 3.10.1 |
| PROJ | 9.5.1 |
| GEOS | 3.13.0 |
| sf | 1.1.0 |
| exactextractr | 0.10.1 |
| yaml | 2.3.12 |

The figure scripts additionally use `scales`. Byte-for-byte reproduction of the
continuous layers requires this GDAL version: bilinear resampling weights differ
slightly between GDAL releases, so a different GDAL can leave sub-pixel
residuals on continuous layers.

Reproducing the aggregation stages needs more disk than the delivery itself: each
worker spills about 18.5 GB into `tempdir()` while mosaicking the 30 m sources,
which reaches 168.6 GB with six workers. Point `TMPDIR` at a data disk — a rerun
needs roughly 210 GB for layers plus 500 GB of scratch, and a full system disk
fails the writes silently while the workers stay alive.

## Stage 11

`11_validate.R` checks six properties and prints a coverage summary. V1 (grid
invariants) and V2 (format) are exhaustive — every layer is opened; V3–V6 are
sampled, and the script says so in its own output so the distinction cannot be
lost in transcription.

```bash
Rscript scripts/11_validate.R header      # V1/V2 over all 21,788 layers
Rscript scripts/11_validate.R full 400    # V3/V4 on a 400-layer probe
```

## Revision stages

Stage 09 uses an Rcpp exact Euclidean grid transform. The native JRC water step uses Python with rasterio, NumPy, SciPy and pyproj. Stage 17 rebuilds the three Hydrography90m upstream elevation statistics. Set `CHECO_H90M_RAW` and `CHECO_H90M_BOUNDARY` to the raw tiles and clipping boundary. Stage 18 reads the versioned Copernicus GLO-90 tiles from `CHECO_COPDEM90_SRC`. Use `tools/fetch_copdem90.py` and compare its tile SHA-256 records with `data/COPDEM90_source_tiles.csv`. To reproduce the release selection pass the production public manifest to `make_datalayers_details.py --release-manifest`. Pass `--production-manifest` with the full SHA-256 inventory to include file sizes and hashes.

The JRC revision used NumPy 1.26.4, SciPy 1.11.4, rasterio 1.4.4 (GDAL 3.10.3) and pyproj 3.7.2. The complete historical inventory uses additional source-specific entry points and pinned intermediate assets.
