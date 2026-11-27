#!/bin/bash
# excerpt.sh RUN HEAD_N TAIL_N: the producer log of runs/RUN, first HEAD_N and last TAIL_N lines, under the run's provenance header
X=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h2/swallow
R=$1; P=$X/runs/$R/producer.log; N=$(wc -l < $P)
{ head -3 $X/runs/$R/run.log; echo "# cmd: excerpt.sh $R $2 $3 (of: $(sed -n 4p $X/runs/$R/run.log | sed 's/^# cmd: //'))"
  echo "# excerpt of runs/$R/producer.log ($N lines): lines 1-$2 and $((N-$3+1))-$N"
  head -$2 $P | sed 's/\x1b\[0m//g'; echo "[... lines $(($2+1))-$((N-$3)) not shown ...]"; tail -$3 $P | sed 's/\x1b\[0m//g'; } > $X/captures/$R.producer-excerpt.log
