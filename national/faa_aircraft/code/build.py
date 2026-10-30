# Copied 2026-10-30 from the datacleaning_agents repo (datasets/faa-aircraft-2026/build.py): the script that built the October 2026 file.
# It imports buildlib.py (copied alongside) from ../../tools in that repo; to run it from here, change that path to this folder.
#
"""
Build FAA Aircraft 2026 from the releasable aircraft registry zip.

  .venv/bin/python datasets/faa-aircraft-2026/build.py work/faa-aircraft-2026/raw/2026-10-05/ReleasableAircraft.zip

- MASTER.txt (registered aircraft, with owners) joined to ACFTREF.txt (model reference) on the
  manufacturer/model code, as the 2023 dataset did: ACFTREF's columns first (its CODE named
  `mfr_mdl_code`), then MASTER's (its own MFR MDL CODE dropped as a duplicate). Every MASTER row
  is kept. DEREG, RESERVED, DEALER, DOCINDEX and ENGINE are not included (as in 2023).
- Column names lower-case with underscores, as 2023.
- Strips the BOM, trims space padding from every value, drops the empty trailing columns.
- Adds `uszip5` (first five digits of a US ZIP, blank otherwise) and `year` (the release year,
  2026 on every row).
Writes work/faa-aircraft-2026/clean/aircraft_<release date>.csv and logs to builds.jsonl.
"""
import csv
import io
import os
import sys
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools'))
from buildlib import HERE, log_build, now, rel, sha256, snake, uszip5  # noqa: E402

DS_DIR = os.path.dirname(os.path.abspath(__file__))


def table(z, name):
    r = csv.reader(io.TextIOWrapper(z.open(name), encoding='utf-8-sig', newline=''))
    header = next(r)
    keep = [i for i, c in enumerate(header) if c.strip()]
    cols = [snake(header[i]) for i in keep]
    return cols, ([row[i].strip() if i < len(row) else '' for i in keep] for row in r)


def main():
    src = sys.argv[1]
    z = zipfile.ZipFile(src)
    stamp = max(i.date_time for i in z.infolist() if i.filename == 'MASTER.txt')
    release = '%04d-%02d-%02d' % stamp[:3]
    year = release[:4]
    ref_cols, ref_rows = table(z, 'ACFTREF.txt')
    ref_cols = ['mfr_mdl_code'] + ref_cols[1:]                     # 'code' -> 'mfr_mdl_code'
    ref = {r[0]: r for r in ref_rows}
    m_cols, m_rows = table(z, 'MASTER.txt')
    key = m_cols.index('mfr_mdl_code')
    m_keep = [i for i in range(len(m_cols)) if i != key]
    header = ref_cols + [m_cols[i] for i in m_keep] + ['uszip5', 'year']
    zi, ci = m_cols.index('zip_code'), m_cols.index('country')
    out_dir = os.path.join(HERE, 'work', 'faa-aircraft-2026', 'clean')
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, 'aircraft_%s.csv' % release)
    started, n, unmatched = now(), 0, 0
    with open(out + '.part', 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(header)
        for row in m_rows:
            rr = ref.get(row[key])
            if rr is None:
                unmatched += 1
                rr = [row[key]] + [''] * (len(ref_cols) - 1)
            w.writerow(rr + [row[i] for i in m_keep] + [uszip5(row[zi], row[ci]), year])
            n += 1
    os.replace(out + '.part', out)
    log_build(DS_DIR, {
        'built_at': started, 'finished_at': now(), 'tool': 'datasets/faa-aircraft-2026/build.py',
        'input': {'path': rel(src), 'sha256': sha256(src), 'release': release},
        'output': {'path': rel(out), 'sha256': sha256(out), 'bytes': os.path.getsize(out),
                   'rows': n, 'columns': len(header)},
        'master_rows_without_model_match': unmatched,
        'columns': header,
    })
    print("wrote %s: %s rows x %d columns; %d without a model match" % (rel(out), format(n, ','), len(header), unmatched))


if __name__ == '__main__':
    main()
