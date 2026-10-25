# Database validation — CHECO26 v2.0

This folder holds the evidence that the delivered archive is what it claims to be:
the checks that were run, their results, the code that produced them, and the
anomalies that were found and resolved along the way.

The full v2.0 verification report is [`V2_VERIFICATION_REPORT.md`](V2_VERIFICATION_REPORT.md),
the independent recomputation is [`INDEPENDENT_VERIFICATION.md`](INDEPENDENT_VERIFICATION.md),
and the layer-by-layer audit is [`DATA_QUALITY_AUDIT.md`](DATA_QUALITY_AUDIT.md).
This README is the summary; where they disagree, the underlying reports win.

**Read the coverage column before the result column.** Two of the six checks open
every layer and four do not. A "pass" from a sampled check is not evidence about
the layers it never touched, and the numbers below never present it as such.

## What was checked

| Check | Coverage | What it verifies | Result |
|---|---|---|---|
| **V1** | **21,110 / 21,110 — all layers** | CRS, extent, 1,000 m cell size, 4,062 × 4,861 grid | **21,110 pass** |
| **V2** | **21,110 / 21,110 — all layers** | float32, declared NoData −9999, tiling, compression | **21,110 pass** |
| V3 | 48 sampled | no valid cell outside the China mask | 48 / 48 |
| V4 | 48 sampled | NoData encoding agrees with the declared value | 48 / 48 |
| V5 | 12 groups, stratified by theme and dataset | class proportions sum to 1 | 12 / 12 |
| V6 | 18 sampled | focal values lie inside their parent's range | 18 / 18 |

V1 and V2 read file headers only, which is why they can cover the whole archive.
V3–V6 read pixels, and a full pass would take hours; they are sampled by design.

## Full-archive audit on an independent toolchain

V1 and V2 come from the production validator, so a defect there would be invisible
above. The whole archive was therefore audited a second time with a separate stack
— Python 3 with rasterio 1.4, no terra — opening every GeoTIFF and reading every
pixel. Tables are in [`result_dataframe/`](result_dataframe/), the report is
[`DATA_QUALITY_AUDIT.md`](DATA_QUALITY_AUDIT.md), the code is `script/audit_*.py`.

| Check | Result |
|---|---:|
| opens, single band | **21,110 / 21,110** |
| float32 | **21,110 / 21,110** |
| NoData −9999 declared | **21,110 / 21,110** |
| grid invariants (CRS, transform, 4,861 × 4,062) | **21,110 / 21,110** |
| DEFLATE, tiled 256 × 256 | **21,110 / 21,110** |
| no valid cell outside the China mask | **21,110 / 21,110** |
| no Inf/NaN among valid cells | **21,110 / 21,110** |
| values inside the documented range | **21,110 / 21,110** |
| agrees with `variable_dictionary.csv` (min, max, n_valid) | **21,110 / 21,110** |
| agrees with `MANIFEST.csv` SHA-256 | **21,110 / 21,110** |

**No layer failed any check.** The same audit extended two checks beyond the
sampling above: it re-derived the composition identity for all **497** base
proportion groups (3,982 layers, against 12 sampled in V5), and it compared five
cross-theme layers point by point against their original sources at 3,000 random
cells (r = 0.983–0.9999, mean bias ≈ 0).

Two toolchains now agree on every claim, so none of these numbers depends on the
implementation that produced it. The audit report reproduces the delivery-side
paths (`audit/*.csv`, `scripts/audit/*.py`); in this repository those files are
`result_dataframe/*` and `script/audit_*.py`. The audit also records what is *not* a failure but
still matters to a user — see §5 of the audit report, which covers the constant
`outlet` layer, the class-restricted patch metrics, the 7,063 byte-identical
layers, and the five climate variables whose source definitions are not WorldClim's.

## Composition identities (V5)

A categorical source, one-hot encoded and area-weighted, must sum to 1 in every
valid cell. The residual should therefore come only from float32 representation.

