# -*- coding: utf-8 -*-
"""test_focal_mean.py -- unit test for common.focal_mean.

The defect being guarded against: a window containing ZERO valid cells must
produce NoData, never a value. Historically the denominator was a float
uniform_filter of the validity mask, which returns a coefficient-rounding
residue (~1e-17) instead of exact 0 on empty windows, so the `c > 0` guard
passed and emitted arbitrary garbage.

Run:  E:\\CHECO26\\.venv\\Scripts\\python.exe test_focal_mean.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from scripts import common  # noqa: E402


def test_empty_window_is_nodata():
    """A 3x3 window with no valid cell must be NoData, not a number."""
    a = np.full((7, 7), np.nan, dtype=np.float32)
    a[0, 0] = 1.0
    a[0, 1] = 3.0
    out = common.focal_mean(a, 1, invalid=np.isnan(a))
    # every cell whose 3x3 window touches nothing must be NaN
    for (y, x) in [(6, 6), (3, 3), (0, 6), (6, 0), (4, 4)]:
        assert not np.isfinite(out[y, x]), (
            "empty window at (%d,%d) produced %r" % (y, x, out[y, x]))
    # cells inside the valid cluster must be finite
    assert np.isfinite(out[0, 0]) and np.isfinite(out[0, 1])


def test_bounds_are_respected():
    """A mean can never leave the min/max of its inputs."""
    rng = np.random.default_rng(0)
    a = rng.normal(10.0, 3.0, size=(80, 90)).astype(np.float32)
    hole = np.zeros(a.shape, dtype=bool)
    hole[30:60, 30:70] = True          # a big NoData hole
    a[hole] = np.nan
    for radius in (1, 5, 10, 20):
        out = common.focal_mean(a, radius, invalid=np.isnan(a))
        finite = np.isfinite(out)
        assert (out[finite] >= np.nanmin(a) - 1e-4).all()
        assert (out[finite] <= np.nanmax(a) + 1e-4).all(), "radius %d escaped the input range" % radius


def test_no_value_on_empty_window_realistic():
    """Hole-edge cells: with a large hole, many windows are empty."""
    a = np.full((200, 200), np.nan, dtype=np.float32)
    a[0:50, :] = 5.0                   # valid strip only
    out = common.focal_mean(a, 1, invalid=np.isnan(a))
    # row 60 is 10 rows below the strip -> its 3x3 window is entirely NoData
    assert not np.isfinite(out[60, 100]), "row 60 should be NoData, got %r" % out[60, 100]
    # row 50 is adjacent -> finite
    assert np.isfinite(out[50, 100])


def test_matches_bruteforce():
    """Compare against an explicit per-window loop on a small array."""
    rng = np.random.default_rng(1)
    a = rng.uniform(0, 1, size=(25, 25)).astype(np.float64)
    a[5:15, 5:15] = np.nan
    for radius in (1, 2, 3):
        out = common.focal_mean(a, radius)
        size = 2 * radius + 1
        for y in range(radius, 25 - radius):
            for x in range(radius, 25 - radius):
                w = a[y - radius:y + radius + 1, x - radius:x + radius + 1]
                v = w[np.isfinite(w)]
                if v.size == 0:
                    assert not np.isfinite(out[y, x]), \
                        "brute-force empty window mismatch at (%d,%d)" % (y, x)
                else:
                    assert abs(out[y, x] - v.mean()) < 1e-5, \
                        "brute-force mean mismatch at (%d,%d)" % (y, x)


def test_all_ones_is_one():
    """Sanity: a constant valid field stays constant."""
    a = np.ones((40, 40), dtype=np.float32)
    for radius in (1, 5, 10, 20):
        out = common.focal_mean(a, radius)
        assert np.allclose(out, 1.0, atol=1e-6)


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t()
            print("PASS  %s" % t.__name__)
        except AssertionError as e:
            failed += 1
            print("FAIL  %s : %s" % (t.__name__, e))
        except Exception as e:
            failed += 1
            print("ERROR %s : %r" % (t.__name__, e))
    print("\n%d/%d passed" % (len(tests) - failed, len(tests)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
