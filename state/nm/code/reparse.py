"""
New Mexico CFIS yearly downloads -> one parsed CSV per kind (November 2026).
  python3 -I state/nm/code/reparse.py <raw dir> <out dir>
Input: CON_<year>.csv (contributions and loans, 35 columns) and EXP_<year>.csv (expenditures, 32 columns), 2020-2026,
from https://login.cfis.sos.state.nm.us (Data Download).
Files are by transaction year.
- Every record is one CRLF-terminated line. A line a CSV reader does not split into the header's fields (a value
  that opens with a quote it never closes, as in "2024 Lakewood Avenue NW) is regrouped from its comma-separated
  pieces (a group of pieces only where it starts and ends with a quote); failing that it is listed and left out.
- Decoded as UTF-8, or as Windows-1252 when a line is not valid UTF-8.
Output: header names in snake case (as in the 2021 build), plus file_year. Values as published.
"""
import csv, glob, json, os, re, sys
from functools import lru_cache
RAW, OUT = sys.argv[1:3]

def snake(h):
    return re.sub(r'_+', '_', re.sub(r'[^a-z0-9]+', '_', h.strip().lower())).strip('_')

def regroup(rec, w):
    t = rec.split(','); n = len(t)
    if n > 400: return None
    @lru_cache(None)
    def go(i, k):
        if i == n: return (0, ()) if k == 0 else None
        if k == 0 or n - i < k: return None
        best = None
        for j in range(i + 1, n + 1):
            piece = ','.join(t[i:j])
            if j - i > 1 and not (piece.startswith('"') and piece.endswith('"') and len(piece) > 1): continue
            rest = go(j, k - 1)
            if rest is None: continue
            cost = rest[0] + ('"' in piece and j - i == 1)
            if best is None or cost < best[0]: best = (cost, (piece,) + rest[1])
        return best
    r = go(0, w)
    if r is None: return None
    return [(v[1:-1] if len(v) >= 2 and v[0] == '"' and v[-1] == '"' else v).replace('""', '"') for v in r[1]]

stats = {}
for kind, name in (('CON', 'nm_contribs'), ('EXP', 'nm_expends')):
    st = {'files': 0, 'rows': 0, 'cp1252': 0, 'regrouped': 0, 'failed': 0, 'blank': 0}
    header = None
    out = csv.writer(open(os.path.join(OUT, name + '.csv'), 'w', encoding='utf-8', newline=''))
    for f in sorted(glob.glob(os.path.join(RAW, kind + '_*.csv'))):
        year = re.search(r'_(\d{4})\.csv$', f).group(1)
        lines = open(f, 'rb').read().split(b'\r\n')
        h = next(csv.reader([lines[0].decode('utf-8-sig')]))
        if header is None:
            header, w = h, len(h); out.writerow([snake(x) for x in header] + ['file_year'])
        assert h == header, (f, h)
        st['files'] += 1
        for raw in lines[1:]:
            if not raw.strip(b' ,'):
                st['blank'] += 1; continue
            try: rec = raw.decode('utf-8')
            except UnicodeDecodeError: rec = raw.decode('cp1252', errors='replace'); st['cp1252'] += 1
            rec = re.sub(r'[\r\n]+', ' ', rec)
            row = next(csv.reader([rec]), [])
            if len(row) != w:
                row = regroup(rec, w)
                if row is None:
                    st['failed'] += 1; print('FAILED', os.path.basename(f), rec[:300]); continue
                st['regrouped'] += 1; print('REGROUPED', os.path.basename(f), row)
            out.writerow(row + [year]); st['rows'] += 1
    stats[kind] = st
print(json.dumps(stats, indent=1))
