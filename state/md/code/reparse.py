"""
Maryland MDCRIS "Download Data" yearly files -> one parsed CSV per kind (November 2026).
  python3 -I state/md/code/reparse.py <raw dir> <out dir>
Input: md_receipts_<filing year>.csv (28 columns) and md_expenditures_<filing year>.csv (37 columns), filing years
2021-2026 (2019 and 2020 come back empty), from https://campaignfinance.maryland.gov/public/cf/downloads.
- The first line is a title ("Contributions and Loan Download as of ..."); the second is the header.
- A record starts at a line that begins with a numeric Filing Entity Id and a comma; any other line continues the
  record before it (line breaks inside fields), joined with a space.
- Each record is decoded as UTF-8, or as Windows-1252 when it is not valid UTF-8.
- A record a CSV reader does not split into the header's fields is regrouped from its comma-separated pieces (a group
  of pieces only where it starts and ends with a quote); failing that it is listed and left out.
- The export writes a curly apostrophe (as in O'Connor) as the bytes ",\xc4\xf4" (Mac Roman mojibake whose first
  character became a real comma, adding a field), 16 times in November 2026; those bytes become the apostrophe.
- Values written as Excel formulas, ="21401-2020", are unwrapped to 21401-2020.
Output: header names in snake case, plus filing_year. Values as published.
"""
import csv, glob, json, os, re, sys
from functools import lru_cache
RAW, OUT = sys.argv[1:3]
START = re.compile(rb'^\d+,')
FORMULA = re.compile(r'^="(.*)"$')

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
for kind in ('receipts', 'expenditures'):
    st = {'files': 0, 'rows': 0, 'joined_lines': 0, 'cp1252': 0, 'regrouped': 0, 'failed': 0, 'blank': 0}
    header = None
    out = csv.writer(open(os.path.join(OUT, 'md_%s.csv' % kind), 'w', encoding='utf-8', newline=''))
    for f in sorted(glob.glob(os.path.join(RAW, 'md_%s_*.csv' % kind))):
        year = re.search(r'_(\d{4})\.csv$', f).group(1)
        lines = re.split(rb'\r?\n', open(f, 'rb').read())
        h = next(csv.reader([lines[1].decode('utf-8')]))
        if header is None:
            header, w = h, len(h); out.writerow([snake(x) for x in header] + ['filing_year'])
        assert h == header, (f, h)
        st['files'] += 1
        recs = []
        for ln in lines[2:]:
            if not ln.strip(b' ,'):
                st['blank'] += 1; continue
            if recs and not START.match(ln):
                recs[-1] += b' ' + ln; st['joined_lines'] += 1
            else:
                recs.append(ln)
        for raw in recs:
            if b',\xc4\xf4' in raw:
                raw = raw.replace(b',\xc4\xf4', b'\x92'); st['apostrophes'] = st.get('apostrophes', 0) + 1   # cp1252 right quote
            try: rec = raw.decode('utf-8')
            except UnicodeDecodeError: rec = raw.decode('cp1252', errors='replace'); st['cp1252'] += 1
            rec = re.sub(r'[\r\n]+', ' ', rec)      # a lone CR or LF inside a field
            row = next(csv.reader([rec]), [])
            if len(row) != w:
                row = regroup(rec, w)
                if row is None:
                    st['failed'] += 1; print('FAILED', os.path.basename(f), rec[:300]); continue
                st['regrouped'] += 1; print('REGROUPED', os.path.basename(f), row)
            row = [FORMULA.sub(r'\1', v) for v in row]
            out.writerow(row + [year]); st['rows'] += 1
    stats[kind] = st
print(json.dumps(stats, indent=1))
