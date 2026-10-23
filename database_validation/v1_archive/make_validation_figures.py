#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Regenerate the database-validation figures from the result dataframes.

The validation figure set:
value-range and NA-count scatterplots per layer, the sampled cell-by-cell
comparison against source products, and the per-theme layer inventory.

Inputs (default: alongside this script):
    result_dataframe/p5_validation_report.csv   per-layer stats (1,595 rows)
    result_dataframe/cell_by_cell_checks.csv    sampled source comparisons
Outputs (default: alongside this script):
    figures/scatterplot_range.png
    figures/scatterplot_NAcount.png
    figures/scatterplot_cellcheck.png
    figures/layers_per_theme.png
"""
from __future__ import annotations

import argparse
import csv
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))

THEMES = ["bioclim", "soil", "topo", "vege", "hydro", "lulc", "anthro", "dist"]
THEME_COLOR = {
    "bioclim": "#E15759", "soil": "#B07AA1", "topo": "#9C755F",
    "vege": "#59A14F", "hydro": "#4E79A7", "lulc": "#F28E2B",
    "anthro": "#EDC948", "dist": "#76B7B2",
}
TOTAL_CELLS = 4861 * 4062          # template grid
MASK_CELLS = 9490310               # valid cells inside the China mask

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["DejaVu Sans", "Arial", "Helvetica"],
    "axes.unicode_minus": False,
    "axes.edgecolor": "#444444",
    "axes.labelcolor": "#222222",
    "text.color": "#222222",
    "xtick.color": "#444444",
    "ytick.color": "#444444",
    "figure.facecolor": "white",
    "axes.facecolor": "white",
})


def theme_of(rel):
    return rel.split("/")[1]


def load_p5(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["vmin"] in ("", None):
                continue
            rows.append(dict(relpath=r["relpath"], theme=theme_of(r["relpath"]),
                             vmin=float(r["vmin"]), vmax=float(r["vmax"]),
                             n_valid=int(r["n_valid"]),
                             na_frac=float(r["na_frac"])))
    return rows


def load_cellchecks(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def fig_range(rows, out):
    fig, ax = plt.subplots(figsize=(10, 5.2))
    order = {t: i for i, t in enumerate(THEMES)}
    rows = sorted(rows, key=lambda r: (order[r["theme"]], r["relpath"]))
    x = np.arange(len(rows))
    y = np.array([abs(r["vmin"]) + abs(r["vmax"]) for r in rows])
    y[y <= 0] = np.nan
    for t in THEMES:
        sel = [i for i, r in enumerate(rows) if r["theme"] == t]
        ax.scatter(x[sel], y[sel], s=7, alpha=0.75, color=THEME_COLOR[t],
                   label=t, linewidths=0)
    ax.set_yscale("log")
    ax.set_xlabel("Layer (grouped by theme)")
    ax.set_ylabel("Value range  |min| + |max|  (log scale)")
    ax.set_title("Value range per layer (1,595 layers)", fontsize=12,
                 fontweight="bold")
    ax.legend(title="theme", markerscale=2, fontsize=9, title_fontsize=9,
              loc="upper left", frameon=False)
    ax.grid(axis="y", alpha=0.25, linewidth=0.5)
    # annotate the three most extreme layers
    idx = np.argsort(np.where(np.isnan(y), -np.inf, y))[-3:]
    for i in idx:
        if np.isnan(y[i]):
            continue
        short = os.path.basename(rows[i]["relpath"])[:-4]
        short = short.replace("glo_", "").replace(".tif", "")
        ax.annotate(short, (x[i], y[i]), textcoords="offset points",
                    xytext=(4, 4), fontsize=7.5, color="#555555")
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    plt.close(fig)
    print("wrote", out)


def fig_na(rows, out):
    fig, ax = plt.subplots(figsize=(10, 5.2))
    order = {t: i for i, t in enumerate(THEMES)}
    rows = sorted(rows, key=lambda r: (order[r["theme"]], r["relpath"]))
    x = np.arange(len(rows))
    y = np.array([r["na_frac"] * TOTAL_CELLS for r in rows])
    for t in THEMES:
        sel = [i for i, r in enumerate(rows) if r["theme"] == t]
        ax.scatter(x[sel], y[sel], s=7, alpha=0.75, color=THEME_COLOR[t],
                   label=t, linewidths=0)
    ax.set_yscale("log")
    floor = TOTAL_CELLS - MASK_CELLS
    ax.axhline(floor, color="#888888", linestyle="--", linewidth=1)
    ax.text(len(rows) * 0.995, floor * 1.15,
            "cells outside the China mask (expected floor)",
            ha="right", fontsize=8.5, color="#555555")
    ax.set_xlabel("Layer (grouped by theme)")
    ax.set_ylabel("NoData cells (log scale)")
    ax.set_title("NoData count per layer (1,595 layers)", fontsize=12,
                 fontweight="bold")
    ax.legend(title="theme", markerscale=2, fontsize=9, title_fontsize=9,
              loc="upper left", frameon=False)
    ax.grid(axis="y", alpha=0.25, linewidth=0.5)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    plt.close(fig)
    print("wrote", out)


def fig_cellcheck(checks, out):
    checks = sorted(checks, key=lambda c: float(c["match"]))
    labels = [os.path.basename(c["relpath"])[:-4].replace("glo_", "")
              for c in checks]
    vals = [float(c["match"]) for c in checks]
    colors = ["#4E79A7" if c["verdict"] == "pass" else "#F28E2B"
              for c in checks]
    fig, ax = plt.subplots(figsize=(10, 5.6))
    y = np.arange(len(checks))
    ax.barh(y, vals, color=colors, height=0.62)
    ax.set_yticks(y)
    ax.set_yticklabels(labels, fontsize=8)
    ax.set_xlim(0.85, 1.005)
    ax.axvline(0.95, color="#888888", linestyle="--", linewidth=1)
    ax.text(0.9505, len(checks) - 0.4, "acceptance threshold 0.95",
            fontsize=8.5, color="#555555")
    for yi, v, c in zip(y, vals, checks):
        ax.text(v + 0.001, yi, "%.3f" % v, va="center", fontsize=8,
                color="#333333")
    ax.set_xlabel("Cell-by-cell match rate vs. source product (1,000 sampled cells)")
    ax.set_title("Sampled cell-by-cell comparison against source products",
                 fontsize=12, fontweight="bold")
    handles = [plt.Rectangle((0, 0), 1, 1, color="#4E79A7"),
               plt.Rectangle((0, 0), 1, 1, color="#F28E2B")]
    ax.legend(handles, ["pass", "reference difference (resampling)"],
              loc="lower right", fontsize=9, frameon=False)
    ax.grid(axis="x", alpha=0.25, linewidth=0.5)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    plt.close(fig)
    print("wrote", out)


def fig_theme_counts(rows, out):
    present, future = {}, {}
    for r in rows:
        t = r["theme"]
        if "/scenario/" in r["relpath"]:
            future[t] = future.get(t, 0) + 1
        else:
            present[t] = present.get(t, 0) + 1
    themes = [t for t in THEMES if present.get(t, 0) + future.get(t, 0) > 0]
    pres = [present.get(t, 0) for t in themes]
    fut = [future.get(t, 0) for t in themes]
    y = np.arange(len(themes))
    fig, ax = plt.subplots(figsize=(8, 4.6))
    ax.barh(y, pres, color="#4E79A7", height=0.6, label="present")
    ax.barh(y, fut, left=pres, color="#F28E2B", height=0.6, label="future scenarios")
    ax.set_yticks(y)
    ax.set_yticklabels(themes, fontsize=10)
    for yi, (p, f) in enumerate(zip(pres, fut)):
        ax.text(p + f + 6, yi, "%d" % (p + f), va="center", fontsize=9,
                color="#333333")
    ax.set_xlabel("Number of layers")
    ax.set_title("CHECO26 layer inventory by theme (1,595 layers)",
                 fontsize=12, fontweight="bold")
    ax.legend(fontsize=9, frameon=False, loc="lower right")
    ax.grid(axis="x", alpha=0.25, linewidth=0.5)
    ax.set_xlim(0, max(np.array(pres) + np.array(fut)) * 1.14)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    plt.close(fig)
    print("wrote", out)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--p5", default=os.path.join(HERE, "..", "result_dataframe",
                                                 "p5_validation_report.csv"))
    ap.add_argument("--cellchecks", default=os.path.join(
        HERE, "..", "result_dataframe", "cell_by_cell_checks.csv"))
    ap.add_argument("--outdir", default=os.path.join(HERE, "..", "figures"))
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    rows = load_p5(args.p5)
    print("p5 rows: %d" % len(rows))
    fig_range(rows, os.path.join(args.outdir, "scatterplot_range.png"))
    fig_na(rows, os.path.join(args.outdir, "scatterplot_NAcount.png"))
    fig_theme_counts(rows, os.path.join(args.outdir, "layers_per_theme.png"))
    checks = load_cellchecks(args.cellchecks)
    print("cell checks: %d" % len(checks))
    fig_cellcheck(checks, os.path.join(args.outdir, "scatterplot_cellcheck.png"))


if __name__ == "__main__":
    main()
