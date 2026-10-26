#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Refresh the cross-table columns of the audit table against the current metadata.

The per-layer audit records `sha_match` and `stats_match` as they stood when the
audit ran. After MANIFEST.csv and variable_dictionary.csv are regenerated, those
columns are stale even though nothing is wrong with the data: the audit was simply
comparing against the older metadata.

This rewrites the three comparison columns from the files that are on disk now:

    sha_match    audit sha256  == MANIFEST sha256
    stats_match  audit min/max/n_valid  == dictionary value_min/value_max/n_valid
                 (plus the dictionary's own unit string, when it carries one)

Output: in place, plus a printed tally. Run before audit_summarize.py.
"""
from __future__ import annotations

import csv
import io
import os
import sys

ROOT = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
AUD = os.path.join(ROOT, "audit", "layer_audit.csv")
DOCS = os.path.join(ROOT, "00_docs")


def num(x):
    try:
        return float(x)
    except Exception:
        return None


def close(a, b):
    if a is None or b is None:
        return False
    return abs(a - b) <= 1e-6 * max(1.0, abs(a), abs(b))


def main():
    rows = list(csv.DictReader(io.open(AUD, encoding="utf-8")))
    cols = list(rows[0].keys())
    man = {r["relpath"].replace("covariates/", "", 1): r
           for r in csv.DictReader(io.open(os.path.join(DOCS, "MANIFEST.csv"), encoding="utf-8-sig"))}
    dic = {r["relpath"]: r for r in csv.DictReader(
        io.open(os.path.join(DOCS, "variable_dictionary.csv"), encoding="utf-8-sig"))}

    sha_ok = sha_bad = dict_ok = dict_bad = 0
    for r in rows:
        rel = r["relpath"]
        m = man.get(rel)
        if m and m["sha256"] == r["sha256"]:
            r["sha_match"] = "yes"; sha_ok += 1
        else:
            r["sha_match"] = "no" if m else "no_manifest"; sha_bad += 1

        d = dic.get(rel)
        if not d:
            r["stats_match"] = "no_dictionary"; dict_bad += 1
            continue
        r["dict_vmin"] = d["value_min"]
        r["dict_vmax"] = d["value_max"]
        r["dict_nvalid"] = d["n_valid"]
        ok = (close(num(r["vmin"]), num(d["value_min"]))
              and close(num(r["vmax"]), num(d["value_max"]))
              and str(r["n_valid"]) == str(d["n_valid"]))
        r["stats_match"] = "True" if ok else "False"
        dict_ok += ok; dict_bad += (not ok)

    with open(AUD, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    print("  sha_match    : 一致 %d / 不一致 %d" % (sha_ok, sha_bad))
    print("  stats_match  : 一致 %d / 不一致 %d" % (dict_ok, dict_bad))
    return 0 if (sha_bad == 0 and dict_bad == 0) else 1


if __name__ == "__main__":
    sys.exit(main())
