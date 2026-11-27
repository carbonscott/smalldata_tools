#!/bin/bash
# run_thr.sh <recording wd> <out dir> <config: thr_mfx|thr_mix> <MPI ranks> <smalldata_tools tree> [timing]
#
# fix-threshold harness: smalldata_tools' lcls2 producer from the given tree with prod_config_<config>.py on the
# shared recorded simulated Jungfrau run, then sumcheck.py (an independent single-process psana2 read-back of every
# Sums key and every subsampled image). With "timing", shim/sitecustomize.py times every processSums call.
# Adapted from the issues' run_maxsum.sh (calibration stand-in calibws_jf.py, logbook shim).
#
# One Slurm step; re-executes itself inside `unshare -rn` (a private network namespace, lo only) so that
# nothing can reach a facility service. The first lines of <out>/run.log are the provenance header, written here.
set -u
H=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h1
X=$H/harness
REC=$(readlink -f "$1"); OUT=$(readlink -f "$2"); CFG=$3; RANKS=$4
SDT=$(readlink -f "$5"); TIMING=${6:-}
SELF=$(readlink -f "$0")
if [ -z "${THR_INSIDE:-}" ]; then
  mkdir -p "$OUT"
  {
    echo "# host: $(hostname)"
    echo "# date: $(date -u +%FT%TZ)"
    echo "# commit: smalldata_tools $(git -C "$SDT" rev-parse HEAD) ($(git -C "$SDT" rev-parse --abbrev-ref HEAD); uncommitted: $(git -C "$SDT" diff --stat | tail -1))"
    echo "# cmd: run_thr.sh $REC $OUT $CFG $RANKS $SDT $TIMING"
    echo "# scripts sha256: $(cd "$X" && sha256sum run_thr.sh sumcheck.py prod_config_$CFG.py calibws_jf.py shim/sitecustomize.py | awk '{printf "%s:%s ", $2, substr($1,1,12)}')"
    echo "# psana env: $(readlink -f /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh)"
    echo "# slurm: job ${SLURM_JOB_ID:-none} step ${SLURM_STEP_ID:-none} cpus ${SLURM_CPUS_PER_TASK:-?}"
  } > "$OUT/run.log"
  THR_INSIDE=1 exec unshare -rn bash "$SELF" "$@" >> "$OUT/run.log" 2>&1
  echo "re-exec failed" >> "$OUT/run.log"; exit 2
