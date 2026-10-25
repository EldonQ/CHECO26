#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cross-verify the provenance table against independent artefacts.

Each check joins provenance_table.csv to something else on disk, so an entry that
is merely self-consistent cannot pass. Two checks need care to avoid false alarms:

  * `script_function` names a production stage, written as `script : detail`. For R
    stages the script must exist and the snake_case identifiers in the detail must
    appear in the R tree. For the earlier Python stages only the script file can be
    checked, and English prose in the detail (`Euclidean`) must not be read as a
    function name.
  * `source_doi_url` holds a bare DOI for most sources. A few were never assigned a
    DOI, and for those the provider's landing page is the honest value; empty or
    unparseable is the failure, a landing page is not.

Output: audit/provenance_verification.csv
"""
from __future__ import annotations

import collections
import csv
import io
import os
import re

ROOT = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
DOCS = os.path.join(ROOT, "00_docs")
DATA = os.path.join(ROOT, "data", "covariates")      # layer_path starts with glo/
AUD = os.path.join(ROOT, "audit")

RANGE = re.compile(r"\[(-?[\d.eE+-]+),\s*(-?[\d.eE+-]+)\]")
BARE_DOI = re.compile(r"^10\.\d{4,9}/\S+$")
FULL_URL = re.compile(r"^https?://(dx\.)?doi\.org/10\.\d{4,9}/\S+$")
SNAKE = re.compile(r"[a-z_][a-z0-9_]*(?:_[a-z0-9]+)+")


def load(path):
    with io.open(path, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def main():
    prov = load(os.path.join(DOCS, "provenance_table.csv"))
    dic = {r["relpath"]: r for r in load(os.path.join(DOCS, "variable_dictionary.csv"))}
    reg = load(os.path.join(DOCS, "LICENCE_REGISTRY.csv"))
    aud = {r["relpath"]: r for r in load(os.path.join(AUD, "layer_audit.csv"))}
    act = [r for r in prov if r["status"] == "active"]
    wd = [r for r in prov if r["status"] != "active"]

    reg_by_key = {r["dataset_key"].strip(): r for r in reg}

    # R tree, for the script_function check
    src = []
    for dp, dn, fn in os.walk(os.path.join(ROOT, "R")):
        for f in fn:
            if f.endswith(".R"):
                try:
                    src.append(io.open(os.path.join(dp, f), encoding="utf-8").read())
                except Exception:
                    pass
    allsrc = "\n".join(src)
    py_dir = os.path.join(ROOT, "scripts")
    py_files = {f for f in os.listdir(py_dir) if f.endswith(".py")}

    checks = []

    def add(name, total, bad, examples, note=""):
        checks.append({"check": name, "checked": total, "failed": bad,
                       "pass_rate_pct": round(100 * (1 - bad / total), 4) if total else "",
                       "examples": " || ".join(examples[:5]), "note": note})
        print("  %-46s 检查 %6d  失败 %5d  %6.2f%% 通过"
              % (name, total, bad, 100 * (1 - bad / total) if total else 0))
        for e in examples[:3]:
            print("      · " + e[:150])

    def ds_key(layer_path):
        p = layer_path.split("/")
        return "%s/%s" % (p[1], p[2]) if len(p) > 2 else ""

    # 1) active rows exist, withdrawn rows do not
    miss = [r["layer_path"] for r in act
            if not os.path.exists(os.path.join(DATA, r["layer_path"].replace("/", os.sep)))]
    add("active 行对应文件存在", len(act), len(miss), miss)
    still = [r["layer_path"] for r in wd
             if os.path.exists(os.path.join(DATA, r["layer_path"].replace("/", os.sep)))]
    add("withdrawn 行对应文件不存在", len(wd), len(still), still)

    # 2) the two tables cover the same layers
    pset, dset = {r["layer_path"] for r in act}, set(dic)
    add("provenance 与字典的层集合一致", len(pset | dset), len(pset ^ dset),
        sorted(pset ^ dset))

    # 3) one English unit label per Chinese label, and no empty unit
    zh2en = collections.defaultdict(set)
    for r in act:
        d = dic.get(r["layer_path"])
        if d:
            zh2en[d["unit"].strip()].add(r["units"].strip())
    amb = ["%s -> %s" % (zh, sorted(en)) for zh, en in zh2en.items() if len(en) > 1]
    add("同一中文单位只对应一个英文单位", len(zh2en), len(amb), amb,
        "%d 种中文单位 / %d 种英文单位" % (len(zh2en), len({r["units"] for r in act})))
    empty_u = [r["layer_path"] for r in act if not r["units"].strip()]
    add("units 非空", len(act), len(empty_u), empty_u)

    # 4) actual_range against the recomputed audit
    badr, worst, n_r = [], 0.0, 0
    for r in act:
        a, m = aud.get(r["layer_path"]), RANGE.match((r["actual_range"] or "").strip())
        if not a or not m:
            continue
        n_r += 1
        lo, hi = float(m.group(1)), float(m.group(2))
        d = max(abs(lo - float(a["vmin"])) / max(1e-12, abs(lo)),
                abs(hi - float(a["vmax"])) / max(1e-12, abs(hi)))
        worst = max(worst, d)
        if d > 1e-5:
            badr.append("%s 溯源[%g,%g] 审计[%g,%g]"
                        % (r["layer_path"][-46:], lo, hi, float(a["vmin"]), float(a["vmax"])))
    add("actual_range 与审计重算一致（1e-5）", n_r, len(badr), badr,
        "最大相对偏差 %.2e" % worst)

    # 5) the recorded valid-cell count
    badn, n_n = [], 0
    for r in act:
        a = aud.get(r["layer_path"])
        m = re.search(r"over\s+([0-9]+)\s+valid", r["actual_range"] or "")
        if not a or not m:
            continue
        n_n += 1
        if int(m.group(1)) != int(a["n_valid"]):
            badn.append("%s 溯源=%s 审计=%s" % (r["layer_path"][-40:], m.group(1), a["n_valid"]))
    add("actual_range 记录的 n_valid 与审计一致", n_n, len(badn), badn)

    # 6) expected_range brackets the measured values
    bade, n_e = [], 0
    for r in act:
        a, m = aud.get(r["layer_path"]), RANGE.match((r["expected_range"] or "").strip())
        if not a or not m:
            continue
        n_e += 1
        lo, hi = float(m.group(1)), float(m.group(2))
        if float(a["vmin"]) < lo - 1e-6 or float(a["vmax"]) > hi + 1e-6:
            bade.append(r["layer_path"])
    add("expected_range 覆盖实测值", n_e, len(bade), bade)

    # 7) licence agrees with the registry, joined on theme/dataset
    badl, n_l, nojoin = [], 0, []
    for r in act:
        g = reg_by_key.get(ds_key(r["layer_path"]))
        if not g:
            nojoin.append(r["layer_path"])
            continue
        n_l += 1
        if r["licence"].strip() != g["licence_spdx"].strip():
            badl.append("%s 表=%s 登记=%s"
                        % (r["layer_path"][-40:], r["licence"], g["licence_spdx"]))
    add("licence 与许可登记表一致", n_l, len(badl), badl,
        "未能联接的行 %d" % len(nojoin))

    # 8) licence_status agrees with the registry class
    bads, n_s = [], 0
    for r in act:
        g = reg_by_key.get(ds_key(r["layer_path"]))
        if not g:
            continue
        n_s += 1
        cls = g["licence_class"].strip().upper()
        expect = {"OPEN": "OPEN", "NC": "NC", "RESTRICTED": "RESTRICTED"}.get(cls, cls)
        if expect not in r["licence_status"].strip().upper():
            bads.append("%s 表=%s 登记类=%s" % (r["layer_path"][-40:], r["licence_status"], cls))
    add("licence_status 与登记的许可类别一致", n_s, len(bads), bads)

    # 9) script_function names a script that exists, and for R stages a function
    bada, n_a = [], 0
    for r in act:
        sf = (r["script_function"] or "").strip()
        if not sf:
            continue
        n_a += 1
        head = sf.split(":")[0].strip()
        if head.startswith("R/"):
            if not os.path.exists(os.path.join(ROOT, head.replace("/", os.sep))):
                bada.append("%s: 脚本不存在 %s" % (r["layer_path"][-38:], head))
                continue
            body = sf.split(":", 1)[1] if ":" in sf else ""
            missing = [t for t in sorted(set(SNAKE.findall(body))) if t not in allsrc]
            if missing:
                bada.append("%s: R/ 中无 %s" % (r["layer_path"][-38:], ",".join(missing)))
        elif head.endswith(".py") and "/" not in head and "\\" not in head:
            if head not in py_files:
                bada.append("%s: 脚本不存在 %s" % (r["layer_path"][-38:], head))
    add("script_function 指向的脚本与函数可核实", n_a, len(bada), bada)

    # 10) the source identifier
    bare = [r for r in act if BARE_DOI.match((r["source_doi_url"] or "").strip())]
    full = [r for r in act if FULL_URL.match((r["source_doi_url"] or "").strip())]
    pages = [r for r in act
             if (r["source_doi_url"] or "").strip().startswith(("http://", "https://"))
             and not FULL_URL.match((r["source_doi_url"] or "").strip())]
    bad_d = [r["layer_path"] for r in act
             if not (BARE_DOI.match((r["source_doi_url"] or "").strip())
                     or (r["source_doi_url"] or "").strip().startswith(("http://", "https://")))]
    add("source_doi_url 非空且为 DOI 或供应商链接", len(act), len(bad_d), bad_d,
        "裸 DOI %d / doi.org %d / 供应商页面 %d" % (len(bare), len(full), len(pages)))

    # 11) stray whitespace or control characters
    bad_t = []
    for r in act:
        for c, v in r.items():
            if v and (v != v.strip() or "\t" in v or "\n" in v or "\r" in v):
                bad_t.append("%s : %s = %r" % (r["layer_path"][-30:], c, v[:60]))
                break
    add("文本字段无首尾空白/控制字符", len(act), len(bad_t), bad_t)

    os.makedirs(AUD, exist_ok=True)
    p = os.path.join(AUD, "provenance_verification.csv")
    with open(p, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(checks[0].keys()))
        w.writeheader()
        w.writerows(checks)
    print("\nwritten:", p)
    print("总判定: %d 项检查，失败合计 %d" % (len(checks), sum(c["failed"] for c in checks)))


if __name__ == "__main__":
    main()
