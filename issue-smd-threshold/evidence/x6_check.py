"""x6_check: judge a smalldata_tools HDF5 file made from a simulated, hutch-coupled Jungfrau run against
truth that the pipeline never sees.

Truth comes from two places, both independent of smalldata_tools and of psana's calibration code:
  1. the frame model (lcls2 psdaq/psdaq/sim/simsls.py, written out again as in sim-hutch
     demos/demo1/readback.py): every pixel of frame n follows from the DAQ's seed, n and the beam state
     stamped in the frame. From the model frame (not the recorded one) and the constants the
     calibration stand-in served (pedestal P, gain G), calib_n = (model_n - P) / G, and every
     smalldata quantity has a closed form with the meaning its name gives it (bad pixels of the
     deployed pixel_status, here the 16 stamp pixels, are 0 in the Sums images):
         Sums/jungfrau_calib            sum_n calib_n                      (per pixel, over the run)
         Sums/jungfrau_calib_square     sum_n calib_n**2
         Sums/jungfrau_calib_thresADU<N> sum_n calib_n * [calib_n >= N]
         Sums/jungfrau_calib_max        max_n calib_n
         jungfrau/ROI_<r>_sum, _max     per event, over the ROI
  2. the hutch record (camonitor of the attenuator readback and the stopper, hutch-record.txt): the
     physics. Per attenuator step, the ring ROI mean / the full-beam step's = the readback; after the
     stopper reads IN the ring ROI is dark (mean calib ~ 0); the dark ROI sits at 0 (pedestal right).

Checks (CHECK <name> PASS|FAIL <evidence>):
  rows        every xtc2 event is one h5 row (matched by timestamp), none twice, none extra
  input       every recorded frame equals the model frame (the pipeline got the data we think)
  img_<algo>  each Sums image equals its closed form, per pixel, within float32 accumulation
  roi_<r>     each event's ROI sum and max equal the closed form
  ratio       per attenuator step, ring ROI mean / full-beam mean within 2 % of the readback
  dark        every event from the record's stopper IN on: |ring ROI mean calib| <= 0.15
  pedestal    dark ROI mean calib over the run within 0.02 of 0

    python x6_check.py --h5 F --xtc-dir D --exp E --run R --seed S --record hutch-record.txt
                       --pedestal 1031.5 --gain 40 [--json out.json]
"""

import argparse
import datetime
import glob
import json
import os
import struct
import sys

import numpy as np

ROWS, COLS = 512, 1024
NPIX = ROWS * COLS
STAMP_PIXELS = 16
STAMP = struct.Struct('<2sBBdI')
PEDESTAL, NOISE_MASK, DATA_MAX = 1000, 0x3F, 0x3FFF
SEQ_K, MIX_A, MIX_B = 0x9E37, 0x9E3779B1, 0x85EBCA6B
POSIX_AT_EPICS_EPOCH = 631152000

ROIS = {'ring': (slice(246, 266), slice(682, 702)),      # prod_config_x6sim.py RING_ROI
        'dark': (slice(400, 420), slice(0, 20))}         # prod_config_x6sim.py DARK_ROI

PV_T = 'MFX:ATT:COM:R_CUR'
PV_SUM = 'PPS:FEH1:45:S45STPRSUM'
PV_CMD = 'SIM:MFX:SH45:CMD'
RATIO_TOL, PED_TOL = 0.02, 0.02
DARK_TOL = 0.15         # a dark 20x20 ROI mean has sigma 18.47/40/20 = 0.023; the weakest beam step is ~25
IMG_RTOL = 5e-4          # of sum_n |calib_n| per pixel: float32 accumulation over a few thousand events
MAX_RTOL = 1e-5


def mix(index):
    h = np.asarray(index, dtype=np.uint64).astype(np.uint32)
    with np.errstate(over='ignore'):
        h = h * np.uint32(MIX_A)
        h ^= h >> np.uint32(16)
        h = h * np.uint32(MIX_B)
        h ^= h >> np.uint32(13)
    return h


