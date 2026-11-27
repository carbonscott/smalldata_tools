"""Loaded at every python start via PYTHONPATH (harness only, not smalldata_tools).

1. X6_LGBK_URL set: any requests call to https://pswww.slac.stanford.edu (psana's hard-coded logbook
   file-list URL, psexp/ds_base.py _file_info_url) goes to the loopback stand-in instead, which answers 404,
   so psana falls back to the files on disk. Nothing leaves the private network namespace.
2. THR_TIMING_DIR set: wraps smalldata_tools.lcls2.DetObject.DetObjectClass.processSums with a
   perf_counter_ns timer, without touching the smalldata_tools tree, and writes one line per call
   (<det> <ns>) to THR_TIMING_DIR/pid<pid>.txt at exit.
"""
import os
import sys

_FACILITY = "https://pswww.slac.stanford.edu"
_url = os.environ.get("X6_LGBK_URL")
if _url:
    try:
        import requests.sessions as _rs

        _orig_request = _rs.Session.request

        def _request(self, method, url, *a, **k):
            if isinstance(url, str) and url.startswith(_FACILITY):
                url = _url + url[len(_FACILITY):]
            return _orig_request(self, method, url, *a, **k)

        _rs.Session.request = _request
    except ImportError:
        pass

_tdir = os.environ.get("THR_TIMING_DIR")
if _tdir:
    import atexit
    import time

    _TARGET = "smalldata_tools.lcls2.DetObject"
    _times = []

    def _patch(module):
        cls = module.DetObjectClass
        orig = cls.processSums

        def processSums(self, *a, **k):
            t0 = time.perf_counter_ns()
            try:
                return orig(self, *a, **k)
            finally:
                _times.append((self._name, time.perf_counter_ns() - t0))

        cls.processSums = processSums

    def _dump():
        if _times:
            os.makedirs(_tdir, exist_ok=True)
            with open(os.path.join(_tdir, "pid%d.txt" % os.getpid()), "w") as f:
                f.writelines("%s %d\n" % t for t in _times)

    atexit.register(_dump)

    class _Finder:
        def find_spec(self, name, path, target=None):
            if name != _TARGET:
                return None
            for f in sys.meta_path:
                if f is self or not hasattr(f, "find_spec"):
                    continue
                spec = f.find_spec(name, path, target)
                if spec is not None:
                    break
            else:
                return None
            orig_exec = spec.loader.exec_module

            def exec_module(module):
                orig_exec(module)
                _patch(module)

            spec.loader.exec_module = exec_module
            return spec

    sys.meta_path.insert(0, _Finder())
