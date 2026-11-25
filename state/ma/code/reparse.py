# Stack the OCPF yearly files (data/raw/<YYYY>/reports.txt, report-items.txt, from
# https://ocpf2.blob.core.windows.net/downloads/data2/ocpf-<YYYY>-reports.zip) into UTF-8 CSVs in data/parsed/, where
# ma_common.R reads them. Read-only on inputs.
#   python3 state/ma/code/reparse.py state/ma
# The files are tab-delimited UTF-8 with a trailing tab; records end with "\r\n" (a few fields hold a bare "\n" or a
# vertical tab, kept as published). Text fields are in double quotes, with no quotes inside them; the enclosing quotes
# are removed. Adds source_year (the zip's year).
import csv, sys
from pathlib import Path

base = Path(sys.argv[1]).resolve()
raw, out = base / 'data' / 'raw', base / 'data' / 'parsed'
out.mkdir(exist_ok=True)
years = sorted(p.name for p in raw.iterdir() if p.is_dir())
for kind, name in (('reports', 'reports.txt'), ('items', 'report-items.txt')):
    hdr, n = None, 0
    with open(out / f'ma_{kind}.csv', 'w', newline='', encoding='utf-8') as g:
        w = csv.writer(g)
        for y in years:
            t = (raw / y / name).read_bytes().decode('utf-8')
            assert t.endswith('\r\n'), (y, name)
            recs = t[:-2].split('\r\n')
            h = recs[0].split('\t')
            assert h[-1] == '', (y, name, 'no trailing tab')
            h = h[:-1]
            if hdr is None:
                hdr = h
                w.writerow(h + ['source_year'])
            assert h == hdr, (y, name, 'header differs')
            for r in recs[1:]:
                f = r.split('\t')
                assert len(f) == len(hdr) + 1 and f[-1] == '', (y, name, f[:3])
                f = [x[1:-1] if len(x) >= 2 and x[0] == '"' and x[-1] == '"' else x for x in f[:-1]]
                w.writerow(f + [y])
                n += 1
    print(kind, 'years', len(years), 'records', n, 'columns', len(hdr))
