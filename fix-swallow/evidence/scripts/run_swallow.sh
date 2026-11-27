#!/bin/bash
# run_swallow.sh RUN_DIR OUT_DIR CONFIG SDT_DIR [extra producer args, e.g. --strict]
#   Adapted from the issue's evidence/run_swallow.sh (pr-assets 148399ad): same offline set-up, own paths.
#   CONFIG  x6roi2d : the Jungfrau ROIs written 2-D (the failing config of upstream issue 307)
#           x6sim   : the same config with the ROIs written for the (1, 512, 1024) Jungfrau data (clean)
#   SDT_DIR : a smalldata_tools checkout (master or the fix head), used unmodified
#   NP      : MPI ranks (env, default 4)
# Launch as a Slurm step inside a private network namespace:
#   srun --jobid=47367581 --overlap --ntasks=1 --cpus-per-task=8 --mem=32G unshare -rn bash run_swallow.sh ...
set -u
X=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h2/swallow
RUN=$1; OUT=$2; CFG=$3; SDT=$4; shift 4; EXTRA="$*"; NP=${NP:-4}
rm -rf "$OUT"; mkdir -p "$OUT/h5" "$OUT/xtc/smalldata"
EXP=mfxsim0001; PORT=31877
CFGDIR=$OUT/cfg; mkdir -p $CFGDIR
cp "$X/prod_config_$CFG.py" "$SDT/lcls2_producers/prod_config_$CFG.py"
LOG=$OUT/run.log
{
echo "# host: $(hostname)"
echo "# date: $(date -u +%FT%TZ)"
echo "# commit: smalldata_tools $(git -C $SDT rev-parse HEAD)"
echo "# cmd: NP=$NP run_swallow.sh $RUN $OUT $CFG $SDT $EXTRA"
echo "# smalldata_tools tracked changes vs HEAD: $(git -C $SDT diff --stat HEAD | tail -1)"
echo "# branch: $(git -C $SDT log -1 --format='%D | %s')"
echo "# recording: $RUN"
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
export KRB5CCNAME=FILE:/nonexistent-h2
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
echo "\$ timeout 600 mpirun -n $NP python -m mpi4py.run lcls2_producers/smd_producer.py --experiment $EXP --run 1 --psdm_dir <OUT>/xtc --directory <OUT>/h5 --noarch --all_events --config $CFG $EXTRA" >> $LOG
timeout 600 mpirun --map-by :OVERSUBSCRIBE -n $NP python -u -m mpi4py.run "$SDT/lcls2_producers/smd_producer.py" \
  --experiment $EXP --run 1 --psdm_dir "$OUT/xtc" --directory "$OUT/h5" --noarch --all_events --config $CFG $EXTRA \
  > "$OUT/producer.log" 2>&1
PRC=$?
sleep 3  # let Open MPI finish forwarding rank output after an MPI_Abort (--strict) before reading the log
kill $CWS 2>/dev/null
rm -f "$SDT/lcls2_producers/prod_config_$CFG.py"
P=$OUT/producer.log
H5=$OUT/h5/${EXP}_Run0001.h5
{
echo "hang guard: timeout 600 s around mpirun ($( [ $PRC = 124 ] && echo HUNG, killed || echo not triggered))"
echo "smd_producer: exit status $PRC after $(( $(date +%s) - T0 )) s ($NP MPI ranks); producer.log $(wc -l < $P) lines"
echo "lines 'Failed analyzing det': $(grep -a -c 'Failed analyzing det' $P)"
echo "tracebacks in producer.log: $(grep -a -c '^Traceback' $P)"
echo "first failure lines (ERROR + traceback frames):"
grep -a -n -m1 -A14 'ERROR.*Failed analyzing det' $P | grep -a -E 'ERROR|File "|^[0-9]+-[A-Za-z]*Error' | head -10
echo "end-of-job summary lines:"
grep -a -E 'Detector .*: analysis failed on' $P
echo "JOB TIME line: $(grep -a -c 'JOB TIME' $P); MPI abort lines: $(grep -a -c -i 'MPI_ABORT' $P)"
python - "$H5" <<'PY'
import sys, h5py
p = sys.argv[1]
try:
    f = h5py.File(p, "r")
except Exception as e:
    print("h5: not readable:", e); sys.exit()
n = f["timestamp"].shape[0] if "timestamp" in f else 0
print("h5 (read back with h5py): %s, %d rows (timestamp)" % (p.split("/")[-1], n))
print("h5 top-level keys:", sorted(f.keys()))
for g in ("jungfrau", "Sums", "failed_events"):
    print("h5 %-13s:" % g, sorted(f[g].keys()) if g in f else "ABSENT")
if "failed_events" in f:
    for k in f["failed_events"]:
        d = f["failed_events"][k]
        print("h5 failed_events/%s = %s (dtype %s, shape %s)" % (k, d[()].tolist(), d.dtype, d.shape))
PY
} >> $LOG
cat $LOG
