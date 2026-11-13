# Database validation — CHECO26

The database holds **21,788 layers** (25 dataset entries from 19 source products,
8 themes) on the China_Albers 1-km grid (4,861 × 4,062 cells, float32,
NoData −9999, DEFLATE, 256 × 256 tiles). This folder summarises how the current
delivery is validated; the validation code lives in
[`../pipeline_r/scripts/tools/`](../pipeline_r/scripts/tools/).

## Four-way consistency

Disk = SHA-256 manifest = provenance table (active rows) = variable dictionary,
all at **21,788 layers**. Checked by `check_table2.R` (per-dataset counts, 21/21
agree, sum equals the disk total) and `check_docs_consistency.R` (layer counts,
theme totals, volume and manuscript numbers against the tables).

## Checks

| Check | Coverage | Tool |
|---|---|---|
| Grid invariants (CRS, extent, 1,000 m, 4,861 × 4,062) | every layer | `11_validate.R` V1 |
| Format (float32, NoData −9999, DEFLATE, 256 × 256 tiles) | every layer | `11_validate.R` V2 |
| Mask compliance, value range, dictionary / manifest agreement | every layer | `11_validate.R` V3–V6 |
| bioclim CHELSA acceptance: geometry / mask / NoData / value range, standard WorldClim calibre for bio02/03/05/06 | 1,210 bioclim layers | `tools/accept_chelsa.R` — 20 checks, 0 failures |
| Independent recomputation (16 properties, a second implementation sharing no code with the pipeline) | whole library | `tools/verify_independent.R` |

The bioclim theme is **CHELSA v2.1** (1,210 layers, CC0-1.0, standard BioClim
calibre). Its acceptance (`accept_chelsa.R`) confirms 22 present + 1,188 future
layers, mask-exact coverage for bio01–19 (9,490,310 valid cells, zero outside
China), bio02 median 10.99 °C and bio06 minimum −46.79 °C (standard calibre), and
gdd0/5/10 coverage faithful to the CHELSA source NoData. The other 20,578 layers
were validated by an exhaustive every-pixel audit (Python + rasterio, independent
of the R + terra production validator) and are unchanged.

## Known source-level limitations

- Eight Hydrography90m layers were **withdrawn** after the source products proved
  numerically unusable (provenance table, `status = withdrawn`).
- Five HydroSHEDS flow-accumulation layers are **withheld** from public release:
  the HydroSHEDS licence grants no right to redistribute under an open licence.
- gdd0/5/10 retain the CHELSA source NoData over cold / ocean areas, so their
  valid-cell count is below the full mask; this is faithful to the source, not a
  processing defect.

## Licence

Per-layer licences are recorded in the provenance table and summarised in the
repository `.zenodo.json` / `CITATION.cff`: CC BY 4.0 (20,491), CC0-1.0 (1,210,
CHELSA), CC BY-NC 4.0 (76), CC BY-NC-SA 4.0 (4), Copernicus (1), ODbL 1.0 (1);
21,783 layers are public, 5 HydroSHEDS layers withheld.

---

*The detailed pre-replacement audit campaign (the 21,110-layer tree with cnclim1km
bioclim, run before the 2026-11-13 CHELSA replacement) is archived locally outside
this repository and is not part of the public release.*