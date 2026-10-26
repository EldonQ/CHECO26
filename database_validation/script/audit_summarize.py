#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Summarise the per-layer audit into a verdict, a failure list and a JSON block.

Reads audit/layer_audit.csv (written by audit_data_quality.py) and produces

    audit/audit_summary.json     machine-readable verdict
    audit/audit_failures.csv     one row per layer that failed at least one check
    audit/theme_summary.csv      per-theme pass rates

A check that could not be evaluated counts as a failure, never as a pass.
"""
from __future__ import annotations

import collections
import csv
import json
import os
import sys

ROOT = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
AUD = os.path.join(ROOT, "audit")
SRC = os.path.join(AUD, "layer_audit.csv")

EXPECTED_LAYERS = 21110
EXPECTED_THEMES = 8


def num(x, default=None):
    try:
        return float(x)
    except Exception:
        return default


def check_layer(r):
    """Return a list of failure strings for one audited layer."""
    fails = []
    if r["open_ok"] != "True":
        fails.append("open: %s" % (r.get("error") or "unknown"))
        return fails
    if r["dtype"] != "float32":
        fails.append("dtype=%s" % r["dtype"])
    if r["nbands"] != "1":
        fails.append("nbands=%s" % r["nbands"])
    if num(r["nodata"]) != -9999.0:
        fails.append("nodata=%s" % r["nodata"])
    if r["dims_ok"] != "True":
        fails.append("dims=%sx%s" % (r["width"], r["height"]))
    if r["transform_ok"] != "True":
        fails.append("transform differs from template")
    if r["crs_ok"] != "True":
        fails.append("crs differs from template")
    if r["storage_ok"] != "True":
        fails.append("storage compress=%s tiled=%s block=%s"
                     % (r["compress"], r["tiled"], r["block"]))
    # A blank count means the audit could not evaluate the check. Reading it as zero
    # would turn "not checked" into "passed", so a blank is a failure of its own.
    for key, label in (("n_nonfinite", "non_finite"),
                       ("n_outside_mask", "valid_cells_outside_mask"),
                       ("n_below", "below_range"),
                       ("n_above", "above_range")):
        c = num(r.get(key), None)
        if c is None:
            fails.append("%s=unreadable" % label)
        elif c > 0:
            if key == "n_below":
                fails.append("%s=%s (<%s)" % (label, r[key], r["range_lo"]))
            elif key == "n_above":
                fails.append("%s=%s (>%s)" % (label, r[key], r["range_hi"]))
            else:
                fails.append("%s=%s" % (label, r[key]))
    if r.get("range_ok", "") != "True":
        fails.append("range_unverifiable=%s" % (r.get("range_ok") or "blank"))
    if r["stats_match"] not in ("True",):
        fails.append("dictionary_mismatch min %s/%s max %s/%s n %s/%s"
                     % (r["vmin"], r["dict_vmin"], r["vmax"],
                        r["dict_vmax"], r["n_valid"], r["dict_nvalid"]))
    if r["sha_match"] != "yes":
        fails.append("manifest_sha=%s" % r["sha_match"])
    return fails


def main():
    with open(SRC, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    print("audited layers: %d" % len(rows), flush=True)

    fails = []
    per_check = collections.Counter()
    for r in rows:
        fl = check_layer(r)
        if fl:
            fails.append({"relpath": r["relpath"], "n_failures": len(fl),
                          "failures": " | ".join(fl)})
            for one in fl:
                per_check[one.split(":")[0].split("=")[0]] += 1

    # per theme
    th = collections.defaultdict(lambda: {"n": 0, "fail": 0})
    for r in rows:
        t = r["theme"]
        th[t]["n"] += 1
        if check_layer(r):
            th[t]["fail"] += 1

    dupe = collections.Counter(r["sha256"] for r in rows)
    dup_hash = {h: c for h, c in dupe.items() if c > 1}
    dup_layers = sum(dup_hash.values()) - len(dup_hash)

    summary = {
        "layers_expected": EXPECTED_LAYERS,
        "layers_audited": len(rows),
        "layers_complete": len(rows) == EXPECTED_LAYERS,
        "themes": len(th),
        "themes_expected": EXPECTED_THEMES,
        "layers_failing": len(fails),
        "layers_passing": len(rows) - len(fails),
        "checks": {
            "open": sum(1 for r in rows if r["open_ok"] == "True"),
            "float32": sum(1 for r in rows if r["dtype"] == "float32"),
            "nodata_minus9999": sum(1 for r in rows if num(r["nodata"]) == -9999.0),
            "grid_invariants": sum(1 for r in rows
                                   if r["dims_ok"] == "True" and r["transform_ok"] == "True"
                                   and r["crs_ok"] == "True"),
            "storage": sum(1 for r in rows if r["storage_ok"] == "True"),
            "no_valid_outside_mask": sum(1 for r in rows
                                         if num(r.get("n_outside_mask"), None) == 0),
            "no_non_finite": sum(1 for r in rows
                                 if num(r.get("n_nonfinite"), None) == 0),
            "within_expected_range": sum(1 for r in rows
                                         if r.get("range_ok") == "True"
                                         and num(r["n_below"], 0) == 0
                                         and num(r["n_above"], 0) == 0),
            "dictionary_agrees": sum(1 for r in rows if r["stats_match"] == "True"),
            "manifest_agrees": sum(1 for r in rows if r["sha_match"] == "yes"),
        },
        "failure_kinds": dict(per_check),
        "duplicate_hash_groups": len(dup_hash),
        "layers_sharing_a_hash": dup_layers,
        "distinct_hashes": len(dupe),
        "bytes_total": sum(int(r["bytes"]) for r in rows if r["bytes"]),
        "per_theme": {k: v for k, v in sorted(th.items())},
    }

    with open(os.path.join(AUD, "audit_summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    with open(os.path.join(AUD, "audit_failures.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["relpath", "n_failures", "failures"])
        w.writeheader()
        w.writerows(fails)

    with open(os.path.join(AUD, "theme_summary.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["theme", "layers", "failing", "pass_rate_pct"])
        for k, v in sorted(th.items()):
            w.writerow([k, v["n"], v["fail"],
                        round(100 * (1 - v["fail"] / v["n"]), 3) if v["n"] else ""])

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if fails:
        print("\n%d layers failed at least one check; first 20:" % len(fails))
        for x in fails[:20]:
            print("  %-70s %s" % (x["relpath"][-70:], x["failures"][:120]))
    else:
        print("\nno layer failed any check")


if __name__ == "__main__":
    main()
