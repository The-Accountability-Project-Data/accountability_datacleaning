# Re-read the CFB downloads with Python's csv module (RFC quoting, "" doubling, quoted CR/LF) and write
# normalized copies for duckdb; report records, bad field counts and the backslash-quote rows. Read-only on inputs.
# Each input must sit in a dataset's data/raw/ folder; its copy goes to the matching data/parsed/ folder
# (state/mn/contribs/data/raw/x.csv -> state/mn/contribs/data/parsed/x.csv), where mn_common.R reads it.
#   python3 state/mn/code/reparse.py state/mn/contribs/data/raw/<file>.csv state/mn/expends/data/raw/<file>.csv
import csv, sys, os
from pathlib import Path
csv.field_size_limit(10**9)


def parsed_path(src):
    p = Path(src).resolve()
    parts = list(p.parts)
    for i in range(len(parts) - 2, 0, -1):
        if parts[i] == 'raw' and parts[i - 1] == 'data':
            parts[i] = 'parsed'
            return str(Path(*parts))
    sys.exit(f'{src}: not in a data/raw/ folder')


for src in sys.argv[1:]:
    out = parsed_path(src)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bad, n, bs = 0, 0, 0
    with open(src, newline='', encoding='utf-8') as f, open(out, 'w', newline='', encoding='utf-8') as g:
        r = csv.reader(f); w = csv.writer(g)
        hdr = next(r); w.writerow(hdr)
        for row in r:
            n += 1
            if len(row) != len(hdr):
                bad += 1; print('BAD', n, len(row), row[:6]); continue
            if any('\\"' in v for v in row): bs += 1
            w.writerow(row)
    print(src, 'records', n, 'bad field count', bad, 'rows with backslash-quote', bs, 'cols', len(hdr))
