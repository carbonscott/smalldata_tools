"""smalldata_tools lcls2 producer config for x6: the simulated MFX Jungfrau module (one 512 x 1024 panel).

Derived from smalldata_tools' own prod_config_mfx.py (c7287eb): same structure, the Jungfrau ROI/sum
entries switched on, every other analysis left off. This file is what a hutch writes per experiment;
smd_producer.py itself is run unmodified.

ROIs ([[segment], [rows], [cols]], half-open; the data are (1, 512, 1024)):
  ring  : rows 246:266, cols 682:702  -- on the crest of the simulator's scattering ring (radius 180
          around row 256, col 512), so it follows the attenuator and the stopper
  dark  : rows 400:420, cols 0:20     -- 530+ pixels from the ring centre: no signal, pedestal only
"""

import numpy as np

detectors = ["jungfrau"]
integrating_detectors = []

RING_ROI = [[0, 1], [246, 266], [682, 702]]
DARK_ROI = [[0, 1], [400, 420], [0, 20]]


def getROIs(run):
    ret_dict = {}
    if run > 0:
        ret_dict["jungfrau"] = [
            {"name": "ROI_ring", "thresADU": None, "writeArea": False, "calcPars": True, "ROI": RING_ROI},
            {"name": "ROI_dark", "thresADU": None, "writeArea": False, "calcPars": True, "ROI": DARK_ROI},
        ]
    return ret_dict


def get_sum_algos(run):
    """MFX's own sum list, verbatim from prod_config_mfx.py (c7287eb)."""
    ret_dict = {}
    if run > 0:
        ret_dict["all"] = [
            "calib",
            "calib_square",
            "calib_thresADU1",
        ]
        ret_dict["jungfrau"] = ["calib_thresADU5", "calib_max"]
    return ret_dict


epicsPV = []
epicsArchFilePV = []
epicsOncePV = []
