# Sources of the screenshots

- `01-code-sum-reduction-of-max.png` (1200x1157): rendered from `../evidence/code-excerpt.txt` (lines 1-4, 6-44) by `lib/render.py`, caption "smalldata_tools master 113800e: each rank keeps a per-pixel max, but the lcls2 producer combines the ranks with SUM; the lcls1 producer uses MAX"; highlights `^ +1010 `, `^ +68[1-2] @@green`, `^ +21[5-7] @@yellow`; callouts 3. Unedited text of the capture.
- `02-recording-jungfrau-2084-events.png` (1300x762): rendered from `../evidence/recording-run.log` (lines 1-5, 9-9, 38-52, 59-59) by `lib/render.py`, caption "The input: a simulated Jungfrau run (one 512x1024 module, 2084 events) recorded by the sim DAQ on S3DF, every count equal"; highlights `cycle PASS@@green`, `equal .*True@@green`, `--det jungfrau`; callouts 2. Unedited text of the capture.
- `03-8-ranks-calib-max-5x-too-large.png` (1400x901): rendered from `../evidence/run-maxsum-8ranks.log` (lines 1-4, 8-8, 13-33) by `lib/render.py`, caption "8 MPI ranks (5 read events): the producer exits 0, and Sums/jungfrau_calib_max is about 5x the true per-pixel max on every pixel"; highlights `small_data.sum`, `ratio h5/truth 4.990`, `median 4.969`, `VERDICT`, `exit 0 in@@yellow`, `5 bigdata rank`; callouts 5. Unedited text of the capture.
- `04-control-1-reading-rank-exact.png` (1400x621): rendered from `../evidence/run-maxsum-4ranks.log` (lines 1-4, 21-33) by `lib/render.py`, caption "Control, same code and data with 4 ranks (1 reads events): there is nothing to add, and calib_max equals the true per-pixel max"; highlights `VERDICT@@green`, `ratio h5/truth 1.000@@green`, `1 bigdata rank`; callouts 2. Unedited text of the capture.
- `05-fix-max-reduction-8-ranks-exact.png` (1400x829): rendered from `../evidence/run-maxsum-8ranks-fix.log` (lines 1-4, 13-33) by `lib/render.py`, caption "With the fix (small_data.max for max keys, as in the lcls1 producer), 8 ranks give the exact per-pixel max"; highlights `if "max" in key@@green`, `VERDICT@@green`, `ratio h5/truth 1.000@@green`; callouts 3. Unedited text of the capture.

The captures were written on S3DF and copied here unchanged:

| Capture here | Written on S3DF as (under /sdf/data/lcls/ds/prj/prjcwang31/scratch/main/sim-issues/agents/h3/) |
|---|---|
| `evidence/code-excerpt.txt` | `runs/gh/maxsum-code-excerpt.txt` (`evidence/excerpt.sh` on sdfiana025, smalldata_tools clone at 113800e) |
| `evidence/recording-run.log` | `runs/jf-rec1/run.log` (`evidence/daqrun.sh record`, sdfrome044) |
| `evidence/run-maxsum-8ranks.log` | `runs/maxsum-8ranks/run.log` (`evidence/run_maxsum.sh`, sdfrome044) |
| `evidence/run-maxsum-4ranks.log` | `runs/maxsum-4ranks/run.log` |
| `evidence/run-maxsum-8ranks-fix.log` | `runs/maxsum-8ranks-fix/run.log` (smalldata_tools-fix, commit a95b35d) |
