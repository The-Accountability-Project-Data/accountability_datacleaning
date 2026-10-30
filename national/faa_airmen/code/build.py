# Copied 2026-10-30 from the datacleaning_agents repo (datasets/faa-airmen-2026/build.py): the script that built the October 2026 file.
# It imports buildlib.py (copied alongside) from ../../tools in that repo; to run it from here, change that path to this folder.
#
"""
Build FAA Airmen 2026 from the releasable airmen zip (comma separated format).

  .venv/bin/python datasets/faa-airmen-2026/build.py work/faa-airmen-2026/raw/2026-10-05/CS102026.zip

- Stacks PILOT_BASIC.csv and NONPILOT_BASIC.csv (same columns), as the 2023 dataset did, and
  adds `airman_type` ('pilot' / 'non-pilot') saying which file each row came from. 63,078 people
  (Oct. 2026) are in both files, so they appear twice -- once per type. Certificate files are
  not included (as in 2023).
- Column names lower-case with underscores, as 2023 (`UNIQUE ID` -> `uniqueid`, as 2023 named it).
- Trims space padding from every value; drops the empty trailing column.
- Adds `uszip5` (first five digits of a US ZIP, blank otherwise) and `year` (the release year,
  2026 on every row).
Writes work/faa-airmen-2026/clean/airmen_<release date>.csv and logs to builds.jsonl.
"""
import csv
import io
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools'))
from buildlib import HERE, log_build, now, rel, sha256, snake, uszip5  # noqa: E402

DS_DIR = os.path.dirname(os.path.abspath(__file__))
FILES = (('PILOT_BASIC.csv', 'pilot'), ('NONPILOT_BASIC.csv', 'non-pilot'))
RENAME = {'unique_id': 'uniqueid'}          # 2023's name for it


def main():
    src = sys.argv[1]
    m = re.search(r'CS(\d\d)(\d{4})\.zip$', src)
    month, year = m.group(1), m.group(2)
    z = zipfile.ZipFile(src)
    # the zip's own files carry the release date
    stamp = max(i.date_time for i in z.infolist() if i.filename == 'PILOT_BASIC.csv')
    release = '%04d-%02d-%02d' % stamp[:3]
    out_dir = os.path.join(HERE, 'work', 'faa-airmen-2026', 'clean')
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, 'airmen_%s.csv' % release)
    started, counts, header_out = now(), {}, None
    with open(out + '.part', 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        for name, kind in FILES:
            r = csv.reader(io.TextIOWrapper(z.open(name), encoding='utf-8', newline=''))
            header = next(r)
            keep = [i for i, c in enumerate(header) if c.strip()]          # drop empty trailing column
            cols = [RENAME.get(snake(header[i]), snake(header[i])) for i in keep]
            if header_out is None:
                header_out = cols + ['airman_type', 'uszip5', 'year']
                w.writerow(header_out)
            assert cols == header_out[:len(cols)], "PILOT/NONPILOT headers differ"
            zi, ci = cols.index('zip_code'), cols.index('country')
            n = 0
            for row in r:
                vals = [row[i].strip() if i < len(row) else '' for i in keep]
                w.writerow(vals + [kind, uszip5(vals[zi], vals[ci]), year])
                n += 1
            counts[name] = n
    os.replace(out + '.part', out)
    total = sum(counts.values())
    log_build(DS_DIR, {
        'built_at': started, 'finished_at': now(), 'tool': 'datasets/faa-airmen-2026/build.py',
        'input': {'path': rel(src), 'sha256': sha256(src), 'release': release, 'files': counts},
        'output': {'path': rel(out), 'sha256': sha256(out), 'bytes': os.path.getsize(out),
                   'rows': total, 'columns': len(header_out)},
        'columns': header_out,
    })
    print("wrote %s: %s rows x %d columns (%s)" % (rel(out), format(total, ','), len(header_out), counts))


if __name__ == '__main__':
    main()
