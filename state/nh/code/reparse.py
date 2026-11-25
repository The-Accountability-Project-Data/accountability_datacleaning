"""
New Hampshire CFS yearly downloads -> one parsed CSV per kind (November 2026).
  python3 -I state/nh/code/reparse.py <raw dir> <out dir>
Input: nh_receipts_<filing year>.csv (22 columns) and nh_expenditures_<filing year>.csv (13 columns) from
https://cfs.sos.nh.gov/public/cf/downloads.
- Records end with CRLF, but a field can hold a line break (LF or CRLF). A record starts at a line that begins with
  a numeric Filing Entity ID, the next fields and a Transaction Type (START); any other line continues the record
  before it and is joined with a space.
- Each record is decoded as UTF-8, or as Windows-1252 when it is not valid UTF-8 (a few records per file).
- A record that a CSV reader does not split into the header's number of fields (a free-text description with
  stray quotes or unquoted commas) is rebuilt: the fields before the description are read one by one, the last
  field follows the last comma, and everything between is the description (outer quotes removed). The
  description is the second-to-last column in both layouts. Failing that (stray quotes in other fields, 8 receipts in
  November 2026), the record is split at every comma and the pieces regrouped into the header's number of fields,
  a group of several pieces only where it starts and ends with a quote (regroup); outer quotes are then removed.
- Output: header names in snake case, plus filing_year (from the file name). Values as published.
"""
import csv, glob, io, json, os, re, sys
RAW, OUT = sys.argv[1], sys.argv[2]
Q = r'(?:"[^"]*"|[^",]*)'
START = {'receipts': re.compile(r'^\d+,' + Q + ',' + Q + ',' + Q + r',[A-Za-z /-]+,'),
         'expenditures': re.compile(r'^\d+,' + Q + ',' + Q + r',[A-Za-z /-]+,')}
FIELD = re.compile(r'"((?:[^"]|"")*)",|([^,"]*),')

def snake(h):
    return re.sub(r'_+', '_', re.sub(r'[^a-z0-9]+', '_', h.strip().lower())).strip('_')

def rebuild(rec, w):
    vals, pos = [], 0
    for _ in range(w - 2):
        m = FIELD.match(rec, pos)
        if not m: return None
        vals.append(m.group(1).replace('""', '"') if m.group(1) is not None else m.group(2)); pos = m.end()
    cut = rec.rfind(',')
    if cut < pos - 1: return None
    desc, last = rec[pos:cut], rec[cut + 1:]
    if len(desc) >= 2 and desc[0] == '"' and desc[-1] == '"': desc = desc[1:-1]
    return vals + [desc, last]

def regroup(rec, w):
    t = rec.split(',')
    n = len(t)
    from functools import lru_cache
    @lru_cache(None)
    def go(i, k):                      # fields for tokens i.. using exactly k fields; fewest quoted single tokens
        if i == n: return (0, ()) if k == 0 else None
        if k == 0: return None
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
    out = []
    for v in r[1]:
        if len(v) >= 2 and v[0] == '"' and v[-1] == '"': v = v[1:-1]
        out.append(v.replace('""', '"'))
    return out

stats = {}
for kind in ('receipts', 'expenditures'):
    files = sorted(glob.glob(os.path.join(RAW, 'nh_%s_*.csv' % kind)))
    header, out, s = None, None, {'files': 0, 'rows': 0, 'cp1252': 0, 'linebreaks': 0, 'rebuilt': 0, 'failed': 0}
    for f in files:
        year = re.search(r'_(\d{4})\.csv$', f).group(1)
        recs = open(f, 'rb').read().split(b'\r\n')
        if recs and recs[-1] == b'': recs.pop()
        h = next(csv.reader([recs[0].decode('utf-8')]))
        joined = []
        for raw in recs[1:]:
            if joined and not START[kind].match(raw.decode('utf-8', errors='replace')):
                joined[-1] += b'\n' + raw
            else:
                joined.append(raw)
        if header is None:
            header = h
            out = csv.writer(open(os.path.join(OUT, 'nh_%s.csv' % kind), 'w', encoding='utf-8', newline=''))
            out.writerow([snake(x) for x in header] + ['filing_year'])
        assert h == header, (f, h)
        w = len(header); s['files'] += 1
        for raw in joined:
            try: rec = raw.decode('utf-8')
            except UnicodeDecodeError: rec = raw.decode('cp1252', errors='replace'); s['cp1252'] += 1
            if '\n' in rec or '\r' in rec:
                rec = re.sub(r'[\r\n]+', ' ', rec); s['linebreaks'] += 1
            row = next(csv.reader([rec]), [])
            if len(row) != w:
                row = rebuild(rec, w)
                if row is None:
                    row = regroup(rec, w)
                    if row is not None:
                        s['regrouped'] = s.get('regrouped', 0) + 1; print('REGROUPED', os.path.basename(f), row)
                if row is None:
                    s['failed'] += 1; print('FAILED', os.path.basename(f), rec); continue
                s['rebuilt'] += 1
            out.writerow(row + [year]); s['rows'] += 1
    stats[kind] = s
print(json.dumps(stats, indent=1))
