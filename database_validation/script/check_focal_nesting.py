#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Check that no focal layer carries values outside its own base layer's range.

A focal mean over a window is an average of base values, so it cannot leave the
base layer's global range. A violation therefore means either a broken window, a
wrong denominator, or a base layer that changed after the focal layer was built.

The comparison uses the per-layer min/max already recorded in audit/layer_audit.csv,
so it costs no raster reads and covers every focal layer in the delivery rather than
a sample. Layers whose base is not delivered (the glu1km landscape metrics exist only
at the four focal scales) are counted separately and not treated as failures.

Output: audit/focal_nesting.csv
"""
from __future__ import annotations

import csv
import io
import os
import re
import sys

ROOT = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
AUD = os.path.join(ROOT, "audit", "layer_audit.csv")
OUT = os.path.join(ROOT, "audit", "focal_nesting.csv")
FOC = re.compile(r"_f(\d+)\.tif$")


def main():
    rows = {r["relpath"]: r for r in csv.DictReader(io.open(AUD, encoding="utf-8"))}
    out, bad, nobase = [], 0, 0
    for rel, r in rows.items():
        m = FOC.search(rel)
        if not m:
            continue
        base_rel = rel[:m.start()] + ".tif"
        b = rows.get(base_rel)
        if not b:
            nobase += 1
            out.append({"focal": rel, "base": base_rel, "radius_m": m.group(1),
                        "status": "no_base_delivered"})
            continue
        lf, hf = float(r["vmin"]), float(r["vmax"])
        lb, hb = float(b["vmin"]), float(b["vmax"])
        tol = 1e-6 * max(1.0, abs(lb), abs(hb))
        ok = lf >= lb - tol and hf <= hb + tol
        bad += (not ok)
        out.append({"focal": rel, "base": base_rel, "radius_m": m.group(1),
                    "focal_vmin": lf, "focal_vmax": hf, "base_vmin": lb, "base_vmax": hb,
                    "status": "ok" if ok else "OUT_OF_BASE_RANGE"})
    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["focal", "base", "radius_m", "focal_vmin",
                                          "focal_vmax", "base_vmin", "base_vmax", "status"])
        w.writeheader()
        w.writerows(out)
    n = sum(1 for x in out if x["status"] in ("ok", "OUT_OF_BASE_RANGE"))
    print("  焦点层 %d 个；有基底 %d，无基底（仅以焦点交付）%d" % (len(out), n, nobase))
    print("  越出基底层值域: %d" % bad)
    print("  written:", OUT)
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
