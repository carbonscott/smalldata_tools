#!/bin/bash
# run_x6.sh RUN_DIR OUT_DIR [--fault stale-pedestal|wrong-gain-mode|no-mask] [--ranks N] [--default-events]
#                            [--config x6sim|x6ctrl]   (prod_config_<name>.py beside this script)
#
# x6: the facility's smalldata_tools lcls2 producer (smd_producer.py, unmodified) and psana2's Jungfrau
# calibration (release lcls2_111826) on a recorded simulated Jungfrau run (h2 rec/record.sh: lcls2 sim/beam-coupling,
# simsls --beam fed by feed_beam.py), judged by x6_check.py against the frame model and the beam record.
# SDT_DIR=<smalldata_tools tree> selects the producer tree (default: the upstream clone at master).
#
# Run it as a step of the job, inside a private network namespace with only loopback, e.g.
#   srun --jobid=J --overlap --ntasks=1 --cpus-per-task=8 --mem=32G unshare -rn bash run_x6.sh RUN OUT
# so that nothing the pipeline starts can reach a facility service (the calibration DB is a stand-in
# on 127.0.0.1; logbook/ARP posts are off because ARP_* are unset and --postRuntable is not given;
# the archiver is off with --noarch).
#
# Writes OUT/x6.log (provenance header first), OUT/h5/<exp>_Run0001.h5, OUT/check.json, OUT/calibws.jsonl.
set -u
P=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/sim-issues/agents/h2      # sim-issues h2: scripts (x6/) and upstream smalldata_tools clone
X=$P/x6
S=${SDT_DIR:-$P/smalldata_tools}
RUN=$1; OUT=$2; shift 2
FAULT=""; RANKS=4; ALLEV=--all_events; CFG=x6sim
while [ $# -gt 0 ]; do
  case $1 in
    --fault) FAULT=$2; shift 2 ;;
    --ranks) RANKS=$2; shift 2 ;;
    --default-events) ALLEV=""; shift ;;
    --config) CFG=$2; shift 2 ;;
    *) echo "run_x6.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$OUT/h5" "$OUT/xtc/smalldata"
EXP=mfxsim0001
PORT=31877
SEED=$(python3 -c 'import json,sys; print(hex(json.load(open(sys.argv[1]))["seed"]))' "$RUN/daq/daq_sim.state.json")
SDT="$(git -C "$S" rev-parse HEAD) ($(basename "$S") $(git -C "$S" rev-parse --abbrev-ref HEAD))"

hdr() {
echo "# host: $(hostname)"
echo "# date: $(date -u +%FT%TZ)"
echo "# commit: smalldata_tools $SDT recording-lcls2 $(git -C "$P/lcls2" rev-parse HEAD)"
echo "# cmd: run_x6.sh $(basename "$RUN") $OUT ${FAULT:+--fault $FAULT} --ranks $RANKS ${ALLEV:---default-events} --config $CFG"
echo "# run: $RUN"
echo "# x6 scripts sha256: $(cd "$X" && sha256sum calibws_jf.py x6_check.py run_x6.sh prod_config_$CFG.py shim/sitecustomize.py | awk '{printf "%s:%s ", $2, substr($1,1,12)}')"
echo "# psana env: /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh -> $(readlink -f /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh)"
echo "# network: $(ip -o link show | awk -F': ' '{print $2}' | tr '\n' ' ')(namespace $(readlink /proc/self/ns/net))"

}
hdr

# the recorded run under an MFX-style experiment name (smalldata_tools accepts TMO RIX UED MFX XPP only)
XTC=$(ls -d "$RUN"/daq/data/*/*/xtc | head -1)
for f in "$XTC"/*.xtc2; do b=$(basename "$f"); ln -sf "$f" "$OUT/xtc/${b/tstx00001/$EXP}"; done
for f in "$XTC"/smalldata/*.xtc2; do b=$(basename "$f"); ln -sf "$f" "$OUT/xtc/smalldata/${b/tstx00001/$EXP}"; done
echo "xtc2 files: $(ls "$OUT/xtc" | grep -c xtc2) bigdata, $(ls "$OUT/xtc/smalldata" | grep -c xtc2) smalldata; seed $SEED"

ip link set lo up 2>/dev/null || true
source /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh >/dev/null 2>&1
unset CALIB_JWT ARP_JOB_ID ARP_LOCATION JID_UPDATE_COUNTERS
export KRB5CCNAME=FILE:/nonexistent-x6
export HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 NO_PROXY=127.0.0.1,localhost
export http_proxy=$HTTP_PROXY https_proxy=$HTTPS_PROXY no_proxy=$NO_PROXY
export LCLS_CALIB_HTTP=http://127.0.0.1:$PORT
# shim/sitecustomize.py: points psana's hard-coded logbook file-list URL at the loopback stand-in
export X6_LGBK_URL=http://127.0.0.1:$PORT
export PYTHONPATH=$X/shim:$S${PYTHONPATH:+:$PYTHONPATH}
export PS_SRV_NODES=1 PS_EB_NODES=1
export OMPI_MCA_osc=^ucx OMPI_MCA_plm=isolated OMPI_MCA_rmaps_base_oversubscribe=1
# unshare -r maps us to uid 0 of a user namespace (no real privilege); OpenMPI refuses uid 0 unless told
export OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

python "$X/calibws_jf.py" --port $PORT --log "$OUT/calibws.jsonl" ${FAULT:+--fault $FAULT} > "$OUT/calibws.out" 2>&1 &
CWS=$!
for i in $(seq 50); do grep -q ready "$OUT/calibws.out" 2>/dev/null && break; sleep 0.2; done
cat "$OUT/calibws.out"

cp "$X/prod_config_$CFG.py" "$S/lcls2_producers/prod_config_$CFG.py"
hdr > "$OUT/producer.log"
T0=$(date +%s)
mpirun --map-by :OVERSUBSCRIBE -n "$RANKS" python -u -m mpi4py.run "$S/lcls2_producers/smd_producer.py" \
  --experiment $EXP --run 1 --psdm_dir "$OUT/xtc" --directory "$OUT/h5" --noarch $ALLEV --config $CFG \
  >> "$OUT/producer.log" 2>&1
PRC=$?
echo "smd_producer: exit $PRC in $(( $(date +%s) - T0 )) s with $RANKS MPI ranks; log $OUT/producer.log"
tail -5 "$OUT/producer.log"
echo "stand-in requests: $(wc -l < "$OUT/calibws.jsonl") ($(grep -c '"status": 200' "$OUT/calibws.jsonl") answered 200; logbook file-list requests $(grep -c '/lgbk/' "$OUT/calibws.jsonl"))"

H5=$OUT/h5/${EXP}_Run0001.h5
[ -s "$H5" ] || { echo "no h5 written"; echo "exit 1"; exit 1; }
echo "h5: $H5 ($(stat -c %s "$H5") bytes)"
python "$X/x6_check.py" --h5 "$H5" --xtc-dir "$OUT/xtc" --exp $EXP --run 1 --seed "$SEED" \
  --record "$RUN/beam-record.txt" --pedestal 1031.5 --gain 40 --json "$OUT/check.json"
RC=$?
kill $CWS 2>/dev/null
echo "exit $RC"
exit $RC
