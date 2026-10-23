#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the README "Spatial characteristics" boundary figure
(figs/china_boundary.png).

The national boundary drawn in the database CRS (China_Albers), with the grid
extent corner values as axis ticks,
so the figure and the extent row of the README table refer to the same numbers.
The nine-dash line is drawn on the main map and the South China Sea is shown as
a separate inset panel on the right (standard China map layout, compliant).
"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import geopandas as gpd

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.environ.get("GEOVIZ_ASSETS",
                      r"C:\Users\LQ\.agents\skills\geo-viz\assets\china")
OUT = os.path.join(HERE, "china_boundary.png")

# China_Albers WKT (identical to pipeline_r/config.yaml)
ALBERS_WKT = (
    'PROJCS["China_Albers",GEOGCS["WGS 84",DATUM["WGS_1984",'
    'SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],'
    'UNIT["degree",0.0174532925199433]],PROJECTION["Albers_Conic_Equal_Area"],'
    'PARAMETER["latitude_of_center",0],PARAMETER["longitude_of_center",105],'
    'PARAMETER["standard_parallel_1",25],PARAMETER["standard_parallel_2",47],'
    'PARAMETER["false_easting",0],PARAMETER["false_northing",0],'
    'UNIT["metre",1]]')

EXTENT = (-2648000, 1867000, 2213000, 5929000)  # xmin, ymin, xmax, ymax
EDGE = "#3D6CA8"     # boundary / dash-line colour
FILL = "#EAF1F9"     # polygon fill
TICK = "#3A3A3A"

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["DejaVu Sans", "Arial", "Helvetica"],
    "axes.edgecolor": TICK,
    "axes.labelcolor": TICK,
    "text.color": TICK,
    "xtick.color": TICK,
    "ytick.color": TICK,
})


def main():
    china = gpd.read_file(os.path.join(ASSETS, "china.shp")).to_crs(ALBERS_WKT)
    dash = gpd.read_file(os.path.join(ASSETS, "dashline.shp")).to_crs(ALBERS_WKT)
    outline = china.dissolve()          # merge provinces -> national outline only
    border = outline.boundary

    fig = plt.figure(figsize=(8.4, 6.0))
    gs = fig.add_gridspec(1, 2, width_ratios=[3.0, 1.0], wspace=0.04,
                          left=0.02, right=0.98, top=0.98, bottom=0.10)
    ax = fig.add_subplot(gs[0, 0])
    fig.patch.set_alpha(0.0)
    ax.patch.set_alpha(0.0)

    outline.plot(ax=ax, facecolor=FILL, edgecolor="none")
    border.plot(ax=ax, color=EDGE, linewidth=1.1)
    dash.plot(ax=ax, color=EDGE, linewidth=0.9)

    xmin, ymin, xmax, ymax = EXTENT
    ax.set_xlim(xmin, xmax)
    ax.set_ylim(ymin, ymax)
    ax.set_aspect("equal")
    ax.set_xticks([xmin, xmax])
    ax.set_yticks([ymin, ymax])
    ax.ticklabel_format(useOffset=False, style="plain")
    ax.tick_params(labelsize=9)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)

    # ---- South China Sea inset panel (right, standard China map layout) ----
    axins = fig.add_subplot(gs[0, 1])
    axins.patch.set_alpha(0.0)
    outline.plot(ax=axins, facecolor=FILL, edgecolor="none")
    border.plot(ax=axins, color=EDGE, linewidth=0.5)
    dash.plot(ax=axins, color=EDGE, linewidth=0.8)
    b = dash.total_bounds  # minx, miny, maxx, maxy (Albers metres)
    pad_x = 0.10 * (b[2] - b[0])
    pad_y = 0.10 * (b[3] - b[1])
    axins.set_xlim(b[0] - pad_x, b[2] + pad_x)
    axins.set_ylim(b[1] - pad_y, b[3] + pad_y)
    axins.set_aspect("equal")
    axins.set_xticks([])
    axins.set_yticks([])
    for spine in axins.spines.values():
        spine.set_edgecolor(EDGE)
        spine.set_linewidth(0.7)
    axins.set_title("South China Sea", fontsize=9, color=TICK, pad=4)

    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    fig.savefig(OUT, dpi=200, transparent=True, bbox_inches="tight")
    plt.close(fig)
    print("written:", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
