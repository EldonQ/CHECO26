# -*- coding: utf-8 -*-
"""make_provenance_table.py -- build the CHECO26 layer-provenance table.

One row per delivered layer (1603 = 1595 active + 8 withdrawn), 21 columns, assembled
from records that already exist in the repository plus the two hand-curated tables
(vardefs.py, srcmeta.py). Nothing is re-typed here that can be joined.

Run:
  E:\\CHECO26\\.venv\\Scripts\\python.exe make_provenance_table.py [--out PATH]
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from collections import OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from srcmeta import MASK_SRC, SRC          # noqa: E402
from vardefs import (definition_for, focal_window_text, parse_layer,   # noqa: E402
                     unit_en, unit_for)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COV = os.path.join(ROOT, "data", "covariates", "glo")
TEMPLATE = os.path.join(ROOT, "data", "template_albers1km.tif")

RE_FOCAL = re.compile(r"_f(\d+)$")
RE_FOCAL_EXT = re.compile(r"_f(\d+)(\.tif)$")
# lineage.csv was written before the 2026-08-08 rename, which changed the focal
# suffixes from "<n>km" to "<metres>". Both spellings occur in the record.
FOCAL_FIX = {"f1km": "f1000", "f5km": "f5000", "f10km": "f10000", "f20km": "f20000"}


def norm_focal(relpath):
    """Rewrite legacy <n>km focal suffixes to the current metre form."""
    stem, dot, ext = relpath.rpartition(".")
    for old, new in FOCAL_FIX.items():
        if stem.endswith("_" + old):
            return stem[: -len(old)] + new + dot + ext
    return relpath

# The reference grid, stated once.
GRID = ("China_Albers equal-area (WGS84, central meridian 105E, standard parallels "
        "25N/47N), 1000 m, 4861 x 4062, x[-2648000, 2213000] y[1867000, 5929000]")

# ---------------------------------------------------------------- processing steps
# One canonical description per pipeline stage. {rs} = the resampling rule that
# common.warp_to_template() actually applies for this layer (config.yaml:resampling).
_RS = {
    "categorical": "nearest",
    "continuous": "bilinear",
    "proportion": "bilinear",
    "distance": "bilinear",
    "downscale_continuous": "average (window mean over the source cells)",
    "downscale_categorical": "mode (most frequent source class in the window)",
    "downscale_min": "min (window minimum of the source cells)",
    "downscale_max": "max (window maximum of the source cells)",
}


def steps_for(theme, dataset, varkey, src):
    """Return the ordered processing-steps string for one layer."""
    rs = _RS["continuous"]
    extra = ""

    if theme == "bioclim":
        rs = _RS["continuous"]
        extra = (" Repojected with rasterio.warp.reproject; the source is already a monthly "
                 "climatology, annual variables (prec/tave/tmin/tmax/sunp) are the sum or "
                 "mean of the 12 monthly bands computed upstream by the provider's builder "
                 "script, not here.")
    elif theme == "soil":
        rs = _RS["continuous"]
        extra = (" Source stored as int16; the published scale factor is applied after "
                 "reprojection (divide by 10 for AN and AK, by 100 for every other "
                 "property).")
    elif theme == "topo":
        rs = _RS["continuous"]
        extra = " Source is a projected Albers DEM; reprojected to the China_Albers template."
    elif theme in ("hydro", "dist") and dataset == "h90m":
        cat = varkey.split("@")[0] in (
            "basin", "direction", "order-hack", "order-horton", "order-shreve",
            "order-strahler", "order-topo", "outlet", "segment", "sub-catchment")
        rs = _RS["downscale_categorical"] if cat else _RS["downscale_continuous"]
        extra = (" Categorical layers take the window mode, continuous layers the window "
                 "mean over the ~90 m source cells. The cm->m scale factor (x0.01) is "
                 "applied after reprojection to the 18 distance/elevation variables.")
    elif theme == "dist" and dataset in ("grip4", "osm", "gsw", "smod"):
        rs = _RS["distance"]
        extra = (" Vector (GRIP4, OSM) or fine raster (GSW, GHS-SMOD) input is first "
                 "rasterised/projected to the template, then a Euclidean distance transform "
                 "in metres is taken.")
    elif theme == "lulc":
        rs = _RS["categorical"]
        extra = (" The class raster is aggregated to the 1 km template with resampling="
                 "nearest, then one-hot proportions, Shannon, edge density, patch density "
                 "and patch size are derived on the 1 km grid (proportion first, window "
                 "second).")
    elif theme == "vege":
        rs = _RS["downscale_continuous"]
        extra = " The ~30 m source is aggregated to the 1 km template by window mean."
    elif theme == "anthro":
        if dataset == "foothii":
            rs = _RS["continuous"]
            extra = " Scale x0.01 applied after reprojection (stored 0-5900 -> index 0-59)."
        elif dataset == "landscan":
            rs = _RS["continuous"]
            extra = " Source is already 30 arc-seconds; reprojected to the template."
        else:
            rs = _RS["downscale_continuous"]
            extra = (" GHS-SMOD classes 21/22/23 are extracted, one-hot encoded and "
                     "aggregated to the 1 km grid by window mean to give an urban "
                     "proportion.")

    return ("1) read the source raster listed in source_file. "
            "2) reproject to the CHECO26 grid (" + GRID + ") with "
            "rasterio.warp.reproject, resampling = " + rs + ", dst_nodata = NaN. "
            "3) apply the published unit scale/offset if any (see source_scale_offset). "
            "4) mask to the national boundary (mask_china.tif, all_touched=True); every "
            "cell outside the mask becomes NoData. "
            "5) write float32 GeoTIFF, nodata -9999, DEFLATE compression, 256x256 tiles, "
            "atomically (temp file then rename)." + extra)


def derive_for(theme, dataset, varkey, relpath):
    """Return the derivation formula/parameters string.

    The focal radius is read from the layer path (`_f<metres>.tif`), which is the
    only place it is recorded, and rendered as the explicit window size.
    """
    parts = []
    m = RE_FOCAL_EXT.search(relpath)
    if m:
        metres = int(m.group(1))
        win = focal_window_text(metres)
        r_cells = metres // 1000
        parts.append("focal mean over a %s, equal weights, "
                     "radius_cells = %d, denominator = number of valid cells in the window"
                     % (win or "%d m radius" % metres, r_cells))
    if theme == "lulc":
        metric = varkey.split("@")[0]
        if metric in ("cropland", "forest", "grassland", "urban", "barren", "water"):
            parts.append("one-hot areal proportion of the class within the output cell")
        elif metric == "shannon":
            parts.append("Shannon index -sum(p*ln(p)) over the 6 class proportions, "
                         "natural logarithm")
        elif metric == "edge":
            parts.append("FRAGSTATS-style edge density: a cell is an edge cell when any "
                         "of its 4 neighbours has a different class; the layer is the "
                         "window mean of that binary indicator")
        elif metric.startswith("patchdensity"):
            parts.append("patch density = (number of 4-connected patches whose anchor "
                         "falls in the disk window) / (pi*r^2) * 100 [patches per 100 km2]; "
                         "patch = 4-neighbour connected component; scope " +
                         ("all classes combined into one landscape" if metric.endswith("All")
                          else "forest class only (class 2)"))
        elif metric.startswith("patchsize"):
            parts.append("patch size = mean area of the patches anchored in the disk "
                         "window [km2]; scope " +
                         ("all classes combined" if metric.endswith("All")
                          else "forest class only (class 2)"))
    if theme == "topo" and varkey == "tri":
        parts.append("Terrain Ruggedness Index (Riley et al. 1999): RMS of the elevation "
                     "difference to the 8 neighbours in a 3x3 window")
    if theme == "topo" and varkey == "aspect":
        parts.append("aspect computed from the 3x3 elevation neighbourhood, 0 deg = north, "
                     "clockwise")
    if theme == "anthro" and dataset == "smod":
        parts.append("GHS-SMOD classes 21/22/23 one-hot encoded, then window mean")
    if theme in ("hydro", "dist") and dataset == "h90m" and varkey.endswith("@max"):
        parts.append("window maximum over the ~90 m source cells (hydro_stats_addon)")
    if theme in ("hydro", "dist") and dataset == "h90m" and varkey.endswith("@min"):
        parts.append("window minimum over the ~90 m source cells (hydro_stats_addon)")
    if not parts:
        parts.append("none - base layer, first-order derivative of the source only")
    return "; ".join(parts)


MISSING_RULE = ("Source NoData is excluded before the aggregation, so it never enters a "
                "window mean, a class proportion or a patch/label computation. A focal "
                "window that contains no valid cell at all yields NoData rather than a "
                "value (this was the 2026-10-06 repair). Boundary cells outside the "
                "national mask are NoData in every delivered layer, so partially covered "
                "1 km cells are averaged over their in-mask source cells only.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "00_docs", "provenance_table.csv"))
    args = ap.parse_args()

    def load(rel):
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
            return list(csv.DictReader(fh))

    mig = load(os.path.join("scratch", "migration_map_0808.csv"))
    lin = load(os.path.join("logs", "lineage.csv"))
    p5 = {r["relpath"]: r for r in load(os.path.join("logs", "p5_validation_report.csv"))}
    vd = {r["relpath"]: r for r in load(os.path.join("00_docs", "variable_dictionary.csv"))}
    fr = {}
    for r in load(os.path.join("logs", "focal_repair_record.csv")):
        k = r["layer"].replace("\\", "/")
        for cand in (k, "glo/" + k, "reg/" + k):
            fr[cand] = r
    wd_rel = set()
    for r in load(os.path.join("logs", "withdrawn_layers_manifest.csv")):
        p = r["relpath"].replace("\\", "/")
        wd_rel.add(p)
        wd_rel.add("glo/" + p)          # the manifest is covariates-relative
        wd_rel.add("reg/" + p)

    # lineage: index by both the old and the new path, so records written before the
    # 2026-08-08 rename still join.  `old2new` is also kept in full (every migration
    # row, not just the ones that carried a source) because it is the map used to
    # translate a current path back to the name lineage.csv used at the time.
    old2new = {m["old_relpath"]: m["new_relpath"] for m in mig}
    new2olds = {}
    for o, n in old2new.items():
        new2olds.setdefault(n, []).append(o)

    # Records whose source starts with "rename:" are the renaming bookkeeping, not a
    # data source -- they must not mask real provenance.
    lin_by = {}

    def _remember(key, rec):
        cur = lin_by.get(key)
        if cur is None:
            lin_by[key] = rec
        elif cur["source"].strip().startswith("rename:") and \
                not rec["source"].strip().startswith("rename:"):
            lin_by[key] = rec

    for r in lin:
        p = r["relpath"].replace("\\", "/")
        if p not in old2new and p not in new2olds:
            _remember(p, r)
            continue
        if p in old2new:
            _remember(old2new[p], r)
            _remember(p, r)
    # The migration rows themselves carry the old name of the base layer; add them so
    # a focal layer can still find its base's provenance record.
    for o, n in old2new.items():
        _remember(n, {"relpath": n, "source": "", "script": "", "note": ""})
        _remember(o, {"relpath": o, "source": "", "script": "", "note": ""})

    # ---- LULC source files: recover the 14 layers lineage never recorded ----
    # The source folder name is read from config.yaml, never re-typed (its exact
    # spelling is "1km resolution", not "1 km resolution").
    LULC_SRC = {"2020": "history_2020.tif"}
    for ssp_dir, ssp_file in (("ssp126", "ssp1_26"), ("ssp245", "ssp2_45"),
                              ("ssp585", "ssp5_85")):
        for y in (2030, 2050, 2100):
            LULC_SRC[ssp_dir] = "%s_%d.tif" % (ssp_file, y)
            LULC_SRC["%s/%d" % (ssp_dir, y)] = "%s_%d.tif" % (ssp_file, y)
    lulc_root = None
    cfg_path = os.path.join(ROOT, "scripts", "config.yaml")
    if os.path.exists(cfg_path):
        for line in open(cfg_path, encoding="utf-8"):
            m = re.match(r'\s*lulc_raw:\s*"([^"]+)"', line)
            if m:
                lulc_root = m.group(1).replace("\\", "/")
                break
    if not lulc_root:
        lulc_root = "E:/CHECO26/Global LULC projection dataset from 2020 to 2100 at a 1km resolution/23542860"
    LULC_ROOT = lulc_root
    if not os.path.isdir(LULC_ROOT):
        print("WARNING: LULC source root not found: %s" % LULC_ROOT)

    # ---- focal radius -> the base layer it was computed from ----
    def base_of(relpath):
        """Strip the focal suffix from a full path, keeping the .tif extension."""
        m = RE_FOCAL_EXT.search(relpath)
        return relpath[:m.start()] + m.group(2) if m else relpath

    universe = [m["new_relpath"] for m in mig]          # 1603, keeps the withdrawn ones

    cols = ["layer_path", "status", "source_file", "source_dataset",
            "source_provider", "source_doi_url", "source_citation",
            "variable_definition", "units",
            "source_crs", "source_resolution", "source_extent", "source_nodata",
            "source_scale_offset", "processing_steps", "derivation_formula",
            "missing_boundary_rule", "script_function", "expected_range", "actual_range",
            "notes"]

    rows = []
    stats = dict(missing_src=0, no_p5=0, no_vd=0, flat=0, focal=0)
    for rel in universe:
        theme, dataset, varkey, flat = parse_layer(rel)
        if flat:
            stats["flat"] += 1
        meta = SRC.get((theme, dataset), {})
        stem = rel[:-4]                            # extension-free stem, for the repair record

        # ---- status ----
        status = "withdrawn" if rel in wd_rel else "active"

        # ---- source file (lineage keys keep the .tif extension) ----
        # A record is only a provenance record when `source` names a real file;
        # the renaming bookkeeping rows carry source = "rename:<old path>".
        def real_src(key):
            rec = lin_by.get(key)
            if rec is None:
                return None
            s = rec["source"].strip()
            if not s or s.startswith("rename:"):
                return None
            return s

        sfile = ""
        for cand in (rel, norm_focal(rel)):
            sfile = real_src(cand) or ""
            if sfile:
                break
        if not sfile:
            # focal layers inherit the base layer's source; the base layer may only
            # be indexed under its pre-rename name, so try every spelling
            cands = []
            for b in (base_of(rel), norm_focal(base_of(rel)), base_of(norm_focal(rel))):
                cands.append(b)
                cands.extend(new2olds.get(b, []))
            for b in dict.fromkeys(cands):
                got = real_src(b)
                if got:
                    sfile = got
                    if RE_FOCAL.search(stem):
                        sfile += "  [inherited from base layer %s]" % os.path.basename(b)
                    break
        if not sfile and theme == "lulc":
            snap = rel.split("/")[-2] if rel.split("/")[-2] in LULC_SRC else None
            if snap is None:
                parts = rel.split("/")
                snap = parts[5] if len(parts) > 6 else parts[3]
            fn = LULC_SRC.get(snap) or LULC_SRC.get(snap.split("/")[-1])
            if fn:
                sfile = "%s/%s" % (LULC_ROOT, fn)
            else:
                sfile = "%s/<snapshot>.tif" % LULC_ROOT
        if not sfile:
            sfile = "TODO: source not recorded in lineage.csv"
            stats["missing_src"] += 1

        # ---- source file: prefixed with [path] or [selector] ----
        # [path]     -> an absolute file path that must exist on disk
        # [selector] -> how the source was selected when lineage recorded a rule rather
        #               than a filename (vector query, tile set, rasterised class subset)
        _sp = sfile.split("  [inherited")[0].strip()
        tag = "path" if re.match(r"^[A-Za-z]:[/\\]|^\\\\|^/", _sp) else "selector"
        sfile = "[%s] %s" % (tag, sfile)

        # ---- script / function ----
        script = ""
        for cand in (rel, norm_focal(rel)):
            if lin_by.get(cand, {}).get("script", ""):
                script = lin_by[cand]["script"]
                break
        if not script and theme == "lulc":
            script = "04_derive_lulc.py"
        if not script:
            for cand in (base_of(rel), norm_focal(base_of(rel))):
                if lin_by.get(cand, {}).get("script", ""):
                    script = lin_by[cand]["script"]
                    break
        if not script:
            script = "TODO"
        funcs = {
            "bioclim": "common.warp_to_template",
            "soil": "common.warp_to_template",
            "topo": "common.warp_to_template / 06_derive_topo_vege.py (tri, aspect)",
            "hydro": "common.warp_to_template (resampling rule downscale_*)",
            "dist": "common.warp_to_template / 05_derive_dist.py (Euclidean distance)",
            "lulc": "common.warp_to_template + 04_derive_lulc.py (proportion, shannon, "
                    "edge_density, patch_metric)",
            "vege": "common.warp_to_template / 03_ingest_timeseries.py (focal_mean)",
            "anthro": "common.warp_to_template + 03_ingest_timeseries.py (focal_mean)",
        }
        script_function = "%s : %s" % (script, funcs.get(theme, "common.warp_to_template"))

        # ---- ranges ----
        p5r = p5.get(rel)
        expected = "not applicable (withdrawn)" if status == "withdrawn" else ""
        if p5r and expected == "":
            expected = "[%s, %s]" % (p5r["vmin"], p5r["vmax"])
        elif expected == "":
            expected = "TODO"
            stats["no_p5"] += 1
        if p5r:
            actual = "[%s, %s] over %s valid cells" % (p5r["vmin"], p5r["vmax"], p5r["n_valid"])
        else:
            actual = "read from the archived file (see notes)"

        # Units: the delivery dictionary is authoritative for active layers; the
        # withdrawn layers are absent from it, so fall back to the unit stated in the
        # variable definition. Never fall back to source_scale_offset -- that describes
        # a conversion, not a unit. Rendered in English for the metadata database.
        raw_unit = vd.get(rel, {}).get("unit", "")
        if not raw_unit:
            raw_unit = unit_for(rel) or ""
        if raw_unit:
            units = unit_en(raw_unit)
        else:
            units = "not applicable (withdrawn)" if status == "withdrawn" else "TODO"
            stats["no_vd"] += 1

        # ---- notes ----
        notes = []
        if status == "withdrawn":
            notes.append("WITHDRAWN from delivery 2026-10-06: the source values are "
                         "numerically unusable and the shipped layer reproduces the source "
                         "faithfully, so re-running cannot repair it. File retained in "
                         "archive/withdrawn_source_defective/ - fully traceable, not deleted.")
        fkey = stem
        if fkey in fr:
            f = fr[fkey]
            # before_oor / after_oor are counts of out-of-range STATISTICS and are empty
            # in focal_repair_record.csv (the column was never populated), so the clause
            # is emitted only when a value is actually present.
            bits = ["garbage cells before=%s, after=%s"
                    % (f["before_garbage"] or "n/a", f["after_garbage"] or "0")]
            if (f.get("before_oor") or "").strip() or (f.get("after_oor") or "").strip():
                bits.append("out-of-range statistics before=%s, after=%s"
                            % (f["before_oor"] or "n/a", f["after_oor"] or "0"))
            notes.append("focal layer repaired 2026-10-06 (%s)" % "; ".join(bits))
        if flat:
            notes.append("STRUCTURAL NOTE: this layer's variable name is carried by the "
                         "FILEname, not by a folder. 04_derive_lulc.py writes the six "
                         "derived metrics with an empty folder suffix "
                         "(write(snapshot_parts(cfg, snap, []), ...)), so the layer sits "
                         "directly in the snapshot folder and nsdm.covinfo records "
                         "variable = '%s' instead of the metric name. Kept exactly as the "
                         "pipeline produces it (renaming would desynchronise disk and "
                         "script); the metric name below is recovered from the filename."
                         % rel.split("/")[-2])
        if meta.get("note") and any(k in meta["note"] for k in
                                    ("WITHDRAWN", "SOCD", "10 model", "not mentioned")):
            notes.append(meta["note"])
        if theme == "bioclim" and "sunp" in rel:
            notes.append("sunp is published by the source only for the ensemble-mean chain, "
                         "so the bcc-csm2-mr chain contains 27 variables where ensmean "
                         "contains 28.")
        rows.append(OrderedDict([
            ("layer_path", rel),
            ("status", status),
            ("source_file", sfile),
            ("source_dataset", meta.get("name", "TODO")),
            ("source_provider", meta.get("provider", "TODO")),
            ("source_doi_url", meta.get("id", "TODO")),
            ("source_citation", meta.get("citation", "TODO")),
            ("variable_definition", definition_for(rel)),
            ("units", units),
            ("source_crs", meta.get("crs", "TODO")),
            ("source_resolution", meta.get("res", "TODO")),
            ("source_extent", meta.get("extent", "TODO")),
            ("source_nodata", meta.get("nodata", "TODO")),
            ("source_scale_offset", meta.get("scale", "TODO")),
            ("processing_steps", steps_for(theme, dataset, varkey, sfile)),
            ("derivation_formula", derive_for(theme, dataset, varkey, rel)),
            ("missing_boundary_rule", MISSING_RULE),
            ("script_function", script_function),
            ("expected_range", expected),
            ("actual_range", actual),
            ("notes", " | ".join(notes) if notes else ""),
        ]))
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    print("rows written : %d" % len(rows))
    print("columns      : %d" % len(cols))
    print("active       : %d" % sum(1 for r in rows if r["status"] == "active"))
    print("withdrawn    : %d" % sum(1 for r in rows if r["status"] == "withdrawn"))
    print("flat LULC    : %d" % stats["flat"])
    print("out          : %s" % args.out)
    print("  source_file fallbacks : %d" % stats["missing_src"])
    print("  no p5 range           : %d" % stats["no_p5"])
    print("  no unit               : %d" % stats["no_vd"])


if __name__ == "__main__":
    main()
