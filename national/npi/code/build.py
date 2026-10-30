# Copied 2026-10-30 from the datacleaning_agents repo (datasets/npi-2026/build.py): the script that built the 2026 file.
# Output path follows that repo's layout (work/npi-2026/clean/); change it before running from here.
#
"""
Build the NPI 2026 CSV from the downloaded NPPES zip: drop deactivated NPIs and reduce
330 columns to 80. No cleaning -- values are copied as-is.

  .venv/bin/python datasets/npi-2026/build.py work/npi-2026/raw/2026-10-04/NPPES_Data_Dissemination_September_2026_V2.zip

Rows:    keep entity type 1 (individuals) and 2 (organizations). Deactivated NPIs have a
         blank entity type and carry only the NPI and deactivation date (no name or
         address), so they are dropped.
Columns: all 55 single (non-repeating) columns, plus the first 5 of each specialty/license
         block -- Healthcare Provider Taxonomy Code, Provider License Number, Provider License
         Number State Code, Healthcare Provider Primary Taxonomy Switch, Healthcare Provider
         Taxonomy Group (slots 1-5, 25 columns). Dropped: those blocks' slots 6-15 (each under
         1% filled in Sept. 2026) and all 50 "Other Provider Identifier" sets (200 columns).
         Original column names and order are kept.
Year:    adds a final column `year`, set for every row to the year the data runs through
         (2026 for the Sept. 2026 file) -- this is a snapshot, so every row is that year.

Writes   work/npi-2026/clean/npi_<data-through-date>.csv
         datasets/npi-2026/builds.jsonl  (input/output sha256, counts, columns kept/dropped)
"""
import csv
import hashlib
import io
import json
import os
import re
import sys
import zipfile
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DS_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, 'work', 'npi-2026', 'clean')
KEEP_SLOTS = 5
BLOCKS = ('Healthcare Provider Taxonomy Code', 'Provider License Number', 'Provider License Number State Code',
          'Healthcare Provider Primary Taxonomy Switch', 'Healthcare Provider Taxonomy Group')
csv.field_size_limit(10 ** 8)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8 * 2 ** 20), b''):
            h.update(chunk)
    return h.hexdigest()


def keep_column(name):
    m = re.match(r'(.+)_(\d+)$', name)
    if not m:
        return True                                  # single column
    base, slot = m.group(1), int(m.group(2))
    if base in BLOCKS:
        return slot <= KEEP_SLOTS
    return False                                     # Other Provider Identifier* blocks


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    z = zipfile.ZipFile(src)
    main_name = next(n for n in z.namelist() if re.match(r'npidata_pfile_\d{8}-\d{8}\.csv$', n))
    through = re.search(r'-(\d{4})(\d{2})(\d{2})\.csv$', main_name).groups()
    out_path = os.path.join(OUT_DIR, 'npi_%s-%s-%s.csv' % through)
    os.makedirs(OUT_DIR, exist_ok=True)

    started = datetime.now(timezone.utc)
    reader = csv.reader(io.TextIOWrapper(z.open(main_name), encoding='utf-8', newline=''))
    header = next(reader)
    keep = [i for i, c in enumerate(header) if keep_column(c)]
    et = header.index('Entity Type Code')
    rows_in = rows_out = 0
    by_type = {}
    with open(out_path + '.part', 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow([header[i] for i in keep] + ['year'])
        for row in reader:
            rows_in += 1
            t = row[et]
            by_type[t or '(blank)'] = by_type.get(t or '(blank)', 0) + 1
            if t not in ('1', '2'):
                continue
            w.writerow([row[i] for i in keep] + [through[0]])
            rows_out += 1
    os.replace(out_path + '.part', out_path)

    rec = {
        'built_at': started.isoformat(timespec='seconds'),
        'finished_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'tool': 'datasets/npi-2026/build.py',
        'input': {'path': os.path.relpath(src, HERE), 'sha256': sha256(src), 'member': main_name},
        'output': {'path': os.path.relpath(out_path, HERE), 'sha256': sha256(out_path),
                   'bytes': os.path.getsize(out_path), 'rows': rows_out, 'columns': len(keep) + 1},
        'rows_in': rows_in,
        'rows_by_entity_type_in': by_type,
        'rows_dropped': rows_in - rows_out,
        'columns_in': len(header),
        'columns_kept': [header[i] for i in keep],
        'columns_added': {'year': through[0]},
        'columns_dropped_count': len(header) - len(keep),
    }
    with open(os.path.join(DS_DIR, 'builds.jsonl'), 'a') as f:
        f.write(json.dumps(rec) + '\n')
    print("wrote %s: %s rows x %d columns (%s bytes); dropped %s rows, %d columns"
          % (rec['output']['path'], format(rows_out, ','), len(keep) + 1, format(rec['output']['bytes'], ','),
             format(rec['rows_dropped'], ','), rec['columns_dropped_count']))


if __name__ == '__main__':
    main()
