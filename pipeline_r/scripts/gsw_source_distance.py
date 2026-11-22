"""China-Albers distances from delivery cell centres to JRC extent pixel centres."""

import argparse
from pathlib import Path

import numpy as np
import rasterio
from pyproj import Transformer
from rasterio.windows import Window
from scipy.spatial import cKDTree


def source_windows(source, size):
    for row in range(0, source.height, size):
        for col in range(0, source.width, size):
            yield Window(col, row, min(size, source.width - col), min(size, source.height - row))


def water_blocks(paths, crs, size, seeds_only=False):
    for path in paths:
        with rasterio.open(path) as source:
            ts = source.transform
            if source.count != 1 or source.crs.to_epsg() != 4326 or ts.b or ts.d:
                raise ValueError(f"Unexpected JRC tile grid: {path}")
            project = Transformer.from_crs(source.crs, crs, always_xy=True)
            for window in source_windows(source, size):
                water = source.read(1, window=window) == 1
                if not water.any():
                    continue
                if seeds_only:
                    r, c = divmod(int(water.argmax()), water.shape[1])
                    r, c = np.array([r]), np.array([c])
                else:
                    r, c = np.nonzero(water)
                x = ts.c + (c + window.col_off + 0.5) * ts.a
                y = ts.f + (r + window.row_off + 0.5) * ts.e
                yield np.column_stack(project.transform(x, y, errcheck=True))
        print(f"{'Seeds' if seeds_only else 'Processed'} {path.name}", flush=True)


def distances(mask_path, paths, output, block_size):
    with rasterio.open(mask_path) as grid:
        mask = grid.read(1) == 1
        profile = grid.profile
        crs, tf = grid.crs, grid.transform
    if tf.b or tf.d or crs.is_geographic:
        raise ValueError("A north-up projected grid is required")
    seeds = cKDTree(np.concatenate(list(water_blocks(paths, crs, block_size, seeds_only=True))))
    groups = []
    for row in range(0, mask.shape[0], 64):
        for col in range(0, mask.shape[1], 64):
            r, c = np.nonzero(mask[row:row + 64, col:col + 64])
            if not r.size:
                continue
            r, c = r + row, c + col
            x, y = tf.c + (c + 0.5) * tf.a, tf.f + (r + 0.5) * tf.e
            queries = np.column_stack([x, y])
            best = seeds.query(queries)[0]
            groups.append((r, c, queries, best))

    minima = np.array([group[2].min(axis=0) for group in groups])
    maxima = np.array([group[2].max(axis=0) for group in groups])
    caps = np.array([group[3].max() for group in groups])
    for water in water_blocks(paths, crs, block_size):
        lo, hi = water.min(axis=0), water.max(axis=0)
        offset = np.maximum(0, np.maximum(lo - maxima, minima - hi))
        relevant = np.flatnonzero(np.hypot(offset[:, 0], offset[:, 1]) <= caps + 1e-8)
        tree = None
        for j in relevant:
            _, _, queries, best = groups[j]
            gap = np.maximum(0, np.maximum(lo - queries, queries - hi))
            eligible = np.hypot(gap[:, 0], gap[:, 1]) <= best + 1e-8
            if eligible.any():
                if tree is None:
                    tree = cKDTree(water)
                best[eligible] = np.minimum(best[eligible], tree.query(queries[eligible])[0])
                caps[j] = best.max()

    result = np.full(mask.shape, -9999, dtype="float32")
    for row, col, _, d in groups:
        result[row, col] = d
    if not np.isfinite(result[mask]).all():
        raise ValueError("Invalid distance for a delivery cell")
    profile.update(dtype="float32", nodata=-9999, count=1, tiled=True, compress="deflate",
                   blockxsize=256, blockysize=256, predictor=3, photometric="minisblack")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".tmp.tif")
    with rasterio.open(temporary, "w", **profile) as dst:
        dst.write(result, 1)
    temporary.replace(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mask", type=Path)
    parser.add_argument("tiles", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--block-size", type=int, default=1024)
    args = parser.parse_args()
    paths = sorted(args.tiles.glob("extent_*_v1_5_2024.tif"))
    if len(paths) != 42 or args.block_size < 1:
        parser.error("Expected 42 JRC v1.5 extent tiles and a positive block size")
    distances(args.mask, paths, args.output, args.block_size)


if __name__ == "__main__":
    main()
