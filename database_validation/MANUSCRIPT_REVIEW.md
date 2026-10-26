# Manuscript review record

Before submission the manuscript was put through a simulated three-seat review: a
methodology/reproducibility seat, a domain/novelty seat, and a devil's advocate whose
brief was to construct the strongest honest case against publication. The seats were run
independently and did not see each other's reports.

This file records what they said and what was done about it. It is here because the
manuscript claims things about this archive, and a reader is entitled to know which of
those claims survived an adversarial reading and which did not.

## Verdicts

| Seat | Verdict |
|---|---|
| Methodology | The engineering scaffolding is stronger than most data descriptors, but the archive was not reproducible from the methods as written: the boundary vector, the parameter file and the source versions were unreferenced, and the code was a moving GitHub URL |
| Domain / novelty | Between incremental and substantive: substantive if re-centred, incremental as framed. The strongest case is the 3,982 areal-proportion layers and the provenance and licence infrastructure, not the layer count |
| Devil's advocate | The headline counts operations rather than information: 18,440 of 21,110 layers come from one land-use product and 7,060 layers are byte-duplicates of a sibling. Its strongest single objection was a contradiction inside the manuscript (see finding 1) |

## Findings accepted and fixed

Numbers in brackets are the sections of `README.md` that carry the evidence.

1. **A factual contradiction.** The manuscript said all four topographic layers were
   reprojected sources, and elsewhere that aspect and the terrain ruggedness index were
   derived here. `provenance_table.csv` settles it: both are produced by
   `08_derive_topo_vege.R` with Horn (1981) and Riley et al. (1999). The derived/direct
   split changed from 20,314 / 796 to 20,316 / 794. [Ten errors, row 1-2]
2. **The pipeline could not be re-executed.** Three production inputs were unreferenced:
   the boundary vector, the parameter file, and the source versions. The parameter file
   is `pipeline_r/config.yaml` and always was deposited; the manuscript now names it. The
   mask is deposited as `data/mask_china.tif`, so the masking step reproduces without the
   vector, which is not redistributed. Source versions are recorded in `source_citation`,
   and the releases that differ from their describing papers are now stated.
3. **Two unrecorded decisions.** The mask is applied to whole 1 km cells *after*
   aggregation, so a boundary cell carries signal from source pixels beyond the national
   boundary; and the areal proportions use the non-background area as denominator, which
   is why they close to 1. Both are now stated, along with the consequence for the
   boundary ring.
4. **Validation scope overstated.** The resampling check covers three representative
   layers, not every theme, and the text said "per theme".
5. **The independent toolchain was unnamed.** It is `audit_data_quality.py`, Python with
   rasterio, ten checks over all 21,110 layers; the text now says so.
6. **The manifest figure was wrong.** 21,118 rows are 172.46 GB; 170.91 GB is the 21,110
   active layers. [Ten errors, row 5]
7. **A sample described as random is systematic.** [Ten errors, row 6]
8. **The population omission was not defended.** The old text explained only why a
   LandScan stack was withdrawn, not why the archive carries no population at all. It is
   now stated as a scope decision, with the note that GHS-SMOD and the human footprint
   contain population components but are not population.
9. **One hundred land-cover claims weakened.** Only CLCD is observation-based; the other
   two products are harmonised, and part of their agreement is inherited rather than
   observed. The manuscript now says which product answers which question.
10. **Figure numbering did not match the files.** Figures 3-7 were named `fig02_*` to
    `fig06_*` and there was no `fig07`. [Ten errors, row 10]

## Findings rejected, with evidence

**"Figure 2's 16,990 scenario layers do not reconcile with Table 1."** The reviewer
computed 16,000 + 540 + 252 + 252 = 17,044 and concluded the figure was wrong. Recomputed
from the delivered tree, the scenario family is 16,000 (hlu1km future) + 486 (the scenario
part of glu1km; the other 54 of its 540 layers are the 2020 baseline) + 252 + 252 =
16,990. The figure is correct.

## Findings that would need new data

Three requests are agreed in principle but are outside what this delivery can answer
without producing more layers:

- a cross-product disagreement or consensus layer for the three land-use products, rather
  than a statement that their disagreement is information;
- absolute-error distributions per layer for the resampling check, rather than a
  three-layer demonstration;
- a population layer at 1 km (GHS-POP or WorldPop), which would change every count in the
  manuscript and require a full re-validation.

These are recorded so that a reader does not mistake silence for a claim that they are
unnecessary.

## Items that depend on the author team

The author list, affiliations, contributions, acknowledgements, funding and the repository
DOI are not part of this repository and are not settled in the manuscript yet; the
placeholder sections say so rather than being silently blank.
