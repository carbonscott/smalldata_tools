"""fix-threshold harness config: two threshold keys, falling, then nhits, max and calib after them (the worst order for master) on the
simulated Jungfrau, plus subsampled full images of the Jungfrau every 0.5 s. No ROIs, no other analysis."""

detectors = ["jungfrau"]
integrating_detectors = []


def get_sum_algos(run):
    ret_dict = {}
    if run > 0:
        ret_dict["jungfrau"] = [
            "calib_thresADU5",
            "calib_thresADU1",
            "calib_nhits",
            "calib_max",
            "calib",
        ]
    return ret_dict


def get_subsample_config(run):
    return {"detectors": ["jungfrau"], "interval": 0.5}


epicsPV = []
epicsArchFilePV = []
epicsOncePV = []
