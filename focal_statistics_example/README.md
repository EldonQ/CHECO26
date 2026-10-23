# CHECO26 focal statistics

This directory provides a minimal, runnable example of the multi-scale focal
statistics that give every CHECO26 cell its landscape context. The production stack is
`pipeline_r/scripts/01_common.R`, which builds four square windows of 3, 11,
21 and 41 cells (1, 5, 10 and 20 km radii).

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

A window that contains no valid cell must output NoData. The validity test
uses the float criterion `c >= 0.5 / size^2`, where `c` is the window mean of
the validity mask: an empty window leaves a rounding residue of ~10^-17 while a
single valid cell gives `1/size^2 >= 5.9e-4`, so the threshold separates them
by ~11 orders of magnitude. It was verified to classify identically to exact
integer counts for all four window sizes.

This criterion matters: the original implementation tested `c > 0` against the
floating-point residue, which is always true, so 242 focal layers once carried
garbage values (up to 4,384 against a base range of 0-63.7). The repair rebuilt
524 derived layers and is documented in
[`../database_validation/README.md`](../database_validation/README.md).

## Running the example

Requires Python with `rasterio`, `numpy`, `scipy`.

```console
python focal_statistics.py \
    --source ../data/sample_layers/glo/bioclim/cnclim1km/present/bio01/glo_bioclim_cnclim1km_present_bio01.tif \
    --radius-km 5 \
    --output focal_bio01_f5000.tif
```

Expected output:

```text
window            : 11 x 11 cells (11 km x 11 km)
base range        : [-20.6223, 25.8854]
focal range       : [-14.1004, 25.8678]
valid cells       : 9488253 of 19745382
G1 out-of-range   : 0 (must be 0)
output            : focal_bio01_f5000.tif
```

The script also checks gate G1 (a window mean cannot leave the base range) and
exits non-zero on violation, so it doubles as a unit test of the criterion.
