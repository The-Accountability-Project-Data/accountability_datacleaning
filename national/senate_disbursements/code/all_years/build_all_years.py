"""
Build the all-years export: copy each report directory's senate_data.csv (read_pages.py output, improved mode by
default) here as <report>_senate_data.csv, clean each with clean_files.py (16 columns), and concatenate the cleaned
files, oldest report first, into senate_disbursements_all.csv (one header row).

  cd all_years && python3 build_all_years.py              # improved-mode parses
  cd all_years && python3 build_all_years.py --baseline   # the 2015-logic parses (senate_data_baseline.csv)
"""
import argparse
import csv
import glob
import os
import re
import shutil
import subprocess
import sys


def report_key(d):
    m = re.match(r"(\d+)_sdoc(\d+)", d)
    return (int(m.group(1)), int(m.group(2)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--baseline", action="store_true")
    a = ap.parse_args()
    src = "senate_data_baseline.csv" if a.baseline else "senate_data.csv"
    reports = sorted((os.path.basename(d.rstrip("/")) for d in glob.glob("../1*_sdoc*/")), key=report_key)
    files = []
    for r in reports:
        path = os.path.join("..", r, src)
        if not os.path.exists(path):
            print("no %s in %s, skipped" % (src, r))
            continue
        shutil.copy(path, "%s_senate_data.csv" % r)
        files.append("%s_senate_data.csv" % r)
    subprocess.run([sys.executable, "clean_files.py"] + files, check=True)
    out = "senate_disbursements_all%s.csv" % ("_baseline" if a.baseline else "")
    total = 0
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        for i, f in enumerate(files):
            rows = csv.reader(open(f.replace(".csv", "_cleaned.csv"), encoding="utf-8"))
            header = next(rows)
            if i == 0:
                w.writerow(header)
            for row in rows:
                w.writerow(row)
                total += 1
    print("%s: %s rows from %s reports (%s to %s)" % (out, total, len(files), files[0][:10], files[-1][:10]))


if __name__ == "__main__":
    main()
