#!/bin/bash
# run_swallow.sh RUN_DIR OUT_DIR CONFIG [asis|fixed]
#   CONFIG  x6roi2d : the Jungfrau ROIs written 2-D ([[rows],[cols]]), the format MFX's prod_config uses for epix100
#           x6sim   : the same config with the ROIs written for the (1, 512, 1024) Jungfrau data (control)
#   asis    : smalldata_tools at the upstream master head, unchanged (default)
#   fixed   : the same with fix-log-exception.patch applied (in a git worktree)
# Runs slac-lcls/smalldata_tools lcls2_producers/smd_producer.py with the psana2 release on a recorded simulated
# Jungfrau run, offline: launch it as a Slurm step inside a private network namespace, e.g.
#   srun --jobid=47203681 --overlap --ntasks=1 --cpus-per-task=8 --mem=32G unshare -rn bash run_swallow.sh RUN OUT x6roi2d
# The calibration DB is the x6 loopback stand-in (calibws_jf.py) through psana2's LCLS_CALIB_HTTP; the logbook
# file-list URL psana2 hard-codes is pointed at the same stand-in by shim/sitecustomize.py (see psana-logbook).
# Writes OUT/run.log (provenance header first, then a summary written by this script), OUT/producer.log (full),
# OUT/producer-excerpt.log (header + first and last lines of the producer log), OUT/h5/.
set -u
H=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/sim-issues/agents/h1
X=$H/smd-swallow
RUN=$1; OUT=$2; CFG=$3; MODE=${4:-asis}
SDT=$H/smalldata_tools
if [ "$MODE" = fixed ]; then
  SDT=$H/smalldata_tools-fixed
  [ -d $SDT ] || { git -C $H/smalldata_tools worktree add -q --detach $SDT HEAD && git -C $SDT apply $X/fix-log-exception.patch; }
fi
rm -rf "$OUT"; mkdir -p "$OUT/h5" "$OUT/xtc/smalldata"
EXP=mfxsim0001; PORT=31877
cp "$X/prod_config_$CFG.py" "$SDT/lcls2_producers/prod_config_$CFG.py"
LOG=$OUT/run.log
NOTE=""; [ "$MODE" = fixed ] && NOTE=" + fix-log-exception.patch"
hdr() {
  echo "# host: $(hostname)"
  echo "# date: $(date -u +%FT%TZ)"
  echo "# commit: smalldata_tools $(git -C $SDT rev-parse HEAD) (slac-lcls/smalldata_tools master head)$NOTE"
  echo "# cmd: run_swallow.sh $(basename $RUN) $OUT $CFG $MODE"
}
{
hdr
echo "# smalldata_tools tracked changes vs HEAD: $(git -C $SDT diff --stat HEAD | tail -1)"
echo "# recording: $RUN ($(cat $RUN/README.commit 2>/dev/null || true))"
echo "# psana env: psconda.sh -> $(readlink -f /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh)"
echo "# network: $(ip -o link show | awk -F': ' '{print $2}' | tr '\n' ' ')(namespace $(readlink /proc/self/ns/net))"
echo "# config prod_config_$CFG.py ROIs: $(grep -E '^(RING|DARK)_ROI' $X/prod_config_$CFG.py | tr '\n' ' ')"
} > $LOG

XTC=$(ls -d "$RUN"/daq/data/*/*/xtc 2>/dev/null | head -1); [ -n "$XTC" ] || XTC=$RUN/xtc
for f in "$XTC"/*.xtc2; do b=$(basename "$f"); ln -sf "$f" "$OUT/xtc/$(echo $b | sed "s/^[a-z]*[0-9]*-/$EXP-/")"; done
for f in "$XTC"/smalldata/*.xtc2; do b=$(basename "$f"); ln -sf "$f" "$OUT/xtc/smalldata/$(echo $b | sed "s/^[a-z]*[0-9]*-/$EXP-/")"; done
echo "xtc2 files: $(ls $OUT/xtc | grep xtc2 | tr '\n' ' ') smalldata: $(ls $OUT/xtc/smalldata | tr '\n' ' ')" >> $LOG

ip link set lo up 2>/dev/null || true
source /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh >/dev/null 2>&1
unset CALIB_JWT ARP_JOB_ID ARP_LOCATION JID_UPDATE_COUNTERS
export KRB5CCNAME=FILE:/nonexistent-h1
export HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 NO_PROXY=127.0.0.1,localhost
export http_proxy=$HTTP_PROXY https_proxy=$HTTPS_PROXY no_proxy=$NO_PROXY
export LCLS_CALIB_HTTP=http://127.0.0.1:$PORT X6_LGBK_URL=http://127.0.0.1:$PORT
export PYTHONPATH=$X/shim:$SDT${PYTHONPATH:+:$PYTHONPATH}
export PS_SRV_NODES=1 PS_EB_NODES=1
export OMPI_MCA_osc=^ucx OMPI_MCA_plm=isolated OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
python "$X/calibws_jf.py" --port $PORT --log "$OUT/calibws.jsonl" > "$OUT/calibws.out" 2>&1 &
CWS=$!
for i in $(seq 50); do grep -q ready "$OUT/calibws.out" 2>/dev/null && break; sleep 0.2; done
cat "$OUT/calibws.out" >> $LOG

T0=$(date +%s)
echo "\$ mpirun -n 4 python -m mpi4py.run smalldata_tools/lcls2_producers/smd_producer.py --experiment $EXP --run 1 --psdm_dir <OUT>/xtc --directory <OUT>/h5 --noarch --all_events --config $CFG" >> $LOG
mpirun --map-by :OVERSUBSCRIBE -n 4 python -u -m mpi4py.run "$SDT/lcls2_producers/smd_producer.py" \
  --experiment $EXP --run 1 --psdm_dir "$OUT/xtc" --directory "$OUT/h5" --noarch --all_events --config $CFG \
  > "$OUT/producer.log" 2>&1
PRC=$?
kill $CWS 2>/dev/null
P=$OUT/producer.log
{
echo "smd_producer: exit status $PRC after $(( $(date +%s) - T0 )) s (4 MPI ranks); producer.log $(wc -l < $P) lines"
echo "lines 'Failed analyzing det': $(grep -c 'Failed analyzing det' $P)"
echo "distinct reasons printed after them (print(e) / logged), with counts:"
grep -A1 'Failed analyzing det' $P | grep -v -E 'Failed analyzing det|^--$' | sort | uniq -c | sort -rn | head -5
echo "tracebacks in producer.log: $(grep -c '^Traceback' $P)"
H5=$OUT/h5/${EXP}_Run0001.h5
python - "$H5" <<'EOF'
import sys, h5py
p = sys.argv[1]
try:
    f = h5py.File(p, "r")
except Exception as e:
    print("h5: not readable:", e); sys.exit()
n = f["timestamp"].shape[0] if "timestamp" in f else 0
print("h5: %s, %d rows (timestamp)" % (p.split("/")[-1], n))
print("h5 top-level keys:", sorted(f.keys()))
for g in ("jungfrau", "Sums"):
    print("h5 %-9s:" % g, sorted(f[g].keys()) if g in f else "ABSENT")
EOF
} >> $LOG
{ hdr; echo "# excerpt of $P: first 40 and last 15 lines"; echo; head -40 $P; echo "[... $(( $(wc -l < $P) - 55 )) lines not shown ...]"; tail -15 $P; } > $OUT/producer-excerpt.log
cat $LOG
