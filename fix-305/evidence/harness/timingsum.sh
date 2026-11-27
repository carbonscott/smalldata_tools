#!/bin/bash
# timingsum.sh <runs dir> <out>: per-call processSums times of the timing runs (timing2.sh), one line per run and a
# summary per tree; reads the run logs' headers and the shim's timing files. Run on the login node after timing2.sh.
R=$(readlink -f "$1"); OUT=$2; A=$(dirname "$R")
{
echo "# host: $(hostname)  (summary; the timed runs ran on sdfrome042, job 47367580, see each run's host line below)"
echo "# date: $(date -u +%FT%TZ)"
echo "# commit: smalldata_tools fix $(git -C $A/sdt-fix rev-parse HEAD) vs master $(git -C $A/sdt-master rev-parse HEAD) vs copy-per-key (master + issue's .copy() line, uncommitted)"
echo "# cmd: timingsum.sh $R  (runs from harness/timing2.sh: run_thr.sh <rec> <out> thr_mfx 4 <tree> timing)"
echo "keys (MFX order): calib, calib_square, calib_thresADU1, calib_thresADU5, calib_max; one 512x1024 Jungfrau module, float32"
echo "4 MPI ranks (1 bigdata rank does every processSums call), 8 cpus, same node, runs interleaved master/fix/copy x3"
echo
grep -h '^20.*node load' "$R/timing2.out" | head -9 | sed 's/^/  /'
echo
source /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh >/dev/null 2>&1
python - "$R" <<'PY'
import glob, re, sys
import numpy as np
R = sys.argv[1]
allt = {}
print("%-16s %-12s %-10s %6s %10s %10s %10s" % ("run", "host", "commit", "calls", "median us", "p10 us", "p90 us"))
for i in (1, 2, 3):
    for t in ("master", "fix", "copy"):
        d = "%s/timing-%s-%d" % (R, t, i)
        head = open(d + "/run.log").read().split("\n")[:10]
        host = [l.split()[-1] for l in head if l.startswith("# host:")][0]
        commit = [l.split()[3][:10] for l in head if l.startswith("# commit:")][0]
        fs = glob.glob(d + "/timing/pid*.txt")
        v = np.concatenate([np.loadtxt(f, usecols=1, dtype=np.int64) for f in fs]) / 1e3
        allt.setdefault(t, []).append(v)
        print("%-16s %-12s %-10s %6d %10.1f %10.1f %10.1f" % ("timing-%s-%d" % (t, i), host, commit, v.size,
              np.median(v), np.percentile(v, 10), np.percentile(v, 90)))
print()
m = {t: np.median(np.concatenate(v)) for t, v in allt.items()}
for t in ("master", "fix", "copy"):
    v = np.concatenate(allt[t])
    print("%-7s all %d calls: median %.1f us per event (%+.1f us, %+.1f %% vs master)"
          % (t, v.size, m[t], m[t] - m["master"], 100 * (m[t] / m["master"] - 1)))
PY
} > "$OUT"
