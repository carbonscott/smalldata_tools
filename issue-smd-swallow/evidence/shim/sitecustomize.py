# x6 harness shim (loaded only when this folder is on PYTHONPATH, i.e. only by run_x6.sh).
#
# psana2 (release lcls2_111826, psana/psexp/ds_base.py:377-378) hard-codes the logbook URL that
# DataSource(exp=..., run=..., dir=...) asks for a run's file list, even when not in live mode:
#     https://pswww.slac.stanford.edu/ws/lgbk/lgbk/<exp>/ws/<run>/current_files_for_live_mode
# There is no environment override (the calibration DB has LCLS_CALIB_HTTP), and the requests.get()
# sits outside the try that would fall back to the files on disk (ds_base.py:399-406), so an offline
# test either contacts the facility's logbook or crashes. With X6_LGBK_URL set, this hook points that
# one method at a loopback stand-in (calibws_jf.py answers 404, so psana takes its own disk fallback).
# Nothing else in psana or smalldata_tools is changed.
import os
import sys

_URL = os.environ.get("X6_LGBK_URL")
if _URL:
    import importlib.abc
    import importlib.util

    class _LgbkRedirect(importlib.abc.MetaPathFinder):
        def find_spec(self, name, path, target=None):
            if name != "psana.psexp.ds_base":
                return None
            sys.meta_path.remove(self)
            spec = importlib.util.find_spec(name)
            if spec is None or spec.loader is None:
                return spec
            orig = spec.loader.exec_module

            def exec_module(module):
                orig(module)

                def _file_info_url(self, runnum):
                    return f"{_URL}/lgbk/{self.exp}/ws/{runnum}/current_files_for_live_mode"
                module.DataSourceBase._file_info_url = _file_info_url
            spec.loader.exec_module = exec_module
            return spec

    sys.meta_path.insert(0, _LgbkRedirect())
