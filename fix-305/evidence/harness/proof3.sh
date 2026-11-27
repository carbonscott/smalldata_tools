#!/bin/bash
# proof2.sh: final before/after. master then fix (37c56ea), configs thr_mfx (MFX order + subsampling) and thr_mix
# (two thresholds falling, nhits, max, calib), 4 ranks, on sdfrome055 (job 47367581)
A=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h1
REC=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/shared/rec/jf-rec1/wd
S="srun --jobid=47367581 --overlap --ntasks=1 --cpus-per-task=8 --mem=32G"
for cfg in thr_mfx thr_mix; do
  $S bash $A/harness/run_thr.sh $REC $A/runs3/master-$cfg $cfg 4 $A/sdt-master
  echo "master $cfg rc $?"
  REF_H5=$A/runs3/master-$cfg/h5/mfxsim0001_Run0001.h5 $S bash $A/harness/run_thr.sh $REC $A/runs3/fix-$cfg $cfg 4 $A/sdt-fix
  echo "fix $cfg rc $?"
done
echo ALLDONE
