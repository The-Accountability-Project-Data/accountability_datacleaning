"""
Download the IRS Exempt Organizations Business Master File Extract (EO BMF)
regional CSV files into this script's directory.

Source page:
https://www.irs.gov/charities-non-profits/exempt-organizations-business-master-file-extract-eo-bmf
"""

import os
import shutil
import urllib.request

BASE_URL = "https://www.irs.gov/pub/irs-soi/"

REGION_FILES = {
    "eo1.csv": "Region 1 - Northeast",
    "eo2.csv": "Region 2 - Mid-Atlantic and Great Lakes",
    "eo3.csv": "Region 3 - Gulf Coast and Pacific Coast",
    "eo4.csv": "Region 4 - All other areas",
}

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# irs.gov sometimes rejects requests with the default python user agent
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; eobmf-downloader)"}


def download(filename):
    url = BASE_URL + filename
    out_path = os.path.join(OUT_DIR, filename)
    tmp_path = out_path + ".part"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as response, open(tmp_path, "wb") as fh:
        shutil.copyfileobj(response, fh)
    os.replace(tmp_path, out_path)
    return out_path


if __name__ == "__main__":
    for filename, description in REGION_FILES.items():
        print(f"Downloading {description}: {BASE_URL + filename}")
        path = download(filename)
        print(f"  saved {path} ({os.path.getsize(path):,} bytes)")
