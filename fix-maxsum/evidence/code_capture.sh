#!/bin/bash
# code_capture.sh <smalldata_tools tree at the PR head> <out file>: the PR diff and the code it relies on.
SDT=$(readlink -f "$1"); OUT=$2
PS=/sdf/group/lcls/ds/ana/sw/conda2/rel/ana/lcls2_111826/install/lib/python3.13/site-packages/psana/smalldata.py
{
echo "# host: $(hostname)"
echo "# date: $(date -u +%FT%TZ)"
echo "# commit: smalldata_tools $(git -C "$SDT" rev-parse HEAD) ($(git -C "$SDT" log -1 --format=%s)); base master 113800e157605e27b1a9794e1f6467a58a5b11cd"
echo "# cmd: code_capture.sh $SDT $OUT"
echo "\$ git diff --numstat 113800e...HEAD"
git -C "$SDT" diff --numstat 113800e157605e27b1a9794e1f6467a58a5b11cd...HEAD
echo "\$ git diff 113800e...HEAD   (the whole diff)"
git -C "$SDT" diff 113800e157605e27b1a9794e1f6467a58a5b11cd...HEAD
echo "\$ grep -n -A3 \"if \\\"max\\\" in key\" lcls1_producers/smd_producer.py   (what the LCLS-I producer does)"
grep -n -A3 "if \"max\" in key" "$SDT/lcls1_producers/smd_producer.py"
echo "\$ sed -n 207,217p smalldata_tools/lcls2/DetObject.py   (per rank: np.maximum for max keys, += for every other key)"
sed -n 207,217p "$SDT/smalldata_tools/lcls2/DetObject.py" | awk "{printf \"%d  %s\\n\", NR+206, \$0}"
echo "\$ grep -rn \"np.minimum\\|find(\\\"min\\\")\" smalldata_tools/lcls2/DetObject.py lcls1_producers/smd_producer.py | wc -l"
grep -rn "np.minimum\|find(\"min\")" "$SDT/smalldata_tools/lcls2/DetObject.py" "$SDT/lcls1_producers/smd_producer.py" | wc -l
echo "\$ sed -n 826,834p psana/smalldata.py   (psana2 release lcls2_111826: SmallData.max and .min exist)"
sed -n 826,834p "$PS" | awk "{printf \"%d  %s\n\", NR+825, \$0}"
} > "$OUT" 2>&1
