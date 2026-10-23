# CHECO26 production pipeline

The complete, idempotent pipeline that builds the CHECO26 delivery tree
(21,110 standardized layers, 8 themes) from heterogeneous source products. This
is a faithful copy of the production scripts that built the delivered database;
the only addition is `scripts/11_make_datalayers_details.py`, which renders the public
layer manifest ([`../data/CHECO26_datalayers_details.csv`](../data/CHECO26_datalayers_details.csv))
from the per-layer dictionary.

## Stages

Run in order; every stage is idempotent (existing outputs are skipped unless
`CHECO26_FORCE=1`) and writes atomically (`.tmp` + rename, no half files).

| # | Script | Produces |
|---|---|---|
| 01 | `01_template.py` | standard grid (`data/CHECO26-standardgrid.tif`), China mask (`data/mask_china.tif`), grid metadata |
| 02 | `02_ingest_static.py` | static layers: bioclim present (28), CSDLv2 soil (168), DEM/slope, Hydrography90m continuous layers, vege base layers — warped to the template per the fixed rules |
| 02b | `02b_hydro_stats_addon.py` | hydro window statistics with ecological semantics (min/max) for water-reachability and extreme-value variables |
| 03 | `03_ingest_timeseries.py` | time series: LandScan population (25 years), WCS footHII (20 years), GHS-SMOD built-up proportion (12 epochs), GLASS NDVI (3 years) — plus focal windows |
| 04 | `04_derive_lulc.py` | LULC discrete→continuous derivations: class proportions, Shannon diversity, edge density, patch density / mean patch size, across 10 snapshots (history 2020 + 9 future scenarios) |
| 05 | `05_derive_dist.py` | distance layers: GRIP4 roads / major roads, OSM trails, GHS-SMOD urban, GSW water, Hydrography90m stream distances |
| 06 | `06_derive_topo_vege.py` | aspect (Horn), TRI (Riley et al. 1999), CSDLv2 whole-profile thickness-weighted means, vege focal windows |
| 07 | `07_future_chains.py` | future climate: 2 chains (ensemble mean, BCC-CSM2-MR) x 3 SSPs x 3 periods x 28 variables = 504 layers in N-SDM `scenario/<year>/<ssp>` layout |
| 08 | `08_validate.py` | full-library acceptance gates (existence / alignment / mask / naming / values / cell-by-cell) |
| 09 | `09_make_docs.py` | fact-driven documentation: `variable_dictionary.csv`, scope statements, validation report |
| 10 | `10_validate_derived.py` | derived-layer gates: value range vs. base layer, empty-window NoData, LULC theoretical bounds |
| 11 | `scripts/11_make_datalayers_details.py` | public layer manifest in SWECO25 column layout (added for this repository) |
| — | `p0_lulc_qc.py` | LULC source QC before ingestion |
| — | `repair_focal_layers.py` | 2026-10-06 focal empty-window repair (524 layers rebuilt) |
| — | `withdraw_hydro_layers.py` | 2026-10-06 withdrawal of 8 defective-source hydro layers |
| — | `make_provenance_table.py` | per-layer provenance table |
| — | `common.py` | shared library: grid spec, mask, warp-to-template, focal mean, naming validator, lineage ledger |
| — | `vardefs.py`, `srcmeta.py` | variable definitions and source metadata tables |
| — | `test_focal_mean.py` | unit test of the focal-mean empty-window criterion |

## Configuration

`config.yaml` is the **single parameter source** — grid geometry, mask
convention, resampling rules, focal radii, derivation definitions (with
literature citations), unit scales, variable lists and source paths. The code
contains no magic numbers; any config change is a version change that requires
re-running the affected layers and leaves a new `config_hash` in the lineage
ledger (`logs/lineage.csv`).

> **Local paths.** The `paths` block points at the original production
> environment (`E:/CHECO26/...`, `E:/h90m/Final`). Adapt it to your local
> layout before running; everything else is portable.

## Requirements

Python with `rasterio`, `numpy`, `scipy`, `pyyaml`, `pyogrio`
(plus `matplotlib` / `geopandas` for the QC visualisation).

## Fixed decisions worth knowing

- **Resampling is variable-type driven**: `categorical=nearest`,
  `continuous/proportion/distance=bilinear`, fine-resolution downscaling uses
  `average` / `mode`, window extremes use `min` / `max`.
- **Every layer is clipped to the China mask** (`china.shp`,
  `all_touched=True`, islands kept); no layer may hold cells outside the
  boundary (hard gate).
- **Naming follows the DATAPREP / N-SDM 2.0.1 convention**: folder names carry
  no underscores; the file name is the folder path joined by underscores plus
  an allowed suffix; focal suffixes are metres (`_f5000`); future layers live
  under `scenario/<year>/<ssp>/`.
- **Zero-crop policy**: config year lists equal the full set available on disk
  (e.g. all 25 LandScan years), so the inventory is an honest reflection of the
  sources.
- **Lineage**: every layer records source file, producing script, config hash
  and timestamp in `logs/lineage.csv`.

## Source products

| Theme | Product | Citation |
|---|---|---|
| bioclim | CNClim1km (present + future) | China Meteorological Administration 1-km climate surfaces |
| soil | CSDLv2 | Shi & Shangguan (2024) |
| topo | China DEM 1 km | — |
| vege | Forest AGB / canopy height 2019, CATCD 2025 tree cover, GLASS NDVI | — |
| hydro | Hydrography90m (China) | Amatulli et al. (2022) |
| lulc | Global LULC projection 2020–2100, 1 km | Zhang et al. (2023) |
| anthro | LandScan, WCS footHII, GHS-SMOD | — |
| dist | GRIP4 roads, OpenStreetMap trails, JRC Global Surface Water, GHS-SMOD, Hydrography90m streams | Meijer et al. (2018) |

## Validation

The acceptance gates are implemented twice on purpose: inside the pipeline
(`08_validate.py`, `10_validate_derived.py`) and as self-contained public
scripts in [`../database_validation/script/`](../database_validation/script/)
that run from this repository's public artefacts alone. Results, figures and
forensics (withdrawn layers, focal repair) are documented in
[`../database_validation/README.md`](../database_validation/README.md).