class Model:
    def __init__(self):
        self.mixed = mix(np.arange(NPIX, dtype=np.uint64)).astype(np.uint64)
        row, col = np.divmod(np.arange(NPIX), COLS)
        x = (np.sqrt((row - 256.0) ** 2 + (col - 512.0) ** 2) - 180.0) / 40.0
        self.profile = np.rint(12000.0 * np.maximum(0.0, 1.0 - x * x))
        self.profile[:STAMP_PIXELS] = 0.0

    def frame(self, seed, n, t, is_open, known):
        pat = ((self.mixed + ((n * SEQ_K + seed) & 0xFFFFFFFF)) & 0xFFFFFFFF) & 0xFFFF
        dark = PEDESTAL + (pat.astype(np.int64) & NOISE_MASK)
        e = (900 + int(mix((n * SEQ_K + seed) & 0xFFFFFFFF)) % 201) / 1000.0
        g = t * e if (known and is_open) else 0.0
        img = np.minimum(dark + np.floor(self.profile * g + 0.5).astype(np.int64), DATA_MAX).astype(np.uint16)
        flags = (1 if is_open else 0) | (2 if known else 0)
        img[:STAMP_PIXELS] = np.frombuffer(STAMP.pack(b'HS', 1, flags, t, seed & 0xFFFFFFFF), np.uint8)
        return img


def decode_stamp(flat):
    px = np.asarray(flat).ravel()[:STAMP_PIXELS]
    if int(px.max()) > 0xFF:
        return None
    magic, ver, flags, t, seed = STAMP.unpack(px.astype(np.uint8).tobytes())
    if magic != b'HS' or ver != 1:
        return None
    return float(t), bool(flags & 1), bool(flags & 2), int(seed)


def parse_record(path):
    out = {}
    for line in open(path):
        f = line.split()
        if len(f) < 4 or '***' in f[3]:
            continue
        try:
            t = datetime.datetime.strptime(f[1] + ' ' + f[2], '%Y-%m-%d %H:%M:%S.%f')
        except ValueError:
            continue
        out.setdefault(f[0], []).append((t.replace(tzinfo=datetime.timezone.utc).timestamp(), f[3]))
    for v in out.values():
        v.sort(key=lambda x: x[0])
    return out


def value_at(changes, t):
    if not changes:
        return None
    cur = changes[0][1]
    for ts, v in changes:
        if ts <= t:
            cur = v
        else:
            break
    return cur


def epics_to_posix(ts):
    return (ts >> 32) + POSIX_AT_EPICS_EPOCH + (ts & 0xFFFFFFFF) * 1e-9


