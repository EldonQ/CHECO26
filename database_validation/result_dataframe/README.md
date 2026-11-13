# Result dataframes — historical audit evidence (pre-replacement)

These CSV/JSON files are the outputs of the full-archive audit run on the
**pre-replacement 21,110-layer tree** (bioclim = cnclim1km, 166.9 GB), produced
by the scripts in [`../script/`](../script/). They are retained as historical
evidence of what was audited, not as a description of the current database.

On 2026-11-13 the bioclim theme was replaced with **CHELSA v2.1** (1,210 layers,
standard BioClim calibre, CC0-1.0); the database now holds **21,788 layers
(183.1 GB)** and the 532 cnclim1km layers were archived. Consequently:

- `layer_audit.csv`, `per_layer_stats.csv`, `theme_summary.csv`,
  `manifest_reverify.csv`, `audit_summary.json`, `provenance_*.csv` and
  `licence_summary.csv` describe the 21,110-layer pre-replacement tree
  (`audit_summary.json` still records `layers_expected: 21110`).
- `NONSTANDARD_CLIMATE_LAYERS.csv` lists the 95 non-standard cnclim1km
  bio02/03/05/06/07 layers. Those layers are now **archived**; the CHELSA
  replacement uses standard WorldClim calibre, so this file is historical and
  does not describe any current layer.
- `bioclim_identity_check.csv`, `source_fidelity.csv`, `composition_identity.csv`,
  `focal_nesting.csv`, `resampling_effect.csv` likewise refer to the
  pre-replacement build.

The current database is validated by
[`../../pipeline_r/scripts/tools/accept_chelsa.R`](../../pipeline_r/scripts/tools/accept_chelsa.R)
(20 checks, 0 failures) and four-way disk = manifest = provenance = dictionary
consistency at 21,788 layers. The non-bioclim layers (20,578) are unchanged from
the tree audited here; the 1,210 CHELSA bioclim layers were re-validated by the
acceptance script.