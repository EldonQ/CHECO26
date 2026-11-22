"""Fetch the Copernicus GLO-90 COG tiles intersecting the CHECO26 mask."""

import argparse
import csv
import hashlib
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import local

import numpy as np
import rasterio
import requests
from pyproj import Transformer


BUCKET = "https://copernicus-dem-90m.s3.amazonaws.com"
connections = local()


def tile_names(path):
    with rasterio.open(path) as src:
        rows, cols = np.nonzero(src.read(1) == 1)
        tx = src.transform
        project = Transformer.from_crs(src.crs, 4326, always_xy=True)
        needed = set()
        # Include the corners of each target cell and an extra two source pixels.
        for oy in (-0.7, 0.7):
            for ox in (-0.7, 0.7):
                lon, lat = project.transform(tx.c + (cols + 0.5 + ox) * tx.a,
                                             tx.f + (rows + 0.5 + oy) * tx.e)
                needed.update(np.unique(np.floor(lat).astype(int) * 360 +
                                        np.floor(lon).astype(int)))
    return sorted(f"Copernicus_DSM_COG_30_N{k // 360:02d}_00_E{k % 360:03d}_00_DEM"
                  for k in needed)


def download(key, directory):
    url = f"{BUCKET}/{key}/{key}.tif"
    dest = directory / f"{key}.tif"
    if dest.is_file():
        with dest.open("rb") as source:
            return dest.name, url, hashlib.file_digest(source, "sha256").hexdigest()
    if not hasattr(connections, "session"):
        connections.session = requests.Session()
    for attempt in range(4):
        try:
            response = connections.session.get(url, timeout=(15, 60))
            response.raise_for_status()
            data = response.content
            etag = response.headers.get("ETag", "").strip('"')
            if len(etag) == 32 and hashlib.md5(data).hexdigest() != etag:
                raise ValueError(f"Source checksum mismatch: {key}")
            tmp = dest.with_suffix(".part")
            tmp.write_bytes(data)
            tmp.replace(dest)
            return dest.name, url, hashlib.sha256(data).hexdigest()
        except (requests.RequestException, ValueError):
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mask", type=Path)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    response = requests.get(f"{BUCKET}/tileList.txt", timeout=(15, 60))
    response.raise_for_status()
    available = set(response.text.splitlines())
    tiles = tile_names(args.mask)
    keys = [tile for tile in tiles if tile in available]
    missing = sorted(set(tiles) - available)
    if not keys:
        raise RuntimeError("No Copernicus tiles matched the grid")
    args.directory.mkdir(parents=True, exist_ok=True)
    print(f"Fetching {len(keys)} source tiles. {len(missing)} grid intersections lack AWS tiles.",
          flush=True)
    with ThreadPoolExecutor(max_workers=10) as pool:
        results = []
        for index, record in enumerate(pool.map(lambda key: download(key, args.directory), keys), 1):
            results.append(record)
            if index % 100 == 0 or index == len(keys):
                print(index, len(keys), flush=True)
    with (args.directory / "source_tiles.csv").open("w", newline="", encoding="utf-8") as out:
        writer = csv.writer(out)
        writer.writerow(["filename", "source_url", "sha256"])
        writer.writerows(results)


if __name__ == "__main__":
    main()
