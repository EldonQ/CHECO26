#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Regenerate the database-validation figures from the result dataframes.

Input (default: ../result_dataframe/per_layer_stats.csv), one row per delivered
layer with theme, n_valid, na_frac, vmin and vmax.

Outputs (default: ../figures/):
    scatterplot_range.png     value range per layer, log scale, by theme
    scatterplot_NAcount.png   NoData cell count per layer against the mask floor
    layers_per_theme.png      layer inventory split into present and scenario

The sampled cell-by-cell comparison figure from the earlier validation campaign
has no counterpart here: the evidence for values is the composition-identity and
independent-recomputation set, reported as tables rather than a per-layer bar
chart. The earlier figure is kept under ``earlier_campaign/``.

Usage:
    python make_validation_figures.py [--stats ...] [--outdir ...]
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


def load_stats(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["vmin"] in ("", None, "NA"):
                continue
            try:
                vmin, vmax = float(r["vmin"]), float(r["vmax"])
            except ValueError:
                continue
            rows.append(dict(relpath=r["relpath"], theme=r["theme"],
                             vmin=vmin, vmax=vmax,
                             n_valid=int(float(r["n_valid"])),
                             na_frac=float(r["na_frac"])))
    return rows


def fig_range(rows, out, n_all):
    order = {t: i for i, t in enumerate(THEMES)}
    rows = sorted(rows, key=lambda r: (order.get(r["theme"], 99), r["relpath"]))
    x = np.arange(len(rows))
    y = np.array([abs(r["vmin"]) + abs(r["vmax"]) for r in rows])
    y[y <= 0] = np.nan
    fig, ax = plt.subplots(figsize=(10, 5.2))
    for t in THEMES:
        sel = [i for i, r in enumerate(rows) if r["theme"] == t]
        if sel:
            ax.scatter(x[sel], y[sel], s=4, alpha=0.55, color=THEME_COLOR[t],
                       label=t, linewidths=0)
    ax.set_yscale("log")
    ax.set_xlabel("Layer (grouped by theme)")
    ax.set_ylabel("Value range  |min| + |max|  (log scale)")
    ax.set_title("Value range per layer (%s layers, %s plotted)"
                 % (format(n_all, ","), format(len(rows), ",")),
                 fontsize=12, fontweight="bold")
    ax.legend(title="theme", markerscale=3, fontsize=9, title_fontsize=9,
              loc="upper left", frameon=False)
    ax.grid(axis="y", alpha=0.25, linewidth=0.5)
    idx = np.argsort(np.where(np.isnan(y), -np.inf, y))[-3:]
    for i in idx:
        if np.isnan(y[i]):
            continue
        short = os.path.basename(rows[i]["relpath"])[:-4].replace("glo_", "")
        ax.annotate(short, (x[i], y[i]), textcoords="offset points",
                    xytext=(4, 4), fontsize=7.5, color="#555555")
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    plt.close(fig)
    print("wrote", out)


def fig_na(rows, out, n_all):
    order = {t: i for i, t in enumerate(THEMES)}
    rows = sorted(rows, key=lambda r: (order.get(r["theme"], 99), r["relpath"]))
    x = np.arange(len(rows))
    y = np.array([r["na_frac"] * TOTAL_CELLS for r in rows])
    fig, ax = plt.subplots(figsize=(10, 5.2))
    for t in THEMES:
        sel = [i for i, r in enumerate(rows) if r["theme"] == t]
        if sel:
            ax.scatter(x[sel], y[sel], s=4, alpha=0.55, color=THEME_COLOR[t],
                       label=t, linewidths=0)
    ax.set_yscale("log")
    floor = TOTAL_CELLS - MASK_CELLS
    ax.axhline(floor, color="#888888", linestyle="--", linewidth=1)
    ax.text(len(rows) * 0.995, floor * 1.15,
            "cells outside the China mask (expected floor)",
            ha="right", fontsize=8.5, color="#555555")
    ax.set_xlabel("Layer (grouped by theme)")
    ax.set_ylabel("NoData cells (log scale)")
    ax.set_title("NoData count per layer (%s layers)" % format(n_all, ","),
                 fontsize=12, fontweight="bold")
    ax.legend(title="theme", markerscale=3, fontsize=9, title_fontsize=9,
              loc="upper left", frameon=False)
    ax.grid(axis="y", alpha=0.25, linewidth=0.5)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    plt.close(fig)
    print("wrote", out)


def fig_theme_counts(rows, out, n_all):
    present, future = {}, {}
    for r in rows:
        t = r["theme"]
        if "/scenario/" in r["relpath"]:
            future[t] = future.get(t, 0) + 1
        else:
            present[t] = present.get(t, 0) + 1
    themes = [t for t in THEMES if present.get(t, 0) + future.get(t, 0) > 0]
    pres = np.array([present.get(t, 0) for t in themes])
    fut = np.array([future.get(t, 0) for t in themes])
    y = np.arange(len(themes))
    fig, ax = plt.subplots(figsize=(8, 4.6))
    ax.barh(y, pres, color="#4E79A7", height=0.6, label="present")
    ax.barh(y, fut, left=pres, color="#F28E2B", height=0.6, label="future scenarios")
    ax.set_yticks(y)
    ax.set_yticklabels(themes, fontsize=10)
    for yi, (p, f) in enumerate(zip(pres, fut)):
        ax.text(p + f + max(pres + fut) * 0.012, yi, format(int(p + f), ","),
                va="center", fontsize=9, color="#333333")
    ax.set_xlabel("Number of layers")
    ax.set_title("CHECO26 layer inventory by theme (%s layers)" % format(n_all, ","),
                 fontsize=12, fontweight="bold")
    ax.legend(fontsize=9, frameon=False, loc="lower right")
    ax.grid(axis="x", alpha=0.25, linewidth=0.5)
    ax.set_xlim(0, max(pres + fut) * 1.16)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    plt.close(fig)
    print("wrote", out)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stats", default=os.path.join(HERE, "..", "result_dataframe",
                                                    "per_layer_stats.csv"))
    ap.add_argument("--outdir", default=os.path.join(HERE, "..", "figures"))
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    all_rows = load_stats(args.stats)
    n_all = sum(1 for _ in csv.DictReader(open(args.stats, encoding="utf-8")))
    print("stats rows: %d ; plottable: %d" % (n_all, len(all_rows)))
    fig_range(all_rows, os.path.join(args.outdir, "scatterplot_range.png"), n_all)
    fig_na(all_rows, os.path.join(args.outdir, "scatterplot_NAcount.png"), n_all)
    fig_theme_counts(all_rows, os.path.join(args.outdir, "layers_per_theme.png"), n_all)


if __name__ == "__main__":
    main()
