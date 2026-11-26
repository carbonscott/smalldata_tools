#!/bin/bash
# code_capture.sh OUTDIR : the code behind smd-swallow at the head of slac-lcls/smalldata_tools master, its history,
# and a search of the repository's issues and pull requests. Writes OUTDIR/code-at-head.txt.
set -u
OUT=$1; mkdir -p "$OUT"
R=/sdf/data/lcls/ds/prj/prjcwang31/scratch/main/sim-issues/agents/h1/smalldata_tools
git -C $R fetch -q origin
S=$(git -C $R rev-parse origin/HEAD); B=$(git -C $R symbolic-ref --short refs/remotes/origin/HEAD)
F=lcls2_producers/smd_producer.py
{
echo "# host: $(hostname)"; echo "# date: $(date -u +%FT%TZ)"
echo "# commit: smalldata_tools $S ($B)"
echo "# cmd: code_capture.sh $OUT"
echo
echo "\$ git ls-remote https://github.com/slac-lcls/smalldata_tools HEAD refs/heads/master"
git ls-remote https://github.com/slac-lcls/smalldata_tools HEAD refs/heads/master
echo
echo "\$ git show $S:$F | cat -n | sed -n '817,846p'"
git -C $R show $S:$F | cat -n | sed -n '817,846p'
echo
echo "\$ git show $S:$F | cat -n | sed -n '1145,1150p'    # end of the script: no failure is reported, exit status 0"
git -C $R show $S:$F | cat -n | sed -n '1145,1150p'
echo
echo "\$ git log --format='%h %ad %s' --date=short -L841,845:$F $S | grep -E '^[0-9a-f]{7,} '    # who wrote the except block"
git -C $R log --format='%h %ad %s' --date=short -L841,845:$F $S | grep -E '^[0-9a-f]{7,} '
echo
for q in 'Failed+analyzing' 'exception+swallowed' 'print(e)' 'silent+failure' 'traceback+producer'; do
  echo "\$ curl -s 'https://api.github.com/search/issues?q=repo:slac-lcls/smalldata_tools+$q'"
  curl -s "https://api.github.com/search/issues?q=repo:slac-lcls/smalldata_tools+$q&per_page=30" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("total_count:", d.get("total_count"), d.get("message", ""))
for i in d.get("items", []):
    print("  #%s %s %s %s" % (i["number"], i["state"], "PR" if "pull_request" in i else "issue", i["title"][:110]))'
done
echo
echo "\$ git ls-tree -r --name-only $S | grep -i -E 'ISSUE_TEMPLATE|^.github/'"
git -C $R ls-tree -r --name-only $S | grep -i -E 'ISSUE_TEMPLATE|^.github/'
} > $OUT/code-at-head.txt 2>&1
cat $OUT/code-at-head.txt
