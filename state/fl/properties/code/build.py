# Reads header_2021.txt from this script's folder (code/), whatever the working directory.
"""Build "Florida Property Assessments 2026" from the Florida Department of Revenue's 2026 county NAL files.

    python build.py <folder of county NAL zips> <output.csv>

Follows state/fl/properties (2018: csvstack the county CSVs, then fix_properties.py adds
PHY_STATE = "FL"), with these changes:
* reads each county zip directly and writes one file;
* the columns are the 2026 NAL layout in the state's order (the first Final NAL file's header), then PHY_STATE, as in
  the 2021 file (csv/cleaned_fl_properties.csv, 2021 roll). The 2026 layout is the 2021 one with EXMPT_43 to
  EXMPT_48 added after EXMPT_42;
* a county file without a column (the preliminary files have no EXMPT_47 or EXMPT_48) gets it blank.
Every value is written as published. Uses the Final NAL file where there is one, else the Preliminary NAL.
Writes <out>.counties.tsv with each county's file and rows. Stops if a county has two files or a column not listed.
"""
import csv
import io
import os
import re
import sys
import zipfile
from urllib.parse import unquote

# header of csv/cleaned_fl_properties.csv (2021 roll): the NAL columns in the state's order, then PHY_STATE
HEADER_2021 = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'header_2021.txt')


def main(raw_dir, out):
    cols_2021 = open(HEADER_2021).read().split(',')
    header = None
    files = {}
    for name in sorted(os.listdir(raw_dir)):
        if not name.endswith('.zip'):
            continue
        m = re.match(r'(.+?)\s*(\d\d) (Final|Preliminary) NAL (\d{4})\.zip$', unquote(name))
        if not m:
            sys.exit(f'unexpected file name {name}')
        county, co, kind, year = m.groups()
        if co in files and files[co][2] == 'Final':
            continue
        if co in files and kind != 'Final':
            continue
        files[co] = (county, name, kind, year)
    # the layout: the first Final file's header, then PHY_STATE; it must hold every 2021 column
    first = next(files[co][1] for co in sorted(files) if files[co][2] == 'Final')
    with zipfile.ZipFile(os.path.join(raw_dir, first)) as z:
        member = [n for n in z.namelist() if n.lower().endswith('.csv')][0]
        header = next(csv.reader(io.TextIOWrapper(z.open(member), encoding='utf-8', newline=''))) + ['PHY_STATE']
    lost = [c for c in cols_2021 if c not in header]
    if lost:
        sys.exit(f'2021 columns missing from the 2026 layout: {lost}')
    print('added since 2021:', [c for c in header if c not in cols_2021])
    rows_total = 0
    with open(out, 'w', encoding='utf-8', newline='') as fh, open(out + '.counties.tsv', 'w') as tsv:
        tsv.write('co_no\tcounty\troll\tzip\tmember\trows\tmissing_columns\n')
        w = csv.writer(fh)
        w.writerow(header)
        for co in sorted(files):
            county, name, kind, year = files[co]
            with zipfile.ZipFile(os.path.join(raw_dir, name)) as z:
                members = [n for n in z.namelist() if n.lower().endswith('.csv')]
                if len(members) != 1:
                    sys.exit(f'{name}: expected one csv, found {members}')
                with z.open(members[0]) as raw:
                    r = csv.reader(io.TextIOWrapper(raw, encoding='utf-8', newline=''))
                    src = next(r)
                    extra = [c for c in src if c not in header]
                    if extra:
                        sys.exit(f'{name}: columns not in the layout: {extra}')
                    idx = {c: i for i, c in enumerate(src)}
                    missing = [c for c in header if c not in idx and c != 'PHY_STATE']
                    n = 0
                    for row in r:
                        if len(row) != len(src):
                            sys.exit(f'{name}: row {n + 2} has {len(row)} fields, header has {len(src)}')
                        w.writerow(['FL' if c == 'PHY_STATE' else (row[idx[c]] if c in idx else '') for c in header])
                        n += 1
            rows_total += n
            tsv.write(f'{co}\t{county}\t{kind} {year}\t{unquote(name)}\t{members[0]}\t{n}\t{",".join(missing)}\n')
            print(f'{co} {county}: {kind} {year}, {n:,} rows' + (f', blank {missing}' if missing else ''), flush=True)
    print(f'wrote {out}: {rows_total:,} rows, {len(header)} columns, {len(files)} counties')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
