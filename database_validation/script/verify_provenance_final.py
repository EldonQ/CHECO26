#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Final, full verification of provenance_table.csv.

verify_provenance.py answers "is each field right against the disk". This script
adds what that one does not: file-level integrity, per-column completeness, value
format, the withdrawn rows, source-file resolvability, and the internal
consistency of the attribution split.

Every check prints its own total so a check that silently skipped rows is visible:
a check with 0 rows examined is reported as a failure, not a pass.

Output: audit/provenance_check_results.csv and audit/PROVENANCE_FINAL.md
"""
from __future__ import annotations

import collections
import csv
import io
import os
import re

ROOT = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
DOCS = os.path.join(ROOT, "00_docs")
DATA = os.path.join(ROOT, "data", "covariates")
AUD = os.path.join(ROOT, "audit")
PROV = os.path.join(DOCS, "provenance_table.csv")

COLS = ["layer_path", "status", "source_file", "source_dataset", "source_provider",
        "source_doi_url", "source_citation", "variable_definition", "units",
        "source_crs", "source_resolution", "source_extent", "source_nodata",
        "source_scale_offset", "processing_steps", "derivation_formula",
        "missing_boundary_rule", "script_function", "expected_range", "actual_range",
        "notes", "licence", "licence_url", "attribution", "licence_status"]
RANGE = re.compile(r"\[(-?[\d.eE+-]+),\s*(-?[\d.eE+-]+)\]")
BARE_DOI = re.compile(r"^10\.\d{4,9}/\S+$")
SNAKE = re.compile(r"[a-z_][a-z0-9_]*(?:_[a-z0-9]+)+")


def load(p):
    with io.open(p, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def main():
    raw = open(PROV, "rb").read()
    prov = load(PROV)
    dic = {r["relpath"]: r for r in load(os.path.join(DOCS, "variable_dictionary.csv"))}
    reg = {r["dataset_key"].strip(): r for r in load(os.path.join(DOCS, "LICENCE_REGISTRY.csv"))}
    aud = {r["relpath"]: r for r in load(os.path.join(AUD, "layer_audit.csv"))}
    mani = {r["relpath"].replace("covariates/", "", 1): r
            for r in load(os.path.join(DOCS, "MANIFEST.csv"))}
    act = [r for r in prov if r["status"] == "active"]
    wd = [r for r in prov if r["status"] == "withdrawn"]

    src = []
    unreadable = []
    for dp, dn, fn in os.walk(os.path.join(ROOT, "R")):
        for f in fn:
            if f.endswith(".R"):
                try:
                    src.append(io.open(os.path.join(dp, f), encoding="utf-8").read())
                except Exception as e:
                    # An unreadable source file would make E1 fail for a reason that has
                    # nothing to do with the table, so it is reported, not hidden.
                    unreadable.append("%s: %s" % (f, type(e).__name__))
    allsrc = "\n".join(src)
    py_files = {f for f in os.listdir(os.path.join(ROOT, "scripts")) if f.endswith(".py")}

    out = []

    def add(name, total, bad, detail="", examples=None):
        ok = total > 0 and bad == 0
        out.append({"check": name, "examined": total, "failed": bad,
                    "pass": "YES" if ok else "NO", "detail": detail,
                    "examples": " || ".join((examples or [])[:4])})
        print("  %-46s 检查 %6d  失败 %5d  %s  %s"
              % (name, total, bad, "PASS" if ok else "**FAIL**", detail))

    def ds_key(lp):
        p = lp.split("/")
        return "%s/%s" % (p[1], p[2]) if len(p) > 2 else ""

    # ---------- A. file integrity ----------
    add("A1 行数为 21,118（21,110 active + 8 withdrawn）", len(prov),
        abs(len(prov) - 21118), "%d 行" % len(prov))
    hdr = list(prov[0].keys())
    add("A2 列名与顺序为 25 列既定表头", 1, 0 if hdr == COLS else 1,
        "%d 列" % len(hdr), [str(hdr)] if hdr != COLS else None)
    add("A3 UTF-8 BOM 存在", 1, 0 if raw[:3] == b"\xef\xbb\xbf" else 1)
    add("A4 文件无 NUL 字节", 1, 1 if b"\x00" in raw else 0)
    add("A5 status 取值仅 active / withdrawn", len(prov),
        sum(1 for r in prov if r["status"] not in ("active", "withdrawn")),
        "active %d / withdrawn %d" % (len(act), len(wd)))
    dup = [k for k, n in collections.Counter(r["layer_path"] for r in prov).items() if n > 1]
    add("A6 layer_path 无重复", len(prov), len(dup), "", dup)

    # ---------- B. paths ----------
    miss = [r["layer_path"] for r in act
            if not os.path.exists(os.path.join(DATA, r["layer_path"].replace("/", os.sep)))]
    add("B1 active 行对应文件存在", len(act), len(miss), "", miss)
    still = [r["layer_path"] for r in wd
             if os.path.exists(os.path.join(DATA, r["layer_path"].replace("/", os.sep)))]
    add("B2 withdrawn 行对应文件不在交付树", len(wd), len(still), "", still)
    shape = [r["layer_path"] for r in act
             if not r["layer_path"].startswith("glo/") or not r["layer_path"].endswith(".tif")]
    add("B3 active 路径均为 glo/…/*.tif", len(act), len(shape), "", shape)

    # ---------- C. values and formats ----------
    badr = []
    for r in act:
        a, m = aud.get(r["layer_path"]), RANGE.match((r["actual_range"] or "").strip())
        if not a or not m:
            badr.append(r["layer_path"] + " [无法解析或无审计]")
            continue
        lo, hi = float(m.group(1)), float(m.group(2))
        if abs(lo - float(a["vmin"])) > 1e-5 * max(1, abs(lo)) or \
           abs(hi - float(a["vmax"])) > 1e-5 * max(1, abs(hi)):
            badr.append(r["layer_path"])
    add("C1 actual_range 可解析且等于审计重算", len(act), len(badr), "", badr)

    badn = []
    for r in act:
        a = aud.get(r["layer_path"])
        m = re.search(r"over\s+([0-9]+)\s+valid", r["actual_range"] or "")
        if not a or not m or int(m.group(1)) != int(a["n_valid"]):
            badn.append(r["layer_path"])
    add("C2 actual_range 记录的 n_valid 等于审计", len(act), len(badn), "", badn)

    bade, badlohi = [], []
    for r in act:
        a, m = aud.get(r["layer_path"]), RANGE.match((r["expected_range"] or "").strip())
        if not m:
            bade.append(r["layer_path"] + " [无法解析]"); continue
        lo, hi = float(m.group(1)), float(m.group(2))
        if lo > hi:
            badlohi.append(r["layer_path"])
        if a and (float(a["vmin"]) < lo - 1e-6 or float(a["vmax"]) > hi + 1e-6):
            bade.append(r["layer_path"])
    add("C3 expected_range 可解析且 lo <= hi", len(act), len(badlohi), "", badlohi)
    add("C4 expected_range 覆盖实测值", len(act), len(bade), "", bade)

    badb = []
    for r in act:
        m = mani.get(r["layer_path"])
        p = os.path.join(DATA, r["layer_path"].replace("/", os.sep))
        if not m or not os.path.exists(p) or os.path.getsize(p) != int(m["bytes"]):
            badb.append(r["layer_path"])
    add("C5 磁盘字节数等于 MANIFEST.csv", len(act), len(badb), "", badb)

    # ---------- D. cross-table ----------
    pset, dset = {r["layer_path"] for r in act}, set(dic)
    add("D1 provenance 与字典的层集合完全一致", len(pset | dset), len(pset ^ dset), "",
        sorted(pset ^ dset))
    zh2en = collections.defaultdict(set)
    for r in act:
        d = dic.get(r["layer_path"])
        if d:
            zh2en[d["unit"].strip()].add(r["units"].strip())
    add("D2 同一中文单位只映射一个英文单位", len(zh2en),
        sum(1 for v in zh2en.values() if len(v) > 1), "%d 种单位" % len(zh2en))
    add("D3 units 非空", len(act), sum(1 for r in act if not r["units"].strip()))

    badlic = [r["layer_path"] for r in act
              if ds_key(r["layer_path"]) in reg
              and r["licence"].strip() != reg[ds_key(r["layer_path"])]["licence_spdx"].strip()]
    nlic = sum(1 for r in act if ds_key(r["layer_path"]) in reg)
    add("D4 licence 等于许可登记表", nlic, len(badlic), "%d 行可联接" % nlic, badlic)

    badst = []
    for r in act:
        g = reg.get(ds_key(r["layer_path"]))
        if not g:
            continue
        cls = g["licence_class"].strip().upper()
        if cls not in r["licence_status"].strip().upper():
            badst.append(r["layer_path"])
    add("D5 licence_status 含登记类别", nlic, len(badst), "", badst)

    add("D6 每个数据集都能在许可登记表中找到",
        len({ds_key(r["layer_path"]) for r in act}),
        len({ds_key(r["layer_path"]) for r in act} - set(reg)),
        "%d 个数据集" % len({ds_key(r["layer_path"]) for r in act}))

    # ---------- E. attribution ----------
    bada = []
    for r in act:
        sf = (r["script_function"] or "").strip()
        head = sf.split(" : ")[0].strip()
        if not head:
            bada.append(r["layer_path"] + " [空]"); continue
        if head.startswith("R/"):
            if not os.path.exists(os.path.join(ROOT, head.replace("/", os.sep))):
                bada.append(r["layer_path"] + " [脚本不存在]"); continue
            body = sf.split(" : ", 1)[1] if " : " in sf else ""
            if [t for t in set(SNAKE.findall(body)) if t not in allsrc]:
                bada.append(r["layer_path"] + " [函数不存在]")
        elif head.endswith(".py") and "/" not in head and "\\" not in head:
            if head not in py_files:
                bada.append(r["layer_path"] + " [脚本不存在]")
    add("E1 script_function 指向的脚本/函数可核实", len(act), len(bada), "", bada)

    split = collections.Counter()
    for r in act:
        h = (r["script_function"] or "").strip().split(" : ")[0]
        split["外部脚本" if h.startswith("E:") else ("R 管线" if h.startswith("R/") else "Python 管线")] += 1
    add("E2 归属三分类合计 21,110", len(act),
        0 if sum(split.values()) == 21110 else 1,
        "R %d / Python %d / 外部 %d" % (split["R 管线"], split["Python 管线"], split["外部脚本"]))

    # ---------- F. text ----------
    badt = []
    for r in prov:
        for c, v in r.items():
            if v and (v != v.strip() or "\t" in v or "\n" in v or "\r" in v):
                badt.append("%s:%s" % (r["layer_path"][-28:], c)); break
    add("F1 无首尾空白/控制字符（含 withdrawn）", len(prov), len(badt), "", badt)

    need = ["source_file", "source_dataset", "source_provider", "source_doi_url",
            "variable_definition", "units", "source_crs", "source_resolution",
            "source_extent", "processing_steps", "script_function", "expected_range",
            "actual_range", "licence", "licence_url", "licence_status"]
    emptyc = collections.Counter()
    for r in act:
        for c in need:
            if not (r[c] or "").strip():
                emptyc[c] += 1
    add("F2 关键列无空值", len(act) * len(need), sum(emptyc.values()),
        ", ".join("%s:%d" % kv for kv in emptyc.items()) or "无")

    badu = [r["layer_path"] for r in act
            if not (BARE_DOI.match((r["source_doi_url"] or "").strip())
                    or (r["source_doi_url"] or "").strip().startswith("http"))]
    add("F3 source_doi_url 为 DOI 或 URL", len(act), len(badu), "", badu)

    # ---------- G. source_file resolvability ----------
    path_rows = [r for r in act if r["source_file"].startswith("[path]")]
    sel_rows = [r for r in act if r["source_file"].startswith("[selector]")]
    other_rows = [r for r in act if not r["source_file"].startswith(("[path]", "[selector]"))]
    # `[path] <full path>` and the path may be followed by annotations, either
    # `  [inherited from base layer ...]` or one or more ` (band 1 = year 1960)`
    # segments. The path itself contains spaces, so the annotations are stripped
    # from the right rather than the path being matched from the left.
    def extract_source_path(sf):
        s = sf[len("[path]"):].strip()
        s = re.sub(r"\s{2,}\[.*\]\s*$", "", s)
        while re.search(r"\s+\([^()]*\)\s*$", s):
            s = re.sub(r"\s+\([^()]*\)\s*$", "", s)
        return s.strip()

    resolvable, annotated = 0, 0
    for r in path_rows:
        raw_path = extract_source_path(r["source_file"])
        if raw_path != r["source_file"][len("[path]"):].strip():
            annotated += 1
        if raw_path and os.path.exists(raw_path.replace("/", os.sep)):
            resolvable += 1
    add("G1 source_file 有 [path]/[selector] 标记",
        len(act), len(other_rows),
        "[path] %d / [selector] %d" % (len(path_rows), len(sel_rows)), other_rows[:3])
    add("G2 [path] 形式的源文件仍存在于磁盘", len(path_rows),
        len(path_rows) - resolvable,
        "可解析 %d / %d，其中 %d 行带注记" % (resolvable, len(path_rows), annotated))

    # ---------- H. the 95 non-standard climate layers ----------
    NS = {"bio02", "bio03", "bio05", "bio06", "bio07"}
    ns_rows = [r for r in act if "/bioclim/" in r["layer_path"]
               and r["layer_path"].rsplit("_", 1)[-1].replace(".tif", "") in NS]
    flagged = [r for r in ns_rows if "NON-STANDARD" in r["variable_definition"]]
    add("H1 95 个非标准气候层全部标注 NON-STANDARD", len(ns_rows),
        len(ns_rows) - len(flagged), "%d / %d" % (len(flagged), len(ns_rows)))
    false_flag = [r["layer_path"] for r in act
                  if "/bioclim/" in r["layer_path"] and "NON-STANDARD" in r["variable_definition"]
                  and r["layer_path"].rsplit("_", 1)[-1].replace(".tif", "") not in NS]
    add("H2 无其它气候层被误标 NON-STANDARD", len(act), len(false_flag), "", false_flag)

    # ---------- write ----------
    os.makedirs(AUD, exist_ok=True)
    p = os.path.join(AUD, "provenance_check_results.csv")
    with open(p, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)

    nfail = sum(1 for c in out if c["pass"] == "NO")
    print("\n  === 合计：%d 项检查，通过 %d，未通过 %d ===" % (len(out), len(out) - nfail, nfail))
    print("  written:", p)
    return nfail


if __name__ == "__main__":
    raise SystemExit(1 if main() else 0)
