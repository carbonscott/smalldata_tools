#!/bin/bash
# matrix.sh: the fix-swallow proof matrix, each run a Slurm step on sdfrome055 inside unshare -rn
X=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h2/swallow
A=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h2
REC=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/shared/rec/jf-rec1/wd/data/tst/tstx00001
for spec in "$@"; do
  set -- $spec
  name=$1; np=$2; tree=$3; cfg=$4; shift 4
  NP=$np srun --jobid=47367581 --overlap --ntasks=1 --cpus-per-task=10 --mem=40G \
    unshare -rn bash $X/run_swallow.sh $REC $X/runs/$name $cfg $A/$tree "$@" > $X/runs/$name.stdout 2>&1
  echo "=== $(date -u +%FT%TZ) done $name srun rc=$?"
done
echo "=== ALL DONE"