| Product | Classes | Years checked | max \|Σ − 1\| |
|---|---:|---|---:|
| `clcd` (observed, aggregated from 30 m) | 9 | 2000, 2001, 2003, 2004 | 5.03–5.22 × 10⁻⁸ |
| `glu1km` (projected, 1 km source) | 6 | four scenario snapshots | 0.000 (exact) |
| `hlu1km` (projected, 0.01° source) | 8 | 1961, 1962, 1966, 1967 | 4.470 × 10⁻⁸ |

`glu1km` closes exactly because its source is published as integer percentages, so
no float aggregation happens. The full audit re-ran this for every base group:
**497 / 497 pass**, with max |Σ − 1| of 5.215 × 10⁻⁸ (clcd), 4.843 × 10⁻⁸ (hlu1km)
and exactly 0 (glu1km). The other two sit at the float32 representation
limit. Two independently built products converging on the same error magnitude,
one of them exact, points to the representation layer rather than the code.

## Independent recomputation

[`script/verify_independent.R`](script/verify_independent.R) re-derives 16
properties using only `terra` and base R, calling no project helper: **16 pass, 0 fail**.

| Group | Comparison | Comparisons | Result |
|---|---|---:|---|
| A | layer count equals 21,110 | 1 | pass |
| A | manifest versus disk, both directions | 21,110 | 0 extra on either side |
| B | 60 random layers against the template (extent, dims, resolution) | 60 | 0 mismatches |
| C | 60 layers declare −9999 | 60 | all |
| C | `terra::NAflag()` returns NaN for float layers | 60 | all |
| C | NoData cell count equals the mask's zero count | 19,745,382 | 10,255,072 = 10,255,072 |
| D | mask valid / invalid cells | 2 | 9,490,310 / 10,255,072 |
| E | 10 random layers, recompute min/max/n_valid | 10 | 0 mismatches |
| F | 8 random layers, re-hash SHA-256 | 8 | 0 mismatches |
| G | CLCD composition identity on 2008 | 9,471,991 | 5.215 × 10⁻⁸ |

## Resampling effect

Each layer contributes 200 random 1 km cells. For each, the cell polygon is
transformed to the source CRS, the source raster clipped to it, and the
area-weighted source mean compared with the delivered value. The within-cell
coefficient of variation is reported alongside because it says how much
sub-kilometre structure a 1 km value absorbs.

| Layer | Median source cells per 1 km cell | Median absolute difference | Median relative difference | Relative difference under 1% | Within-cell CV (median) |
|---|---:|---:|---:|---:|---:|
| vege / canopy height (30 m) | 1,300 | 0.000 m | 0.00% | 75.5% | 90.0% |
| dist / river distance (90 m) | 144 | 4.21 m | 2.40% | 29.5% | 77.0% |
| hydro / flow accumulation (90 m) | 144 | 2.02 | 7.75% | 13.0% | 277.4% |

Canopy height reproduces the source mean exactly at the median. Flow accumulation
has the largest relative difference because the variable spans eight orders of
magnitude, so an absolute difference of about 2 becomes a large relative
difference wherever the cell mean is small.

The within-cell CV is the number that matters for use: it is why the land-cover
family ships nine per-cell areal proportions rather than a single dominant class.

## Byte-level uniqueness

Counting distinct SHA-256 digests over the whole archive: **14,047 of 21,110 layers
are byte-distinct (66.5%)**, so the layer count overstates the amount of distinct
information by about a third. Six of the eight themes contain no duplicates at all;
the redundancy is confined to the projected land-use family, where the projected
urban extent is frozen across all five SSP-RCP scenarios and therefore repeats.

## Distribution and licensing

| Group | Layers |
|---|---:|
| Open licence (CC BY 4.0, ODbL 1.0, Copernicus) | 21,025 |
| Non-commercial (CC BY-NC 4.0, of which 4 are CC BY-NC-SA 4.0) | 80 |
| Withheld (HydroSHEDS v1 flow accumulation) | 5 |
| **Total** | **21,110** |