fi
log() { echo "$(date -u +%FT%TZ) $*"; }
ip link set lo up
up=$(ip -o link show up | awk -F': ' '{print $2}' | tr '\n' ' ')
log "network namespace $(readlink /proc/self/ns/net); links up: $up"
[ "$up" = "lo " ] || { log "REFUSING: lo is not the only link up"; exit 3; }
EXP=mfxsim0001; PORT=$((31000 + RANDOM % 900))
mkdir -p "$OUT/h5" "$OUT/xtc/smalldata"
XTC=$(ls -d "$REC"/data/*/*/xtc | head -1)
for f in "$XTC"/*.xtc2; do b=$(basename "$f"); ln -sf "$f" "$OUT/xtc/${b/tstx00001/$EXP}"; done
for f in "$XTC"/smalldata/*.xtc2; do b=$(basename "$f"); ln -sf "$f" "$OUT/xtc/smalldata/${b/tstx00001/$EXP}"; done
log "recording $REC: $(ls "$OUT/xtc" | grep -c xtc2) bigdata, $(ls "$OUT/xtc/smalldata" | grep -c xtc2) smalldata xtc2 file(s), presented as experiment $EXP run 1"

set +u
source /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh >/dev/null 2>&1
unset CALIB_JWT ARP_JOB_ID ARP_LOCATION JID_UPDATE_COUNTERS
export KRB5CCNAME=FILE:/nonexistent-thr PYTHONDONTWRITEBYTECODE=1
export HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 NO_PROXY=127.0.0.1,localhost
export http_proxy=$HTTP_PROXY https_proxy=$HTTPS_PROXY no_proxy=$NO_PROXY
export LCLS_CALIB_HTTP=http://127.0.0.1:$PORT
export X6_LGBK_URL=http://127.0.0.1:$PORT      # shim/sitecustomize.py: psana's logbook file-list URL -> stand-in
export PYTHONPATH=$X/shim:$SDT${PYTHONPATH:+:$PYTHONPATH}
export PS_SRV_NODES=1 PS_EB_NODES=1
export OMPI_MCA_osc=^ucx OMPI_MCA_plm=isolated OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
[ "$TIMING" = timing ] && { export THR_TIMING_DIR=$OUT/timing; rm -rf "$THR_TIMING_DIR"; }
log "psana2 release: $(python -c 'import psana,os; print(os.path.dirname(psana.__file__))' 2>/dev/null)"

python "$X/calibws_jf.py" --port $PORT --log "$OUT/calibws.jsonl" > "$OUT/calibws.out" 2>&1 &
CWS=$!
for i in $(seq 50); do grep -q ready "$OUT/calibws.out" 2>/dev/null && break; sleep 0.2; done
cat "$OUT/calibws.out"

cp "$X/prod_config_$CFG.py" "$SDT/lcls2_producers/prod_config_$CFG.py"
log "processSums in this tree (smalldata_tools/lcls2/DetObject.py):"
grep -n -A12 'def processSums' "$SDT/smalldata_tools/lcls2/DetObject.py" | head -13
log "sum keys and subsampling of prod_config_$CFG.py:"
grep -n -A8 'def get_sum_algos\|def get_subsample_config' "$X/prod_config_$CFG.py" | grep -v '^\s*$' | head -20
log "ranks: $RANKS MPI ranks = 1 smd0 + $PS_EB_NODES event builder + $PS_SRV_NODES srv + $((RANKS - 2 - PS_SRV_NODES)) bigdata rank(s)"
T0=$(date +%s)
log "\$ mpirun -n $RANKS python -m mpi4py.run smd_producer.py --experiment $EXP --run 1 --psdm_dir <out>/xtc --directory <out>/h5 --noarch --all_events --config $CFG"
mpirun --map-by :OVERSUBSCRIBE -n "$RANKS" python -u -m mpi4py.run "$SDT/lcls2_producers/smd_producer.py" \
  --experiment $EXP --run 1 --psdm_dir "$OUT/xtc" --directory "$OUT/h5" --noarch --all_events --config $CFG \
  > "$OUT/producer.log" 2>&1
PRC=$?
log "smd_producer: exit $PRC in $(( $(date +%s) - T0 )) s; log $(basename "$OUT")/producer.log ($(grep -c 'Failed analyzing' "$OUT/producer.log") 'Failed analyzing' lines)"
log "stand-in requests: $(wc -l < "$OUT/calibws.jsonl") ($(grep -c '"status": 200' "$OUT/calibws.jsonl") answered 200; logbook requests $(grep -c '/lgbk/' "$OUT/calibws.jsonl"))"
H5=$OUT/h5/${EXP}_Run0001.h5
[ -s "$H5" ] || { log "no h5 written"; tail -20 "$OUT/producer.log"; kill $CWS; exit 1; }
if [ "$TIMING" = timing ]; then
  log "processSums timing (shim/sitecustomize.py, perf_counter_ns per call, files $(ls "$THR_TIMING_DIR" | tr '\n' ' ')):"
  python - "$THR_TIMING_DIR" <<'PY'
import glob, sys
import numpy as np
for fn in sorted(glob.glob(sys.argv[1] + "/pid*.txt")):
    t = np.array([int(l.split()[1]) for l in open(fn)], dtype=np.float64) / 1e3
    print("  %s: %d processSums calls; median %.1f us, p10 %.1f us, p90 %.1f us, mean %.1f us"
          % (fn.split("/")[-1], t.size, np.median(t), np.percentile(t, 10), np.percentile(t, 90), t.mean()))
PY
fi
log "\$ python sumcheck.py --h5 $(basename "$H5") ${REF_H5:+--ref-h5 $REF_H5}"
python "$X/sumcheck.py" --h5 "$H5" --xtc-dir "$OUT/xtc" --exp $EXP --run 1 ${REF_H5:+--ref-h5 "$REF_H5"}
RC=$?
kill $CWS 2>/dev/null
log "sumcheck exit $RC"
echo "exit $RC"
