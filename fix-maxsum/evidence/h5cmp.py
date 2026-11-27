#!/usr/bin/env python
"""h5cmp.py A.h5 B.h5 : compare the Sums group of two smalldata h5 files, dataset by dataset.

For every Sums dataset: shape, dtype and whether the raw bytes are identical (numpy tobytes). For a
dataset that differs: how many elements differ and the per-element ratio A/B where B != 0.
Also reports the event-row count of both files. Reads only h5py; no smalldata_tools, no psana.
"""
import sys
import h5py
import numpy as np

a, b = sys.argv[1], sys.argv[2]
fa, fb = h5py.File(a, "r"), h5py.File(b, "r")
print("A: %s   B: %s" % (a.split("/")[-3] + "/" + a.split("/")[-1], b.split("/")[-3] + "/" + b.split("/")[-1]))
print("event rows: A %d  B %d" % (len(fa["timestamp"]), len(fb["timestamp"])))
ka, kb = sorted(fa["Sums"].keys()), sorted(fb["Sums"].keys())
print("Sums keys A: %s" % ", ".join(ka))
if ka != kb:
    print("Sums keys B differ: %s" % ", ".join(kb))
for k in ka:
    if k not in fb["Sums"]:
        continue
    x, y = fa["Sums"][k][()], fb["Sums"][k][()]
    same = x.shape == y.shape and x.dtype == y.dtype and x.tobytes() == y.tobytes()
    line = "Sums/%-28s %s %-8s %s" % (k, x.shape, x.dtype, "BYTE-IDENTICAL" if same else "DIFFERS")
    if not same and x.shape == y.shape:
        d = x != y
        m = y != 0
        r = x[m].astype(np.float64) / y[m]
        rel = np.abs(x.astype(np.float64) - y) / np.abs(y.astype(np.float64)).max()
        line += ": %d of %d elements differ; ratio A/B min %.3f median %.3f max %.3f; max |A-B|/max|B| %.1e" % (
            d.sum(), d.size, r.min(), np.median(r), r.max(), rel.max())
    print(line)