class Accum:
    """Run-integrated closed forms of the Sums images, for every algorithm the h5 holds."""
    def __init__(self, algos):
        self.algos = algos
        self.img = {a: None for a in algos}
        self.absum = None

    def add(self, c):
        a_abs = np.abs(c)
        self.absum = a_abs.copy() if self.absum is None else self.absum + a_abs
        for a in self.algos:
            if a == 'calib':
                v = c
            elif a == 'calib_square':
                v = c * c
            elif a.startswith('calib_thresADU'):
                v = np.where(c >= float(a[len('calib_thresADU'):]), c, 0.0)
            elif a == 'calib_max':
                self.img[a] = c.copy() if self.img[a] is None else np.maximum(self.img[a], c)
                continue
            else:
                continue
            self.img[a] = v.copy() if self.img[a] is None else self.img[a] + v


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument('--h5', required=True)
    p.add_argument('--xtc-dir', required=True)
    p.add_argument('--exp', required=True)
    p.add_argument('--run', type=int, required=True)
    p.add_argument('--seed', type=lambda s: int(s, 0), required=True)
    p.add_argument('--record', required=True)
    p.add_argument('--pedestal', type=float, default=1031.5)
    p.add_argument('--gain', type=float, default=40.0)
    p.add_argument('--masked-pixels', type=int, default=16,
                   help='pixels 0..N-1 are bad in the pixel_status that should be deployed (the stamp)')
    p.add_argument('--json', default=None)
    a = p.parse_args(argv)

    import h5py
    f = h5py.File(a.h5, 'r')
    sums = sorted(k for k in f['Sums'].keys() if k.startswith('jungfrau_')) if 'Sums' in f else []
    algos = [k[len('jungfrau_'):] for k in sums]
    roi_keys = {r: {q: 'jungfrau/ROI_%s_%s' % (r, q) for q in ('sum', 'max')} for r in ROIS}
    ts = np.asarray(f['timestamp'][()]).astype(np.uint64)
    roi = {r: {q: (np.asarray(f[k][()], dtype=np.float64) if k in f else None) for q, k in d.items()}
           for r, d in roi_keys.items()}
    h5img = {al: np.asarray(f['Sums/jungfrau_' + al][()], dtype=np.float64).reshape(-1) for al in algos}
    print('h5: %d rows; Sums images: %s; ROI datasets: %s'
          % (len(ts), ', '.join(sums) or 'none',
             ', '.join(k for d in roi_keys.values() for k in d.values() if k in f)))

    from psana import DataSource
    files = sorted(glob.glob(os.path.join(a.xtc_dir, '%s-r%04d-s*.xtc2' % (a.exp, a.run))))
    ds = DataSource(files=files, skip_calib_load='all')     # raw only: no logbook, no calibration DB
    run = next(ds.runs())
    det = run.Detector([d for d in run.detnames if d.startswith('jungfrau')][0])
    model = Model()
    acc = Accum(algos)
    events, bad_input = [], []
    for evt in run.events():
        raw = det.raw.raw(evt)
        if raw is None:
            continue
        flat = np.asarray(raw).reshape(-1)
        n = int(det.raw._segments(evt)[0].frame_cnt)
        st = decode_stamp(flat)
        if st is None:
            bad_input.append((n, 'no stamp'))
            continue
        t, is_open, known, seed = st
        img = model.frame(a.seed, n, t, is_open, known)
        if not np.array_equal(img, flat) or seed != (a.seed & 0xFFFFFFFF):
            bad_input.append((n, 'frame differs from model'))
        c = (img.astype(np.float64) - a.pedestal) / a.gain
        cm = c.copy()
        cm[:a.masked_pixels] = 0.0                       # bad pixels (pixel_status) are 0 in the Sums
        acc.add(cm)
        c2 = c.reshape(ROWS, COLS)
        ex = {}
        for r, sl in ROIS.items():
            sub = c2[sl]
            ex[r] = dict(sum=sub.sum(), max=sub.max(), abs=np.abs(sub).sum(), mean=sub.mean())
        events.append(dict(ts=int(evt.timestamp), t=epics_to_posix(int(evt.timestamp)), n=n, ex=ex))
    print('xtc2: %d jungfrau events, frame_cnt %d..%d' % (len(events), events[0]['n'], events[-1]['n']))

    checks = []

    def check(name, ok, ev):
        checks.append((name, bool(ok), ev))
        print('CHECK %-22s %s  %s' % (name, 'PASS' if ok else 'FAIL', ev))

    row_of, dup = {}, 0
    for i, v in enumerate(ts):
        dup += int(int(v) in row_of)
        row_of[int(v)] = i
    xtc_ts = set(e['ts'] for e in events)
    missing = [e for e in events if e['ts'] not in row_of]
    extra = [v for v in row_of if v not in xtc_ts]
    in_order = bool(np.all(np.diff(ts.astype(np.int64)) > 0))
    check('rows', not missing and not extra and dup == 0,
          'h5 %d rows, xtc2 %d events; missing %d, extra %d, duplicate %d; rows in time order: %s'
          % (len(ts), len(events), len(missing), len(extra), dup, in_order))
    check('input', not bad_input, '%d of %d recorded frames equal the model frame%s'
          % (len(events) - len(bad_input), len(events),
             (' (first bad: %s)' % (bad_input[0],)) if bad_input else ''))

    if not algos:
        check('img', False, 'no Sums/jungfrau_* images in the h5')
    for al in algos:
        want, got = acc.img[al].reshape(-1), h5img[al]
        if got.size != want.size:
            check('img_' + al, False, 'shape %s, want %d pixels' % (got.shape, want.size))
            continue
        if al == 'calib_max':
            tol = MAX_RTOL * np.abs(want) + 1e-5
        elif al == 'calib_square':
            tol = IMG_RTOL * np.abs(want) + 1e-3
        else:
            tol = IMG_RTOL * acc.absum.reshape(-1) + 1e-3
        err = np.abs(got - want)
        bad = np.flatnonzero(~(err <= tol))
        ev = '%d of %d pixels off (worst |h5 - truth| %.4g at pixel %d: h5 %.6g, truth %.6g)' % (
            bad.size, want.size, float(err.max()), int(err.argmax()), float(got[err.argmax()]),
            float(want[err.argmax()]))
        if bad.size:
            ev += '; first off pixel %d: h5 %.6g, truth %.6g' % (bad[0], got[bad[0]], want[bad[0]])
        check('img_' + al, bad.size == 0, ev)

    for r in ROIS:
        for q in ('sum', 'max'):
            col = roi[r][q]
            if col is None:
                check('roi_%s_%s' % (r, q), False, 'dataset %s absent' % roi_keys[r][q])
                continue
            nbad, first, worst = 0, None, 0.0
            for e in events:
                i = row_of.get(e['ts'])
                if i is None:
                    continue
                want, got = e['ex'][r][q], float(np.sum(col[i]))
                tol = (1e-5 * e['ex'][r]['abs'] + 1e-3) if q == 'sum' else (1e-5 * abs(want) + 1e-5)
                worst = max(worst, abs(got - want))
                if not abs(got - want) <= tol:
                    nbad += 1
                    first = first or dict(frame=e['n'], h5=got, truth=want)
            check('roi_%s_%s' % (r, q), nbad == 0, '%d of %d events off (worst |h5 - truth| %.3g)%s'
                  % (nbad, len(events), worst, ('; first: ' + json.dumps(first)) if first else ''))

    # physics against the hutch record
    rec = parse_record(a.record)
    npx = {r: (sl[0].stop - sl[0].start) * (sl[1].stop - sl[1].start) for r, sl in ROIS.items()}
    ring = roi['ring']['sum']
    for e in events:
        e['T_rec'] = value_at(rec.get(PV_T), e['t'])
        e['open'] = value_at(rec.get(PV_SUM), e['t']) == 'OUT' and value_at(rec.get(PV_CMD), e['t']) == 'OUT'
        i = row_of.get(e['ts'])
        e['ring'] = float(np.sum(ring[i])) / npx['ring'] if (ring is not None and i is not None) else None
    steps, cur = [], None
    for e in events:
        if not e['open'] or e['T_rec'] is None or e['ring'] is None:
            cur = None
            continue
        if cur is None or cur['T_text'] != e['T_rec']:
            cur = dict(T_text=e['T_rec'], T=float(e['T_rec']), vals=[])
            steps.append(cur)
        cur['vals'].append(e['ring'])
    full = [s for s in steps if s['T'] == 1.0 and len(s['vals']) > 10]
    rows, ok_ratio = [], False
    if full:
        fm = float(np.mean(full[0]['vals']))
        big = [s for s in steps if len(s['vals']) >= 10]
        ok_ratio = len(big) >= 4
        for s in big:
            r = float(np.mean(s['vals'])) / fm
            dev = r / s['T'] - 1.0 if s['T'] > 0 else float('nan')
            rows.append('T=%s n=%d ratio=%.4f dev=%+.2f%%' % (s['T_text'], len(s['vals']), r, 100 * dev))
            ok_ratio = ok_ratio and abs(dev) <= RATIO_TOL
    check('ratio', ok_ratio, '; '.join(rows) if rows else 'no full-beam step found')

    t_in = next((t for t, v in rec.get(PV_SUM, []) if v == 'IN' and events and t > events[0]['t']), None)
    after = [e for e in events if t_in is not None and e['t'] >= t_in and e['ring'] is not None]
    worst_dark = max((abs(e['ring']) for e in after), default=None)
    check('dark', bool(after) and worst_dark <= DARK_TOL,
          "%d events after the record's stopper IN; worst |ring ROI mean calib| %s"
          % (len(after), ('%.4f' % worst_dark) if worst_dark is not None else '-'))

    dk = roi['dark']['sum']
    if dk is not None:
        dmean = float(np.mean([float(np.sum(dk[row_of[e['ts']]])) for e in events if e['ts'] in row_of])) / npx['dark']
        check('pedestal', abs(dmean) <= PED_TOL, 'dark ROI mean calib over the run %.4f (tolerance %.2f)'
              % (dmean, PED_TOL))
    else:
        check('pedestal', False, 'no dark ROI dataset')

    nfail = sum(1 for c in checks if not c[1])
    print('SUMMARY %d checks, %d PASS, %d FAIL%s' % (len(checks), len(checks) - nfail, nfail,
          (' (failing: %s)' % ', '.join(c[0] for c in checks if not c[1])) if nfail else ''))
    if a.json:
        json.dump(dict(checks=[dict(name=n, ok=o, evidence=e) for n, o, e in checks], steps=rows,
                       n_events=len(events), h5_rows=int(len(ts)), sums=sums), open(a.json, 'w'), indent=1)
    return 0 if nfail == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
