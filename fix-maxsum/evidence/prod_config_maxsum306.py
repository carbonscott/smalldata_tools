"""fix-maxsum (upstream issue 306) test config: smalldata_tools lcls2 producer, one simulated Jungfrau module.

Derived from the issue's prod_config_maxsum.py. Sums: calib (listed explicitly: the producer adds it only when no sum list is given), calib_max,
calib_square and calib_thresADU5, with calib_max listed BEFORE the threshold key so that DetObject's in-place
threshold (upstream issue 305, a separate fix) cannot touch it. The non-max keys are there to show that the
fix leaves every SUM-reduced key byte-identical to master.
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
        ret_dict["jungfrau"] = ["calib", "calib_max", "calib_square", "calib_thresADU5"]
    return ret_dict


epicsPV = []
epicsArchFilePV = []
epicsOncePV = []
