# CHECO26 validation

The production inventory contains 21,788 rasters (183.2 GB). The proposed data deposit covers 21,710 layers (21,637 open and 73 noncommercial). Five HydroSHEDS layers are withheld for source licence terms. Three legacy h90m topology or ID layers and 70 degenerate GLU all-class patch layers are retained internally. The full raster deposit is pending.

## 2026-11-22 revision

MPI temperature triplets in five affected combinations are jointly warped from decoded source bands. The revised triplets have a maximum identity residual of 7.63 × 10⁻⁶ °C. The 27 future GDD ensembles use common eligible models across the three thresholds and agree with independent recomputation. GHS-SMOD includes classes 21, 22, 23 and 30. The four gridded feature distances match a second exact Euclidean transform. JRC water distance uses native maximum-extent pixel centres, verified in three regional source windows. The h90m upstream-cell elevation trio shares one cleaned 20-tile mosaic and obeys min ≤ mean ≤ max. Terrain uses Copernicus GLO-90 with EGM2008 heights. Derivatives use a complete 3×3 neighbourhood.

The production raster SHA-256 manifest, variable dictionary and provenance are generated together. Earlier independent full-pixel scans describe historical versions. The revised outputs have focused independent acceptance checks. The nine public sample files match their production counterparts byte for byte.

Native-tile replay was audited on all 48 legacy h90m rasters. Version 2.2 updates nine extrema and the sparse outlet flag. The 22 historical means are retained after a comparison against independently coverage-weighted values. Three direction or ID layers remain internal. Native input checksums are in `data/H90M_SOURCE_MANIFEST.csv`. The outlet flag increases from 18,551 to 18,557 valid 1 km cells (40 added, 34 removed). Nine extrema differ at a total of 13 cells. Eight groups satisfy min ≤ mean ≤ max throughout their common valid masks. Reprocessing and release selection preserve the legacy source terms.
