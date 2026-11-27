#!/bin/bash
# cmp_capture.sh OUT A_RUN B_RUN [A_RUN B_RUN ...]: h5cmp.py (h5py read-back, sha256 per dataset) for pairs of runs
X=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h2/swallow
OUT=$1; shift
source /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh >/dev/null 2>&1
{
echo "# host: $(hostname)"
echo "# date: $(date -u +%FT%TZ)"
echo "# commit: smalldata_tools $(git -C $X/../sdt-fix rev-parse HEAD) (head; master $(git -C $X/../sdt-master rev-parse HEAD))"
echo "# cmd: cmp_capture.sh $OUT $*"
while [ $# -ge 2 ]; do
  echo; echo "=== $1 vs $2"
  for r in $1 $2; do echo "$r: $(grep -a '^# commit' $X/runs/$r/run.log) | $(grep -a '^smd_producer: exit' $X/runs/$r/run.log)"; done
  python $X/h5cmp.py $X/runs/$1/h5/mfxsim0001_Run0001.h5 $X/runs/$2/h5/mfxsim0001_Run0001.h5
  shift 2
done
} > $OUT
cat $OUT
