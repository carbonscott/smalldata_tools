#!/bin/bash
# spread8.sh <out file>: the 8-rank h5 files of runs/ compared pairwise with h5cmp.py (h5py only), to separate
# the fix from the run-to-run spread of float32 sums (which events each of the 5 reading ranks got differs per run).
A=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h3; R=$A/runs; H=h5/mfxsim0001_Run0001.h5; OUT=$1
{
echo "# host: $(hostname)"
echo "# date: $(date -u +%FT%TZ)"
echo "# commit: smalldata_tools master 113800e157605e27b1a9794e1f6467a58a5b11cd vs head 727462fef3db74caa3919a7cb0fdb2d7484cc398 (runs/*/run.log name the tree of each h5)"
echo "# cmd: spread8.sh $OUT"
echo "# scripts sha256: $(cd $A/maxsum && sha256sum spread8.sh h5cmp.py | awk "{printf \"%s:%s \", \$2, substr(\$1,1,12)}")"
for r in master-8 master-8b head-8 head-8b; do echo "# $r: $(sed -n 3p $R/$r/run.log | cut -c1-80) ... $(grep -m1 "smd_producer: exit" $R/$r/run.log | cut -c22-60)"; done
source /sdf/group/lcls/ds/ana/sw/conda2/manage/bin/psconda.sh >/dev/null 2>&1
for p in "master-8b master-8 two runs of master" "head-8b head-8 two runs of the fix" "head-8 master-8 fix vs master" "head-8b master-8b fix vs master (second pair)"; do
  set -- $p; a=$1; b=$2; shift 2
  echo; echo "\$ python h5cmp.py $a $b   ($*)"
  python $A/maxsum/h5cmp.py $R/$a/$H $R/$b/$H | grep -v "^Sums keys" | sed "s/(1, 512, 1024) float32  //"
done
} > "$OUT" 2>&1
