"""calibws_jf: a loopback stand-in for the LCLS calibration-constants web service (calib_ws), serving
Jungfrau constants whose values are known, so that psana2's det.raw.calib() (and smalldata_tools on
top of it) can be checked against a closed form.

Modelled on lcls2 sim-main's psdaq/psdaq/sim/calibws_server.py (which serves an ePixUHR 3x2); this
one serves a single 512 x 1024 Jungfrau module in psana's shape (3 gain modes, 1 segment, 512, 1024).

    python calibws_jf.py --port P [--pedestal 1031.5] [--gain 40.0] [--fault NAME] [--log F]

Constants (gain mode g = 0, 1, 2; the simulated module only ever sends gain bits 0):
  pedestals[g]    = PEDESTAL + 100*g            (ADU; PEDESTAL defaults to 1031.5, the simulated
                                                 module's true dark mean: 1000 + mean of 0..63)
  pixel_gain[g]   = GAIN / (1, 30, 600)[g]      (ADU per keV)
  pixel_rms[g]    = 18.47 (the rms of uniform 0..63 ADU noise; a dark run deploys it, and smalldata_tools'
                    ROIFunc needs it to reshape the detector's x/y to the data shape)
  pixel_status[g] = 1 for pixels 0..15 (row 0, columns 0..15: the simulator's state stamp), else 0
psana then computes calib = ((raw & 0x3fff) - pedestals[g]) / pixel_gain[g] * mask.

--fault plants one deployment mistake (what a stale or wrong calibration looks like):
  stale-pedestal   pedestals[0] = 1000.0 (a dark taken before the noise floor was right: +31.5 ADU)
  wrong-gain-mode  pixel_gain[0] = pixel_gain[1] (the gain plane of the wrong mode deployed)
  no-mask          pixel_status all 0 (the stamp pixels are not masked)

It answers the requests psana.pscalib.calib.MDBWebUtils makes (URL = LCLS_CALIB_HTTP):
  GET <db>/<col>?query_string=<json>  (or a JSON body)   -> a list of documents
  GET <db>/gridfs/<id>                                   -> the array's bytes
For any detector long name that starts with 'jungfrau'. Every request is one JSON line in --log.
It binds 127.0.0.1 only.
"""

import argparse
import json
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np

SHAPE = (3, 1, 512, 1024)
SHORT = 'jungfrau_000001'
CTYPES = ('pedestals', 'pixel_gain', 'pixel_rms', 'pixel_status')
NOISE_RMS = float(((64 ** 2 - 1) / 12.0) ** 0.5)     # rms of the simulator's uniform 0..63 ADU noise
GAIN_DIV = (1.0, 30.0, 600.0)
STAMP_PIXELS = 16
FAULTS = ('stale-pedestal', 'wrong-gain-mode', 'no-mask')


def constants(pedestal, gain, fault=None):
    ped = np.empty(SHAPE, dtype=np.float32)
    gn = np.empty(SHAPE, dtype=np.float32)
    for g in range(3):
        ped[g] = pedestal + 100.0 * g
        gn[g] = gain / GAIN_DIV[g]
    rms = np.full(SHAPE, NOISE_RMS, dtype=np.float32)
    status = np.zeros(SHAPE, dtype=np.uint64)
    status[:, 0, 0, :STAMP_PIXELS] = 1
    if fault == 'stale-pedestal':
        ped[0] = 1000.0
    elif fault == 'wrong-gain-mode':
        gn[0] = gn[1]
    elif fault == 'no-mask':
        status[:] = 0
    return {'pedestals': ped, 'pixel_gain': gn, 'pixel_rms': rms, 'pixel_status': status}


class Store:
    def __init__(self, pedestal, gain, fault):
        self.arrays = constants(pedestal, gain, fault)
        t = int(time.time())
        self.docs = []
        for k, ct in enumerate(CTYPES):
            a = self.arrays[ct]
            self.docs.append({'_id': f'{t:08x}{k + 1:016x}', 'ctype': ct, 'detector': SHORT,
                              'run': 0, 'run_end': 'end', 'experiment': 'simcalib',
                              'time_sec': t - 3600, 'time_stamp': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
                              'version': 'V2026-x6', 'data_type': 'ndarray',
                              'data_dtype': str(a.dtype), 'data_shape': str(tuple(a.shape)),
                              'dtype': 'ndarray', 'longname': None, 'shortname': SHORT,
                              'id_data': f'{t:08x}{k + 101:016x}'})
        self.blobs = {d['id_data']: self.arrays[d['ctype']].tobytes() for d in self.docs}


def make_handler(store, log, lock):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass

        def _send(self, code, body, ctype='application/json'):
            self.send_response(code)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _query(self, url):
            qs = urllib.parse.parse_qs(url.query).get('query_string', [None])[0]
            if qs:
                return json.loads(qs)
            n = int(self.headers.get('Content-Length') or 0)
            if n:
                return json.loads(self.rfile.read(n) or b'{}')
            return {}

        def do_GET(self):
            url = urllib.parse.urlsplit(self.path)
            parts = [p for p in url.path.split('/') if p]
            if parts and parts[0] == 'calib_ws':
                parts = parts[1:]
            try:
                query = self._query(url)
            except ValueError:
                query = None
            code, body, ctype, served = 404, b'[]', 'application/json', None
            if len(parts) == 3 and parts[1] == 'gridfs' and parts[2] in store.blobs:
                code, body, ctype = 200, store.blobs[parts[2]], 'application/octet-stream'
                served = f'{len(body)} B'
            elif len(parts) == 2 and query is not None:
                db, col = parts
                if db == 'cdb_detnames':
                    long = query.get('long', '') if isinstance(query, dict) else ''
                    docs = [{'long': long, 'short': SHORT}] if str(long).startswith('jungfrau') else []
                    code, body, served = 200, json.dumps(docs).encode(), [d['short'] for d in docs]
                elif col == SHORT:
                    want = {k: v for k, v in query.items() if k == 'ctype'}
                    docs = [d for d in store.docs if all(d.get(k) == v for k, v in want.items())]
                    if db != f'cdb_{SHORT}':
                        docs = []           # an experiment's database: none; psana falls back to the detector's
                    code, body, served = 200, json.dumps(docs).encode(), [d['ctype'] for d in docs]
                else:
                    code, body, served = 200, b'[]', []
            elif len(parts) == 3 and query is not None and parts[1] == SHORT:
                docs = [d for d in store.docs if d['_id'] == parts[2]]
                code, body = (200, json.dumps(docs[0]).encode()) if docs else (404, b'{}')
            self._send(code, body, ctype)
            with lock:
                log.write(json.dumps({'t': time.time(), 'path': url.path, 'query': query,
                                      'status': code, 'served': served}) + '\n')
                log.flush()

    return Handler


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--port', type=int, required=True)
    p.add_argument('--pedestal', type=float, default=1031.5)
    p.add_argument('--gain', type=float, default=40.0)
    p.add_argument('--fault', choices=FAULTS, default=None)
    p.add_argument('--log', default=None)
    a = p.parse_args(argv)
    store = Store(a.pedestal, a.gain, a.fault)
    log = open(a.log, 'a') if a.log else sys.stdout
    srv = ThreadingHTTPServer(('127.0.0.1', a.port), make_handler(store, log, threading.Lock()))
    srv.daemon_threads = True
    print(f'calibws_jf: ready on 127.0.0.1:{a.port}: {SHORT} pedestal {a.pedestal} gain {a.gain} '
          f'fault {a.fault}', flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
