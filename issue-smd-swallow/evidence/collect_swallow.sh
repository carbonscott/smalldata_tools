#!/bin/bash
# collect_swallow.sh OUTDIR : copy the three smd-swallow runs' logs into OUTDIR. run.log files already start with
# the header run_swallow.sh wrote; each producer.log is copied whole under a header naming its source.
set -u
OUT=$1; mkdir -p "$OUT"
H=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/sim-issues/agents/h1/smd-swallow/runs
for r in x6roi2d-asis x6sim-asis x6roi2d-fixed; do
  cp $H/$r/run.log $OUT/$r.run.log
  { sed -n '1,2p' $H/$r/run.log | sed "s/^# date: .*/# date: $(date -u +%FT%TZ)/" | sed "s/^# host: .*/# host: $(hostname)/"
    sed -n '3p' $H/$r/run.log
    echo "# cmd: collect_swallow.sh $OUT (whole copy of $H/$r/producer.log, unchanged below the blank line)"
    echo; cat $H/$r/producer.log; } > $OUT/$r.producer.log
done
ls -la $OUT
