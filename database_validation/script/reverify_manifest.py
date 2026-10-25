#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Re-hash every delivered layer and compare with MANIFEST.csv.

This is the only check that proves the cleanup touched nothing: it reads all
169 GB back and compares byte-for-byte digests. A missing file, a changed byte,
or a manifest entry with no file all fail.

Output: audit/manifest_reverify.csv and a printed verdict.
"""
from __future__ import annotations

import csv
import hashlib
import io
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

ROOT = os.environ.get("CHECO_ROOT", r"E:\CHECO26\N-SDM")
DATA = os.path.join(ROOT, "data")
AUD = os.path.join(ROOT, "audit")
WORKERS = 8
CHUNK = 8 << 20


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(CHUNK)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def job(rel, expect, nbytes):
    p = os.path.join(DATA, rel.replace("/", os.sep))
    if not os.path.exists(p):
        return (rel, "missing", "", int(nbytes or 0), 0)
    got_bytes = os.path.getsize(p)
    if nbytes and got_bytes != int(nbytes):
        return (rel, "size_mismatch", "", int(nbytes), got_bytes)
    got = digest(p)
    return (rel, "ok" if got == expect else "hash_mismatch", got, int(nbytes or 0), got_bytes)


def main():
    with io.open(os.path.join(ROOT, "00_docs", "MANIFEST.csv"), encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    cov = [r for r in rows if r["relpath"].startswith("covariates/")]
    print("manifest 中 covariates 条目: %d" % len(cov), flush=True)

    t0 = time.time()
    out = []
    with ProcessPoolExecutor(max_workers=WORKERS) as ex:
        futs = [ex.submit(job, r["relpath"], r["sha256"], r["bytes"]) for r in cov]
        for i, fu in enumerate(futs, 1):
            out.append(fu.result())
            if i % 1000 == 0:
                print("  %d/%d  %.0f 文件/s" % (i, len(cov), i / (time.time() - t0)), flush=True)

    bad = [r for r in out if r[1] != "ok"]
    print("\n=== 结果 ===")
    print("  校验层数: %d" % len(out))
    print("  一致:     %d" % (len(out) - len(bad)))
    print("  不一致:   %d" % len(bad))
    for r in bad[:20]:
        print("    %-60s %s" % (r[0][-60:], r[1]))

    os.makedirs(AUD, exist_ok=True)
    p = os.path.join(AUD, "manifest_reverify.csv")
    with open(p, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["relpath", "status", "sha256_now", "bytes_manifest", "bytes_now"])
        w.writerows(out)
    print("written:", p)


if __name__ == "__main__":
    main()
