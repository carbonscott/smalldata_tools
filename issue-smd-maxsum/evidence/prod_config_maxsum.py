"""smd-maxsum: a smalldata_tools lcls2 producer config with one per-pixel max over the run.

Derived from smalldata_tools' prod_config_mfx.py: the Jungfrau entry switched on, the two ROIs of the x6
bench (simulated MFX Jungfrau, one 512 x 1024 module), and a sum list of calib (always stored by the
producer) and calib_max ONLY, with no calib_thresADU key, so that DetObject.processSums' in-place
threshold (a separate bug) cannot touch calib_max. smd_producer.py itself is run unmodified.
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
    ret_dict = {}
    if run > 0:
        ret_dict["jungfrau"] = ["calib_max"]
    return ret_dict


epicsPV = []
epicsArchFilePV = []
epicsOncePV = []
