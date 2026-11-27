#!/usr/bin/env python
"""sumcheck.py --h5 H5 --xtc-dir DIR --exp EXP --run N [--ref-h5 H5] [--det jungfrau]

Independent read-back for fix-threshold: one psana2 process (no MPI, no smalldata_tools) reads every event,
takes det.raw.calib(evt) (float32, as the producer sees it) and computes every Sums key found in the h5 from
its name alone:
    calib                 sum_n c_n
    calib_square          sum_n c_n**2
    calib_thresADU<N>     sum_n c_n * [c_n >= N]
    calib_nhits           sum_n (1 if c_n > 0 else c_n)   (LCLS-I DetObject's definition, and master's when listed first)
    calib_max             max_n c_n
(threshold first, then nhits, then square.) The terms are float32 and summed in float32 in event order, as
one bigdata rank does, so each h5 image must equal the definition bit for bit (4 MPI ranks = 1 bigdata rank);
the largest difference is also printed in float64 against a float64 sum. Then every subsampled full image in the h5 is matched by timestamp
to its event and compared with that event's c_n. With --ref-h5 (master's h5), each Sums key of the two files is
also compared byte for byte.
"""
import argparse
import re
import sys

import h5py
import numpy as np
from psana import DataSource

p = argparse.ArgumentParser()
p.add_argument("--h5", required=True)
p.add_argument("--xtc-dir", required=True)
p.add_argument("--exp", required=True)
p.add_argument("--run", type=int, required=True)
p.add_argument("--det", default="jungfrau")
p.add_argument("--ref-h5", default=None)
a = p.parse_args()

with h5py.File(a.h5, "r") as f:
    keys = sorted(k[len(a.det) + 1:] for k in f["Sums"].keys() if k.startswith(a.det + "_"))
    sums = {k: np.asarray(f["Sums/%s_%s" % (a.det, k)][()]) for k in keys}
    sub = []
    def visit(name, obj):
        if isinstance(obj, h5py.Dataset) and obj.ndim >= 3 and "subsample" in name and name.endswith("/data"):
            sub.append(name)
    f.visititems(visit)
    subs = {}
    for name in sub:
        ts_name = name.rsplit("/", 1)[0] + "/timestamp"
        if ts_name in f:
            subs[name] = (np.asarray(f[name][()]), np.asarray(f[ts_name][()]))
print("h5: %s  Sums keys for %s: %s" % (a.h5.split("/")[-1], a.det, ", ".join(keys)))
for name, (d, ts) in subs.items():
    print("h5: subsampled images %s shape %s dtype %s, %d timestamps" % (name, d.shape, d.dtype, len(ts)))

def parse(k):
    thres = None
    for s in k.split("_"):
        m = re.fullmatch(r"thresADU(-?[0-9.]+)", s)
        if m:
            thres = float(m.group(1))
    return thres, "nhits" in k, "square" in k, "max" in k

want_ts = {}
for name, (d, ts) in subs.items():
    for i, t in enumerate(ts):
        want_ts.setdefault(int(t), []).append((name, i))

ds = DataSource(exp=a.exp, run=a.run, dir=a.xtc_dir)
run = next(ds.runs())
det = run.Detector(a.det)
acc = {k: None for k in keys}
acc64 = {k: None for k in keys}
n = 0
sub_res = []
for evt in run.events():
    c = det.raw.calib(evt)
    if c is None:
        continue
    c = np.asarray(c, dtype=np.float32)
    n += 1
    for k in keys:
        thres, nhits, square, isMax = parse(k)
        t = c.copy()
        if thres is not None and thres > 1e-9:
            t = np.where(c >= np.float32(thres), t, np.float32(0))
        if nhits:
            t = np.where(t > 0, np.float32(1), t)
        if square:
            t = t * t
        if isMax:
            acc[k] = t if acc[k] is None else np.maximum(acc[k], t)
            acc64[k] = acc[k]
        else:
            acc[k] = t.copy() if acc[k] is None else acc[k] + t
            t64 = t.astype(np.float64)
            acc64[k] = t64 if acc64[k] is None else acc64[k] + t64
    for name, i in want_ts.get(int(evt.timestamp), []):
        img = subs[name][0][i].reshape(c.shape)
        diff = img != c
        lt5 = (c < 5) & (c != 0)
        sub_res.append((name, i, int(diff.sum()), int((diff & (img == 0)).sum()), int(lt5.sum())))
print("truth: %d events with data read by one psana2 process; det.raw.calib shape %s" % (n, c.shape))

bad = 0
for k in keys:
    h = sums[k].reshape(acc[k].shape)
    ok = h == acc[k]
    nb = int((~ok).sum())
    bad += nb > 0
    zero_wrong = int(((h == 0) & (acc[k] != 0)).sum())
    print("CHECK Sums/%s_%s %s: %d of %d pixels equal the definition bit for bit; %d differ (%d of them 0 in the h5); "
          "max |h5 - float64 truth| %.4g" % (a.det, k, "PASS" if nb == 0 else "FAIL", ok.sum(), ok.size, nb,
                                             zero_wrong, np.abs(h.astype(np.float64) - acc64[k]).max()))
nsub = len(sub_res)
nsub_bad = sum(1 for r in sub_res if r[2])
for name, i, nd, nz, nlt5 in sub_res[:3] + sub_res[-1:]:
    print("  subsampled image %s[%d]: %d pixels differ from the event's calib (%d of them 0 in the h5); "
          "%d pixels of the event have calib < 5 and calib != 0" % (name, i, nd, nz, nlt5))
if nsub:
    print("CHECK subsampled full images %s: %d of %d equal their event's calib on every pixel"
          % ("PASS" if nsub_bad == 0 else "FAIL", nsub - nsub_bad, nsub))
    bad += nsub_bad > 0
else:
    print("CHECK subsampled full images NOT RUN: none found in the h5")
if a.ref_h5:
    with h5py.File(a.ref_h5, "r") as g:
        for k in keys:
            r = np.asarray(g["Sums/%s_%s" % (a.det, k)][()])
            same = r.dtype == sums[k].dtype and r.shape == sums[k].shape and r.tobytes() == sums[k].tobytes()
            print("vs ref %s: Sums/%s_%s %s (dtype %s/%s)" % (a.ref_h5.split("/")[-1], a.det, k,
                  "byte-identical" if same else "DIFFERENT (%d pixels)" % int((r != sums[k]).sum()), sums[k].dtype, r.dtype))
print("VERDICT: %s" % ("every Sums key equals its definition and every saved image its event" if bad == 0
                       else "%d check(s) FAIL" % bad))
sys.exit(1 if bad else 0)
