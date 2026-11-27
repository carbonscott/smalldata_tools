"""h5cmp.py A.h5 B.h5: compare every dataset of two smalldata h5 files (h5py read-back, nothing from smalldata_tools).
Per dataset: byte-identical (sha256 of the raw bytes)? If not, and the dataset has one row per event, compare
again with the rows of each file sorted by timestamp (with several reading ranks the row order of the h5 differs
from run to run). Other arrays that differ (e.g. Sums, whose float32 sums depend on how events were split over
ranks) get their max |A-B| relative to max |A|."""
import sys, hashlib, h5py, numpy as np
def load(path):
    out = {}
    with h5py.File(path, "r") as f:
        f.visititems(lambda n, o: out.__setitem__(n, np.asarray(o[()])) if isinstance(o, h5py.Dataset) else None)
    return out
def sha(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()
a, b = load(sys.argv[1]), load(sys.argv[2])
print("A:", sys.argv[1]); print("B:", sys.argv[2])
print("datasets: A %d, B %d" % (len(a), len(b)))
print("only in A:", sorted(set(a) - set(b)))
print("only in B:", sorted(set(b) - set(a)))
n = len(a.get("timestamp", []))
oa = np.argsort(a["timestamp"], kind="stable") if n else None
ob = np.argsort(b["timestamp"], kind="stable") if n else None
common = sorted(set(a) & set(b))
same, same_sorted, close, diff = [], [], [], []
for k in common:
    x, y = a[k], b[k]
    if x.dtype == y.dtype and x.shape == y.shape and sha(x) == sha(y):
        same.append(k)
    elif n and x.shape == y.shape and x.ndim >= 1 and x.shape[0] == n and sha(x[oa]) == sha(y[ob]):
        same_sorted.append(k)
    elif x.shape == y.shape and np.issubdtype(x.dtype, np.floating):
        r = float(np.max(np.abs(x.astype(np.float64) - y)) / max(np.max(np.abs(x)), 1e-30))
        close.append((k, r))
    else:
        diff.append(k)
print("common datasets: %d; byte-identical: %d; identical after sorting rows by timestamp: %d; "
      "float arrays not identical: %d; other differences: %d" % (len(common), len(same), len(same_sorted), len(close), len(diff)))
for k in same_sorted:
    print("  same after timestamp sort: %s" % k)
for k, r in close:
    print("  float differs: %-34s max|A-B|/max|A| = %.2e" % (k, r))
for k in diff:
    print("  DIFFERS: %s" % k)
