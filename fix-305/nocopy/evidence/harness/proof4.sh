#!/bin/bash
# proof4.sh: no-copy variant (fix/305-sort-no-copy) vs master, and vs #6 (37c56ea). Configs thr_mfx and thr_mix,
# 4 ranks, one roma node (job 47386055). Then processSums timing, interleaved master / fix / nocopy / copy-per-key.
A=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h1
REC=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/shared/rec/jf-rec1/wd
J=47386055
S="srun --jobid=$J --overlap --ntasks=1 --cpus-per-task=8 --mem=32G"
for cfg in thr_mfx thr_mix; do
  $S bash $A/harness/run_thr.sh $REC $A/runs4/master-$cfg $cfg 4 $A/sdt-master; echo "master $cfg rc $?"
  REF_H5=$A/runs3/fix-$cfg/h5/mfxsim0001_Run0001.h5 $S bash $A/harness/run_thr.sh $REC $A/runs4/nocopy-$cfg $cfg 4 $A/sdt-nocopy; echo "nocopy $cfg rc $?"
done
for i in 1 2 3; do
  for t in master fix nocopy copy; do
    echo "$(date -u +%FT%TZ) node load: $(srun --jobid=$J --overlap --ntasks=1 cat /proc/loadavg)"
    $S bash $A/harness/run_thr.sh $REC $A/runs4/timing-$t-$i thr_mfx 4 $A/sdt-$t timing; echo "timing $t $i rc $?"
  done
done
echo ALLDONE
