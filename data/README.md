# CHECO26 data artefacts

Light-weight data assets that ship with the repository. The full database
(166.9 GB) is not yet publicly released (see the main
[README](../README.md#data-availability)); these artefacts let you audit the
inventory, build the exact grid, and inspect representative layers without
downloading anything.

| File | What it is |
|---|---|
| `CHECO26_datalayers_details.csv` | **Layer manifest** — one row per delivered layer (21,110 rows), in the shared 14-column semicolon layout |
| `CHECO26-standardgrid.tif` | the template grid every layer is aligned to (China_Albers, 1000 m, 4861 x 4062, value 1) |
| `mask_china.tif` | China mask (1 = inside the national boundary, `all_touched=True`), 9,490,310 valid cells |
| `table2_dataset_layer_counts.csv` | machine-readable version of Table 1 in the manuscript: layer counts per dataset entry |
| `table3_resampling_effect.csv` | machine-readable version of Table 2: the resampling check on three representative layers |
| `sample_layers/reg/...` | seven representative delivered layers, checked cell by cell against the delivery tree, kept in the delivery directory layout so the naming convention is self-documenting |
| `source_layers/cnclim1km/...` | the raw 0.01° source of one sample layer (CNClim1km bio01), used by the standardization example to demonstrate reprojection from EPSG:4326 |
| `source_layers/smod/...` | GHS-SMOD 2020 settlement classes cropped to the China window (30 arc-sec, CC BY 4.0), the public input of the distance example |

## Naming convention

Every layer path has six levels, `scope/theme/dataset/period/variable/file`, and the
file name repeats the scope and the theme (`reg_<theme>_<dataset>_...tif`). The scope of
CHECO26 is **`reg`** (regional, the China window); the archive and any deployment that
follows the nsdm layout therefore use the same names — no prefix rewriting is needed
when the data move. A `glo` scope exists in the wider project for global products and is
not part of CHECO26.

## Manifest columns

`category;dataset;variable;period;scenario;sub_period;start_year;end_year;attribute;focal;variable_long;unit;path;valid`

| Column | Meaning |
|---|---|
| `category` | theme: bioclim, soil, topo, vege, hydro, lulc, anthro, dist |
| `dataset` | source product (e.g. `cnclim1km`, `csdlv2`, `h90m`, `glu1km`, `foothii`) |
| `variable` | variable token (e.g. `bio01`, `ph`, `elev`, `forest`, `hii`, `spi`, `road`) |
| `period` | `present` or `future` |
| `scenario` | `ssp126` / `ssp245` / `ssp585` for future layers, else `NA` |
| `sub_period` | period identifier: `1991_2020` (present climate), centre year for future layers, year for time series, else `NA` |
| `start_year` / `end_year` | source year range of the layer |
| `attribute` | sub-variable qualifier: soil depth code (0/5/15/30/60/100), derivation (`prop`, `profile`, `min`, `max`, `all`/`forest` patch scope), else `NA` |
| `focal` | focal window size in metres (1000 / 5000 / 10000 / 20000), else `NA` |
| `variable_long` | English long name |
| `unit` | physical unit |
| `path` | path inside the delivery tree (relative to the covariates root) |
| `valid` | `yes` for all delivered layers |

Soil depth codes: `0` = 0–5 cm, `5` = 5–15 cm, `15` = 15–30 cm,
`30` = 30–60 cm, `60` = 60–100 cm, `100` = 100–200 cm; `profile` is the
thickness-weighted whole-profile aggregate. The manifest is regenerated from
the production dictionary by [`../pipeline_r/tools/make_datalayers_details.py`](../pipeline_r/tools/make_datalayers_details.py).

## Sample layers

| Sample | Theme | Dataset | Why this layer |
|---|---|---|---|
| `reg/bioclim/cnclim1km/present/bio01/...` | bioclim | CNClim1km | the template-defining climate layer (annual mean temperature) |
| `reg/soil/csdlv2/ph/...` | soil | CSDLv2 | whole-profile pH, shows the soil depth convention |
| `reg/topo/chinadem/elev/...` | topo | China DEM | national elevation |
| `reg/anthro/foothii/2020/hii/...` | anthro | WCS footHII | human footprint index, 2020 |
| `reg/lulc/glu1km/2020/forest/..._prop.tif` | lulc | Global LULC projection | the base proportion layer, focal input of the example below |
| `reg/lulc/glu1km/2020/forest/..._prop_f5000.tif` | lulc | Global LULC projection | flagship discrete-to-continuous derivation (forest proportion, 5-km window) |
| `reg/lulc/glu1km/2020/forest/..._prop_f20000.tif` | lulc | Global LULC projection | same derivation at the widest window (41 x 41), which uses the explicit count path |
| `reg/dist/grip4/road/...` | dist | GRIP4 | distance to the road network |
| `reg/dist/smod/urban/...` | dist | GHS-SMOD | distance to settlements, reproduced by the distance example |
