# CHECO26 focal statistics

A minimal, runnable example of the multi-scale focal statistics that give every
CHECO26 cell its landscape context.

The example is **not** a re-implementation. It sources the production scripts
(`pipeline_r/scripts/00_config.R` and `01_common.R`) and calls the production
functions:

```r
layers <- focal_all(base)          # four windows at once, radii from config.yaml
focal_mean(base, 5L)               # or one window at a time
```

The four windows (3 x 3, 11 x 11, 21 x 21, 41 x 41 cells) are read from
`pipeline_r/config.yaml` (`focal.radii_km`), not restated here.

## Window semantics

CHECO26 focal layers are named with a suffix that encodes the **window size in
metres**; the window is a **square** of `2 * radius + 1` cells:

| Suffix | Window | Coverage | Equivalent circle radius |
|---|---|---|---|
| `_f1000` | 3 x 3 | 3 km x 3 km | ~1.69 km |
| `_f5000` | 11 x 11 | 11 km x 11 km | ~6.2 km |
| `_f10000` | 21 x 21 | 21 km x 21 km | ~11.9 km |
| `_f20000` | 41 x 41 | 41 km x 41 km | ~23.1 km |

Two points that are easy to get wrong:

- `_f1000` is the *smallest multi-cell window* on the 1-km grid, **not** a
  1-km radius disc: a strict 1-km disc on a 1-km grid is degenerate (a single
  cell under `<`, a 5-cell cross under `<=`).
- Patch metrics (`patchdensity`, `patchsize`) use **circular** windows, a
  different convention from the square focal-mean layers.

## The empty-window rule

A window that contains no valid cell must output NoData. For the large windows
the denominator is an explicit count layer, and a window counts as empty when
the count falls below 0.5; for the small windows `terra::focal(na.rm = TRUE)`
divides by the number of valid cells inside the window. Both routes were
verified against exact integer counts for all four window sizes.

This matters: an earlier implementation tested `c > 0` against the
floating-point residue of a window mean, which is always true, so 242 focal
layers once carried garbage values (up to 4,384 against a base range of 0-63.7).
The repair rebuilt 524 derived layers and is documented in
[`../database_validation/README.md`](../database_validation/README.md).

## Run

```bash
Rscript focal_statistics_example/focal_statistics.R
```

Requires R with `terra` and `yaml`. The input and the reference output are both
in this repository:

- input: `data/sample_layers/.../reg_lulc_glu1km_2020_forest_prop.tif` (base 1-km layer)
- reference: `data/sample_layers/.../reg_lulc_glu1km_2020_forest_prop_f5000.tif` (delivered layer)

## What the example checks

| Check | What it verifies |
|---|---|
| G1 | a window mean cannot leave the base range (0 violations) |
| G2 | recomputing `_f5000` from the base layer reproduces the delivered layer cell by cell |

G2 currently reports a maximum difference of 3.0e-8 over 9,490,284 cells and
zero cells above 1e-6 — that is float32 rounding, so the production function
reproduces the archive exactly. The script exits non-zero if either check fails,
so it doubles as a regression test of `focal_mean()`.

## A note on the sample layers

While building this example we found that the copy of
`reg_lulc_glu1km_2020_forest_prop_f5000.tif` that had been shipped in
`data/sample_layers/` did not match the archive (it had 26,279 distinct values
where the archive layer has 4,496, and it disagreed with the base layer). It was
replaced with the archive version; the other sample layers were checked cell by
cell against the archive and agree exactly.
