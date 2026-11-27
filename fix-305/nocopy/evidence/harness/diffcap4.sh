#!/bin/bash
# diffcap4.sh <tree> <out>: the no-copy fix's whole diff against master, with the provenance header
T=$(readlink -f "$1"); OUT=$2
H=$(git -C "$T" rev-parse HEAD)
F="smalldata_tools/lcls2/DetObject.py lcls2_producers/smd_producer.py"
{
echo "# host: $(hostname)"
echo "# date: $(date -u +%FT%TZ)"
echo "# commit: smalldata_tools $H ($(git -C "$T" rev-parse --abbrev-ref HEAD))"
echo "# cmd: diffcap4.sh $T: git diff --numstat master...HEAD; git show --format=... HEAD; black 26.5.1 --check on the changed files"
echo "\$ git diff --numstat 113800e...HEAD   (lines added, removed)"
git -C "$T" diff --numstat 113800e157605e27b1a9794e1f6467a58a5b11cd...HEAD
echo "\$ uvx black==26.5.1 --check $F"
(cd "$T" && UV_CACHE_DIR=$(dirname "$T")/cache/uv XDG_CACHE_HOME=$(dirname "$T")/cache/xdg uvx black==26.5.1 --check $F 2>&1 | grep -v "^Installed\|Download"; echo "black exit ${PIPESTATUS[0]}")
echo "\$ git show HEAD"
git -C "$T" show --format="commit %H%nparent %P%n%n    %s%n" HEAD
} > "$OUT"
