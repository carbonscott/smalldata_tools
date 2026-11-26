#!/usr/bin/env python
"""maxcheck.py --h5 H5 --xtc-dir DIR --exp EXP --run N [--ref-h5 H5]

Independent truth for Sums/jungfrau_calib_max: one psana2 process (no MPI, no smalldata_tools) reads every
event of the run, takes det.raw.calib(evt) and keeps the per-pixel maximum. Prints the h5's calib_max against
it: global maxima, their ratio, and how many pixels agree within float32 rounding. With --ref-h5, also the
pixel-by-pixel ratio of the two h5 files' calib_max.
"""
import argparse
import h5py
import numpy as np
from psana import DataSource

p = argparse.ArgumentParser()
p.add_argument("--h5", required=True)
p.add_argument("--xtc-dir", required=True)
p.add_argument("--exp", required=True)
p.add_argument("--run", type=int, required=True)
p.add_argument("--ref-h5", default=None)
a = p.parse_args()

ds = DataSource(exp=a.exp, run=a.run, dir=a.xtc_dir)
run = next(ds.runs())
det = run.Detector("jungfrau")
tmax, n = None, 0
for evt in run.events():
    c = det.raw.calib(evt)
    if c is None:
        continue
    c = np.asarray(c, dtype=np.float64)
    tmax = c.copy() if tmax is None else np.maximum(tmax, c)
    n += 1
print("truth: %d events read by one psana2 process; per-pixel max of det.raw.calib, shape %s" % (n, tmax.shape))

with h5py.File(a.h5, "r") as f:
    h = np.asarray(f["Sums/jungfrau_calib_max"][()], dtype=np.float64).reshape(tmax.shape)
    nrows = len(f["timestamp"]) if "timestamp" in f else -1
print("h5:    %s  Sums/jungfrau_calib_max shape %s, %d event rows" % (a.h5.split("/")[-1], h.shape, nrows))
on = (tmax > 0) & ~((h == 0) & (tmax != 0))
print("global max: truth %.3f  h5 %.3f  ratio h5/truth %.3f" % (tmax.max(), h.max(), h.max() / tmax.max()))
masked = (h == 0) & (tmax != 0)
print("pixels 0 in the h5 but not in the truth (smalldata_tools' bad-pixel mask): %d" % masked.sum())
close = np.isclose(h, tmax, rtol=1e-5, atol=1e-3) | masked
print("pixels equal to the truth (rtol 1e-5), masked pixels counted as equal: %d of %d" % (close.sum(), close.size))
r = h[on] / tmax[on]
print("per-pixel ratio h5/truth over %d pixels with truth > 0: min %.3f  median %.3f  max %.3f"
      % (on.sum(), r.min(), np.median(r), r.max()))
print("pixels where h5 exceeds the truth by > 1%%: %d" % (h > tmax * 1.01 + 1e-3).sum())
if a.ref_h5:
    with h5py.File(a.ref_h5, "r") as f:
        g = np.asarray(f["Sums/jungfrau_calib_max"][()], dtype=np.float64).reshape(tmax.shape)
    m = g > 0
    rr = h[m] / g[m]
    print("vs %s: per-pixel ratio min %.3f median %.3f max %.3f" % (a.ref_h5.split("/")[-1], rr.min(), np.median(rr), rr.max()))
print("VERDICT: %s" % ("calib_max EQUALS the per-pixel max" if close.all() else
                       "calib_max is NOT the per-pixel max (%d pixels differ)" % (~close).sum()))
