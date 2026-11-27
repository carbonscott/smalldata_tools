#!/bin/bash
# timing2.sh: processSums per-call timing with MFX's key list (thr_mfx), 4 ranks, 8 cpus, sdfrome042 (job 47367580).
# Three rounds of master (113800e), fix (37c56ea) and copy-per-key (master + the issue's .copy() line, uncommitted).
A=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h1
REC=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/shared/rec/jf-rec1/wd
S="srun --jobid=47367580 --overlap --ntasks=1 --cpus-per-task=8 --mem=32G"
for i in 1 2 3; do
  for t in master fix copy; do
    echo "$(date -u +%FT%TZ) node load: $(srun --jobid=47367580 --overlap --ntasks=1 cat /proc/loadavg)"
    $S bash $A/harness/run_thr.sh $REC $A/runs2/timing-$t-$i thr_mfx 4 $A/sdt-$t timing
    echo "$t $i rc $?"
  done
done
echo ALLDONE
