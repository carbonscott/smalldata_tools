#!/bin/bash
# run_maxsum.sh <recording wd> <out dir> <MPI ranks> [smalldata_tools tree]
#
# smd-maxsum: smalldata_tools' lcls2 producer (smd_producer.py, unmodified unless the tree given is the fix branch)
# with a config whose only per-pixel run sum besides calib is calib_max (prod_config_maxsum.py), on a recorded
# simulated Jungfrau run, then maxcheck.py: an independent single-process psana2 per-pixel max of det.raw.calib.
# Adapted from the x6 bench's run_x6.sh (calibration stand-in calibws_jf.py, logbook shim).
#
# One Slurm step; re-executes itself inside `unshare -rn` (a private network namespace, lo only) so that
# nothing can reach a facility service. The first lines of <out>/run.log are the provenance header, written here.
set -u
H=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/sim-issues/agents/h3
M=$H/maxsum
REC=$(readlink -f "$1"); OUT=$(readlink -f "$2"); RANKS=$3
SDT=$(readlink -f "${4:-$H/smalldata_tools}")
SELF=$(readlink -f "$0")
if [ -z "${MAXSUM_INSIDE:-}" ]; then
  mkdir -p "$OUT"
  {
    echo "# host: $(hostname)"
    echo "# date: $(date -u +%FT%TZ)"
    echo "# commit: smalldata_tools $(git -C "$SDT" rev-parse HEAD) ($(git -C "$SDT" log -1 --format=%s | cut -c1-60)) recording lcls2 $(git -C "$H/lcls2" rev-parse --short=12 HEAD)"
    echo "# cmd: run_maxsum.sh $REC $OUT $RANKS $SDT"
    echo "# scripts sha256: $(cd "$M" && sha256sum run_maxsum.sh maxcheck.py prod_config_maxsum.py calibws_jf.py shim/sitecustomize.py | awk '{printf "%s:%s ", $2, substr($1,1,12)}')"
    echo "# psana env: $(readlink -f /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh)"
    echo "# slurm: job ${SLURM_JOB_ID:-none} step ${SLURM_STEP_ID:-none} cpus ${SLURM_CPUS_PER_TASK:-?}"
  } > "$OUT/run.log"
  MAXSUM_INSIDE=1 exec unshare -rn bash "$SELF" "$@" >> "$OUT/run.log" 2>&1
  echo "re-exec failed" >> "$OUT/run.log"; exit 2
fi
log() { echo "$(date -u +%FT%TZ) $*"; }
ip link set lo up
up=$(ip -o link show up | awk -F': ' '{print $2}' | tr '\n' ' ')
log "network namespace $(readlink /proc/self/ns/net); links up: $up"
[ "$up" = "lo " ] || { log "REFUSING: lo is not the only link up"; exit 3; }
EXP=mfxsim0001; PORT=31877
mkdir -p "$OUT/h5" "$OUT/xtc/smalldata"
XTC=$(ls -d "$REC"/data/*/*/xtc | head -1)
for f in "$XTC"/*.xtc2; do b=$(basename "$f"); ln -sf "$f" "$OUT/xtc/${b/tstx00001/$EXP}"; done
for f in "$XTC"/smalldata/*.xtc2; do b=$(basename "$f"); ln -sf "$f" "$OUT/xtc/smalldata/${b/tstx00001/$EXP}"; done
log "recording $(basename "$(dirname "$REC")"): $(ls "$OUT/xtc" | grep -c xtc2) bigdata, $(ls "$OUT/xtc/smalldata" | grep -c xtc2) smalldata xtc2 file(s), presented as experiment $EXP run 1"

set +u
source /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh >/dev/null 2>&1
unset CALIB_JWT ARP_JOB_ID ARP_LOCATION JID_UPDATE_COUNTERS
export KRB5CCNAME=FILE:/nonexistent-maxsum PYTHONDONTWRITEBYTECODE=1
export HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 NO_PROXY=127.0.0.1,localhost
export http_proxy=$HTTP_PROXY https_proxy=$HTTPS_PROXY no_proxy=$NO_PROXY
export LCLS_CALIB_HTTP=http://127.0.0.1:$PORT
export X6_LGBK_URL=http://127.0.0.1:$PORT      # shim/sitecustomize.py: psana's logbook file-list URL -> stand-in
export PYTHONPATH=$M/shim:$SDT${PYTHONPATH:+:$PYTHONPATH}
export PS_SRV_NODES=1 PS_EB_NODES=1
export OMPI_MCA_osc=^ucx OMPI_MCA_plm=isolated OMPI_MCA_rmaps_base_oversubscribe=1
export OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
log "psana2 release: $(python -c 'import psana,os; print(os.path.dirname(psana.__file__))' 2>/dev/null)"

python "$M/calibws_jf.py" --port $PORT --log "$OUT/calibws.jsonl" > "$OUT/calibws.out" 2>&1 &
CWS=$!
for i in $(seq 50); do grep -q ready "$OUT/calibws.out" 2>/dev/null && break; sleep 0.2; done
cat "$OUT/calibws.out"

cp "$M/prod_config_maxsum.py" "$SDT/lcls2_producers/prod_config_maxsum.py"
log "the reduction this smalldata_tools runs at the end of the run (lcls2_producers/smd_producer.py):"
grep -n -A6 'sumDict = {"Sums": {}}' "$SDT/lcls2_producers/smd_producer.py" | head -9
log "ranks: $RANKS MPI ranks = 1 smd0 + $PS_EB_NODES event builder + $PS_SRV_NODES srv + $((RANKS - 2 - PS_SRV_NODES)) bigdata rank(s) that read events"
T0=$(date +%s)
log "\$ mpirun -n $RANKS python -m mpi4py.run smd_producer.py --experiment $EXP --run 1 --psdm_dir <out>/xtc --directory <out>/h5 --noarch --all_events --config maxsum"
mpirun --map-by :OVERSUBSCRIBE -n "$RANKS" python -u -m mpi4py.run "$SDT/lcls2_producers/smd_producer.py" \
  --experiment $EXP --run 1 --psdm_dir "$OUT/xtc" --directory "$OUT/h5" --noarch --all_events --config maxsum \
  > "$OUT/producer.log" 2>&1
PRC=$?
log "smd_producer: exit $PRC in $(( $(date +%s) - T0 )) s; log $(basename "$OUT")/producer.log ($(grep -c 'Failed analyzing' "$OUT/producer.log") 'Failed analyzing' lines)"
H5=$OUT/h5/${EXP}_Run0001.h5
[ -s "$H5" ] || { log "no h5 written"; tail -20 "$OUT/producer.log"; kill $CWS; exit 1; }
log "\$ python maxcheck.py --h5 $(basename "$H5") ${REF_H5:+--ref-h5 $REF_H5}"
python "$M/maxcheck.py" --h5 "$H5" --xtc-dir "$OUT/xtc" --exp $EXP --run 1 ${REF_H5:+--ref-h5 "$REF_H5"}
RC=$?
kill $CWS 2>/dev/null
log "maxcheck exit $RC"