Per-layer records are in [`result_dataframe/per_layer_stats.csv`](result_dataframe/per_layer_stats.csv)
(licence class and release status per row) and in `RESTRICTED_LAYERS.csv`.

## Withdrawn layers

Eight Hydrography90m layers were withdrawn from the delivery after the source
products themselves proved numerically unusable — negative flow accumulation down
to −244,806 km², and a composite terrain index spanning ±1.8 × 10⁹. The delivered
values were verified cell by cell to be a faithful downscaling of those sources,
so a rerun cannot repair them. They remain in the provenance table with
`status = withdrawn` so the removal is auditable rather than silent.

## Six defects found in the validator itself

This is the most useful section of the folder. Early in the campaign the checks
reported pass because they were doing nothing:

| # | Defect | Symptom | Fix |
|---|---|---|---|
| 1 | V4 used `terra::NAflag()` | returns NaN for float rasters, so the whole check was skipped | read `NoData Value=` from the GDAL metadata block |
| 2 | V5 grouped by `dirname()` | classes live in sibling directories, so every group had one file and was skipped | group on the two levels above the file |
| 3 | `limit` truncated the whole file list | `full 40` silently restricted V3–V6 to 40 layers | `limit` now only bounds V1/V2 |
| 4 | V5 used `global(min)` after the rewrite | cells outside the mask are 0, so `dev = 1` and correct data failed | evaluate only where Σ > 0 |
| 5 | V5 took the 12 oldest groups by mtime | systematically excluded the newest data — none of the 12 was CLCD | stratify by theme/dataset and rotate |
| 6 | the first independent script prefixed paths wrongly | compared 0 layers and reported pass | fixed the prefix, and every check now prints its comparison count |

The lasting guard is the last row: every check reports how many comparisons it
made, so a check that did nothing cannot masquerade as a check that passed.

## What could not be verified

- **Source integrity.** Ingest checksums were not retained, so the source files can
  no longer be re-verified against the delivered archive.
- **Comparison with the v1.0 Python delivery.** That delivery was replaced in
  place, so a like-for-like comparison is impossible. Two diagnostic rasters do
  survive and answer the question for both resampling rules: bilinear gives a mean
  absolute difference of 0.0146 °C but only 2.85% bit-identical cells, while
  nearest gives 94.48% bit-identical cells but differences up to 9.71 °C in the
  rest. v2.0 is therefore not a drop-in numerical replacement for v1.0, and users
  needing continuity must recompute derived quantities from v2.0.

## Reproducing

```bash
Rscript pipeline_r/scripts/11_validate.R header      # V1/V2 over all 21,110 layers
Rscript script/verify_independent.R                   # 16 independent checks
Rscript script/check_table2.R                         # per-dataset counts sum to 21,110
Rscript script/check_docs_consistency.R               # documentation numbers versus disk
Rscript script/check_trends.R                         # temporal consistency of annual series
Rscript script/resampling_effect.R                    # source-versus-resampled comparison
python script/make_result_dataframes.py --delivery <delivery-root> --outdir result_dataframe
python script/make_validation_figures.py
```

The R scripts expect `CHECO_ROOT` to point at the delivery root, which holds
`data/covariates/`, `scripts/config.yaml` and `00_docs/`.

## Layout

| Path | Content |
|---|---|
| `V2_VERIFICATION_REPORT.md` | full v2.0 verification report |
| `INDEPENDENT_VERIFICATION.md` | the independent recomputation, written up separately |
| `result_dataframe/per_layer_stats.csv` | one row per layer: theme, dataset, unit, n_valid, na_frac, min, max, bytes, SHA-256, licence class, release status |
| `result_dataframe/licence_summary.csv` | layer counts per licence class and release status |
| `result_dataframe/*_identity_check.csv`, `resampling_effect.csv`, `python_vs_r_comparison.csv` | the tables behind the numbers above |
| `figures/` | value range per layer, NoData count per layer, theme inventory |
| `script/` | the checks and the scripts that regenerate the tables and figures |
| `v1_archive/` | the v1.0 validation campaign, kept for provenance only |
