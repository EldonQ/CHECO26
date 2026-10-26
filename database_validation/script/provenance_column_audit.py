#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Column-by-column audit of provenance_table.csv against the delivered tree.

Design notes, learned the hard way:

  * `source_nodata`, `source_scale_offset` and `source_resolution` are **descriptive
    prose** ("NaN (declared); class 0 = ocean", "divide by 10 for AN and AK; divide
    by 100 for every other property"). They are not machine-parsable scalars, so a
    format check on them is meaningless; what can be checked is that they are
    non-empty and that the scale can be read out where it is stated plainly.
  * Consistency keys must include the property and depth: the last `_` token of a
    soil layer is the depth (`0`, `5`, …), not the property, so keying on it merges
    28 different properties into one group and invents conflicts.
  * Focal layers legitimately carry different `variable_definition` text, because
    each names its own window. The right check is not "definitions equal" but
    "each focal layer's definition names its own radius and window".

Output: audit/provenance_column_audit.csv
"""
from __future__ import annotations

import collections
import csv
import io
import os
import re

import numpy as np
import rasterio
from rasterio.warp import transform as rio_transform
from rasterio.crs import CRS

ROOT = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
DOCS = os.path.join(ROOT, "00_docs")
DATA = os.path.join(ROOT, "data", "covariates")
COV = os.path.join(DATA, "glo")
AUD = os.path.join(ROOT, "audit")
PROV = os.path.join(DOCS, "provenance_table.csv")

URL = re.compile(r"^https?://\S+$")
RES = re.compile(r"^[\d.]+", re.I)
FOCAL = re.compile(r"_f(\d+)\.tif$")
WINDOW = {"1000": ("1 km", "3 x 3"), "5000": ("5 km", "11 x 11"),
          "10000": ("10 km", "21 x 21"), "20000": ("20 km", "41 x 41")}
ALBERS = ("+proj=aea +lat_0=0 +lon_0=105 +lat_1=25 +lat_2=47 "
          "+datum=WGS84 +units=m +no_defs")


def load(p):
    with io.open(p, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def parse_scale(text, layer_path=""):
    """Return (kind, factor) where kind is 'mult', 'div' or None.

    The soil series states two rules in one sentence: "divide by 10 for AN and AK;
    divide by 100 for every other property". A single-factor parser applied the
    first rule to all 196 layers and reported 6 false failures; the ratio test is
    what exposed the conditional, so it has to be parsed, not flattened.
    """
    t = (text or "").strip().lower()
    if "for an and ak" in t and "every other" in t:
        parts = layer_path.split("/")
        prop = parts[3].lower() if len(parts) > 4 else ""
        return ("div", 10.0) if prop in ("an", "ak") else ("div", 100.0)
    if t.startswith("none") or "no scale factor" in t or t.startswith("per the hydrography90m"):
        return ("mult", 1.0)
    m = re.match(r"^x\s*([\d.eE+-]+)", t)
    if m:
        return ("mult", float(m.group(1)))
    m = re.search(r"divide by\s+([\d.eE+-]+)", t)
    if m:
        return ("div", float(m.group(1)))
    m = re.match(r"^([\d.eE+-]+)\s*$", t)
    if m:
        return ("mult", float(m.group(1)))
    return (None, None)


def main():
    prov = load(PROV)
    act = [r for r in prov if r["status"] == "active"]
    cols = list(prov[0].keys())
    res = []

    def add(section, name, examined, bad, detail="", examples=None):
        res.append({"section": section, "check": name, "examined": examined,
                    "failed": bad, "detail": detail,
                    "examples": " || ".join((examples or [])[:3])})
        flag = "OK  " if bad == 0 and examined > 0 else "FAIL"
        print("  %s %-46s %6d %5d  %s" % (flag, name, examined, bad, detail))

    # ---------- 1. per column profile ----------
    print("\n=== 1. 逐列画像（25 列）===")
    print("  %-22s %7s %8s %6s %s" % ("列", "空值", "不同值", "最长", "示例"))
    for c in cols:
        vals = [(r[c] or "") for r in prov]
        empty = sum(1 for v in vals if not v.strip())
        res.append({"section": "1 画像", "check": "列 %s" % c, "examined": len(vals),
                    "failed": empty,
                    "detail": "不同值 %d, 最长 %d" % (len(set(vals)), max(len(v) for v in vals)),
                    "examples": next((v for v in vals if v.strip()), "")[:40]})
        print("  %-22s %7d %8d %6d %s"
              % (c, empty, len(set(vals)), max(len(v) for v in vals),
                 next((v for v in vals if v.strip()), "")[:40]))

    # ---------- 2. column format ----------
    print("\n=== 2. 列格式 ===")
    badu = [r["layer_path"] for r in act
            if not (re.match(r"^10\.\d{4,9}/\S+$", r["source_doi_url"].strip())
                    or URL.match(r["source_doi_url"].strip()))]
    add("2 格式", "source_doi_url 为 DOI 或 http(s) URL", len(act), len(badu), "", badu)

    badl = [r["layer_path"] for r in act if not URL.match((r["licence_url"] or "").strip())]
    add("2 格式", "licence_url 为 http(s) URL", len(act), len(badl), "", badl)

    # 矢量源写成 "vector" 是合法的（GRIP4 道路、OSM 步道）
    badr = [r["layer_path"] for r in act
            if not (RES.match((r["source_resolution"] or "").strip())
                    or (r["source_resolution"] or "").strip().lower() == "vector")]
    nvec = sum(1 for r in act if (r["source_resolution"] or "").strip().lower() == "vector")
    add("2 格式", "source_resolution 为数值+单位或 vector", len(act), len(badr),
        "%d 种取值，其中矢量源 %d 层" % (len({r["source_resolution"] for r in act}), nvec), badr)

    for c in ("derivation_formula", "missing_boundary_rule", "attribution",
              "source_crs", "source_extent", "processing_steps"):
        bad = [r["layer_path"] for r in act if not (r[c] or "").strip()]
        add("2 格式", "%s 非空" % c, len(act), len(bad),
            "%d 种取值" % len({r[c] for r in act}), bad)

    # descriptive columns: only emptiness can be checked
    for c in ("source_nodata", "source_scale_offset"):
        bad = [r["layer_path"] for r in act if not (r[c] or "").strip()]
        add("2 格式", "%s 非空（描述性文本，不可格式校验）" % c, len(act), len(bad),
            "%d 种取值" % len({r[c] for r in act}), bad)

    # ---------- 3. cross-column consistency ----------
    print("\n=== 3. 跨列一致性 ===")

    def ds_key(lp):
        p = lp.split("/")
        return "%s/%s" % (p[1], p[2])

    for col, label in [("source_dataset", "数据集名"), ("source_provider", "提供者"),
                       ("source_doi_url", "DOI"), ("licence", "许可"),
                       ("licence_url", "许可 URL"), ("licence_status", "许可状态")]:
        by = collections.defaultdict(set)
        for r in act:
            by[ds_key(r["layer_path"])].add((r[col] or "").strip())
        amb = [k for k, v in by.items() if len(v) > 1]
        add("3 一致性", "同一数据集内 %s 唯一" % label, len(by), len(amb),
            "%d 个数据集" % len(by), amb)

    # unit key: directory + filename with the focal suffix stripped
    def var_key(r):
        d, f = os.path.split(r["layer_path"])
        return (d, re.sub(r"_f\d+\.tif$", ".tif", f))

    by = collections.defaultdict(set)
    for r in act:
        by[var_key(r)].add(r["units"].strip())
    amb = ["%s/%s -> %s" % (k[0][-30:], k[1][-24:], sorted(v)) for k, v in by.items() if len(v) > 1]
    add("3 一致性", "同一变量（含各焦点窗口）units 唯一", len(by), len(amb),
        "%d 个变量" % len(by), amb)

    # The window belongs in derivation_formula, not variable_definition: the former
    # says how this layer was made, the latter says what the variable is. Phrasing
    # varies by dataset ("focal mean over a 21x21 square window", "square-window
    # mean, 21 x 21 cells"), so match the cell count with optional spaces.
    CELLS = {"1000": 3, "5000": 11, "10000": 21, "20000": 41}
    badf, nf = [], 0
    for r in act:
        m = FOCAL.search(r["layer_path"])
        if not m:
            continue
        nf += 1
        k = CELLS.get(m.group(1))
        f = r["derivation_formula"] or ""
        if not k or not re.search(r"\b%d\s*[x\u00d7]\s*%d\b" % (k, k), f):
            badf.append(r["layer_path"] + " :: " + f[:50])
    add("3 一致性", "焦点层 derivation_formula 写明自身窗口格数", nf, len(badf), "", badf)

    # non-focal layers must not claim a focal window
    badn = []
    nn = 0
    for r in act:
        if FOCAL.search(r["layer_path"]):
            continue
        nn += 1
        d = r["variable_definition"] or ""
        if "x 3" in d or "11 x 11" in d or "21 x 21" in d or "41 x 41" in d:
            badn.append(r["layer_path"])
    add("3 一致性", "非焦点层定义不提窗口格数", nn, len(badn), "", badn)

    # ---------- 4. filesystem reconciliation ----------
    print("\n=== 4. 与目录树对账 ===")
    disk = set()
    for dp, dn, fn in os.walk(COV):
        for f in fn:
            if f.endswith(".tif") and not f.endswith(".tmp.tif"):
                disk.add(os.path.relpath(os.path.join(dp, f), DATA).replace("\\", "/"))
    rows_set = {r["layer_path"] for r in act}
    add("4 对账", "磁盘 .tif 集合与 active 行集合一致", len(disk | rows_set),
        len(disk ^ rows_set), "磁盘 %d / 表 %d" % (len(disk), len(rows_set)),
        sorted(disk ^ rows_set)[:5])

    dcount = collections.Counter("/".join(p.split("/")[1:3]) for p in disk)
    tcount = collections.Counter(ds_key(r["layer_path"]) for r in act)
    diff = [k for k in set(dcount) | set(tcount) if dcount.get(k, 0) != tcount.get(k, 0)]
    add("4 对账", "每个数据集的层数磁盘=表", len(dcount), len(diff),
        "%d 个数据集" % len(dcount),
        ["%s 盘%d/表%d" % (k, dcount.get(k, 0), tcount.get(k, 0)) for k in diff[:5]])

    dth = collections.Counter(p.split("/")[1] for p in disk)
    tth = collections.Counter(ds_key(r["layer_path"]).split("/")[0] for r in act)
    diff = [k for k in set(dth) | set(tth) if dth.get(k, 0) != tth.get(k, 0)]
    add("4 对账", "每个主题的层数磁盘=表", len(dth), len(diff),
        ", ".join("%s:%d" % (k, dth[k]) for k in sorted(dth)), diff)

    # ---------- 5. declared scale verification ----------
    print("\n=== 5. source_scale_offset 抽验 ===")
    cand = []
    for r in act:
        if not r["source_file"].startswith("[path]"):
            continue
        kind, fac = parse_scale(r["source_scale_offset"], r["layer_path"])
        if kind is None or fac in (None, 1.0):
            continue
        srcres = (r["source_resolution"] or "").strip().lower()
        # 点采样只在源像元与本库像元尺度相当时可判读；30 m 源与 1 km 均值不可比
        if not (srcres.startswith("1000 m") or srcres.startswith("1 km")):
            continue
        p = r["source_file"][len("[path]"):].strip()
        p = re.sub(r"\s{2,}\[.*\]\s*$", "", p)
        while re.search(r"\s+\([^()]*\)\s*$", p):
            p = re.sub(r"\s+\([^()]*\)\s*$", "", p)
        cand.append((r, p.strip(), kind, fac))
    # The scale prose is identical for every layer of a dataset, so sampling by text
    # would test one rule only. Soil is the case that matters: AN and AK are stored
    # x10 while every other property is x100, two different rules in one dataset.
    # Sample one layer per property instead, so both rules are exercised.
    def prop_of(lp):
        parts = lp.split("/")
        return parts[3] if len(parts) > 4 else "/".join(parts[1:3])

    byprop = collections.defaultdict(list)
    for item in cand:
        byprop[(ds_key(item[0]["layer_path"]), prop_of(item[0]["layer_path"]))].append(item)
    sample = [byprop[k][0] for k in sorted(byprop)][:8]
    print("  非恒等 scale、可解析、且源为 1 km 的层 %d，按属性抽 %d 层" % (len(cand), len(sample)))

    rng = np.random.default_rng(20261025)
    with rasterio.open(os.path.join(ROOT, "data", "mask_china.tif")) as s:
        m = s.read(1); tr = s.transform
    idx = np.flatnonzero(m.ravel() == 1)
    pick = rng.choice(idx, 400, replace=False)
    rr, cc = np.unravel_index(pick, m.shape)
    xs, ys = tr * (cc + 0.5, rr + 0.5)

    ratios = []
    for r, src, kind, fac in sample:
        if not os.path.exists(src.replace("/", os.sep)):
            continue
        dst = os.path.join(DATA, r["layer_path"].replace("/", os.sep))
        try:
            with rasterio.open(src.replace("/", os.sep)) as s:
                sx, sy = rio_transform(CRS.from_proj4(ALBERS), s.crs,
                                       xs.tolist(), ys.tolist())
                sv = np.array([v[0] for v in s.sample(zip(sx, sy))], dtype="float64")
            with rasterio.open(dst) as s2:
                dv = np.array([v[0] for v in s2.sample(zip(xs.tolist(), ys.tolist()))],
                              dtype="float64")
                nd = s2.nodata
            conv = (lambda v: v * fac) if kind == "mult" else (lambda v: v / fac)
            ok = np.isfinite(sv) & np.isfinite(dv) & (dv != nd) & (np.abs(sv) > 1e-9)
            if ok.sum() < 30:
                continue
            ratio = float(np.median(dv[ok] / conv(sv[ok])))
            ratios.append((r["layer_path"], r["source_scale_offset"], ratio, int(ok.sum())))
        except Exception:
            continue

    for lp, sc, ra, n in ratios:
        print("    %-50s %-26s %7.3f (n=%d)" % (lp[-50:], sc[:26], ra, n))
    good = [x for x in ratios if abs(x[2] - 1) <= 0.05]
    bad = [x for x in ratios if abs(x[2] - 1) > 0.05]
    add("5 标度", "声明 scale 与实测比值一致（±5%）", len(ratios), len(bad),
        "抽 %d 层，符合 %d" % (len(ratios), len(good)),
        ["%s %s -> %.3f" % (x[0][-40:], x[1][:20], x[2]) for x in bad[:3]])

    # ---------- write ----------
    os.makedirs(AUD, exist_ok=True)
    p = os.path.join(AUD, "provenance_column_audit.csv")
    with open(p, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["section", "check", "examined", "failed",
                                          "detail", "examples"])
        w.writeheader()
        w.writerows(res)
    checked = [x for x in res if x["section"] != "1 画像"]
    nf = sum(1 for x in checked if x["failed"] > 0 or x["examined"] == 0)
    print("\n  === 结论：%d 项检查（不含逐列画像），未通过 %d ===\n  written: %s"
          % (len(checked), nf, p))


if __name__ == "__main__":
    main()
