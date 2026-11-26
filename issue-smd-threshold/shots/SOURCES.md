# Sources of the screenshots


Note on what the shots leave out: each run log also has a `CHECK ratio FAIL` line (about +4% on every attenuated step). That check belongs to the
test harness, not to smalldata_tools: the beam log (`beam-record.txt`, written by the feeder that drives the simulator) starts a fraction of a second
after the DAQ began recording, so the first ~30 dark frames are counted as full beam and lower the T=1 reference. It is the same in the failing,
control and fix runs and does not involve any Sums image. The full logs are in `../evidence/`.
- `01-code-in-place-threshold.png` (1200x974): rendered from `../evidence/code-113800e.txt` (lines 1-4, 7-27, 59-66) by `lib/render.py`, caption "At master 113800e processSums thresholds self.evt.dat in place, and MFX's config lists calib_max after two threshold keys"; highlights `^ *196 `, `^ *198 `, `^ *138 @@yellow`; callouts 3. Unedited text of the capture.
- `02-mfx-config-calib-max-zero.png` (1200x746): rendered from `../evidence/run-mfx-order.log` (lines 1-4, 11-11, 19-31) by `lib/render.py`, caption "With MFX's sum list the producer exits 0 and calib_max is 0 on 434404 pixels whose true max is up to 4.84 keV"; highlights `img_calib_max +FAIL`, `exit 0`; callouts 3. Unedited text of the capture.
- `03-control-calib-max-first.png` (1200x559): rendered from `../evidence/run-control-calib-max-first.log` (lines 1-4, 11-11, 21-27) by `lib/render.py`, caption "Control: the same run and producer with calib_max listed first gives the true max on all 524288 pixels"; highlights `img_calib_max +PASS@@green`; callouts 2. Unedited text of the capture.
- `04-fix-copy-passes.png` (1200x582): rendered from `../evidence/run-fix-copy.log` (lines 1-4, 11-11, 21-27) by `lib/render.py`, caption "Fix: with processSums summing a copy, MFX's original order gives the true calib_max and leaves the other sums unchanged"; highlights `img_calib_max +PASS@@green`; callouts 2. Unedited text of the capture.
