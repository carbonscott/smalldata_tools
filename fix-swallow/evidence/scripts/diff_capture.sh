#!/bin/bash
# diff_capture.sh OUT: the whole diff of fix/307-swallow-exceptions against master, as fetched from the fork,
# with its line count and a black 26.5.1 check of the changed file.
A=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/smd-prs/agents/h2
G=$A/sdt-master
OUT=$1
git -C $G fetch -q origin master fix/307-swallow-exceptions
M=$(git -C $G rev-parse origin/master); H=$(git -C $G rev-parse origin/fix/307-swallow-exceptions)
export UV_CACHE_DIR=$A/cache/uv XDG_CACHE_HOME=$A/cache/xdg
T=$(mktemp -d $A/cache/blk.XXXX); git -C $G show $H:lcls2_producers/smd_producer.py > $T/smd_producer.py
{
echo "# host: $(hostname)"
echo "# date: $(date -u +%FT%TZ)"
echo "# commit: smalldata_tools $H"
echo "# cmd: diff_capture.sh (git diff --numstat / git diff origin/master...origin/fix/307-swallow-exceptions, black 26.5.1 --check)"
echo "# master (base): $M"
echo "\$ git log --oneline origin/master..origin/fix/307-swallow-exceptions"
git -C $G log --oneline $M..$H
echo "\$ git diff --numstat origin/master...origin/fix/307-swallow-exceptions"
git -C $G diff --numstat $M...$H
echo "\$ uvx --from black==26.5.1 black --check lcls2_producers/smd_producer.py   (file at the head)"
(cd $T && uvx -q --from black==26.5.1 black --check smd_producer.py 2>&1 | sed "s#$T/##")
echo "\$ git diff origin/master...origin/fix/307-swallow-exceptions"
git -C $G diff $M...$H
} > $OUT
rm -rf $T
cat $OUT
