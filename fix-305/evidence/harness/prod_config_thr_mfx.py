"""fix-threshold harness config: MFX's own sum list (prod_config_mfx.py at 113800e, verbatim order) on the
simulated Jungfrau, plus subsampled full images of the Jungfrau every 0.5 s. No ROIs, no other analysis."""

detectors = ["jungfrau"]
integrating_detectors = []


def get_sum_algos(run):
    ret_dict = {}
    if run > 0:
        ret_dict["all"] = [
            "calib",
            "calib_square",
            "calib_thresADU1",
        ]
        ret_dict["jungfrau"] = ["calib_thresADU5", "calib_max"]
    return ret_dict


def get_subsample_config(run):
    return {"detectors": ["jungfrau"], "interval": 0.5}


epicsPV = []
epicsArchFilePV = []
epicsOncePV = []
