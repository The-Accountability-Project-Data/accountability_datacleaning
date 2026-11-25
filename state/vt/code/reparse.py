"""
Vermont Campaign Finance System -> one parsed CSV per kind (November 2026).
  python3 -I state/vt/code/reparse.py <raw dir> <search dir> <out dir>
1. Bulk "Download Data" files vt_<receipts|expenditures>_<filing year>.csv, filing years 2014-2025 (26 / 28 columns).
   Every line ends with CRLF, also inside fields: a record starts at a line that begins with a numeric Filing Entity
   Id, three more fields, a numeric Transaction Id (START); other lines continue the record before it (joined with a
   space). A record a CSV reader still does not split into the header's fields is regrouped from its comma-separated
   pieces (a group of pieces only where it starts and ends with a quote) or, failing that, listed and left out.
2. Filing year 2026 is not on the Download Data page yet. Its records come from the public search's JSON,
   put in the bulk columns:
   Filing Entity Id = entityId/entityID, Filing Entity Name = filerName, Registration Type = filerTypeDescription,
   Transaction Id/Type/Subtype, contributor or payee type = transactionSource / payeeType, last name = lastName or,
   when empty, sourceName (organizations), first name = firstName and middleName, address fields, date, amount,
   Election Type = electionTypeDescription, Election Year, Timed Report Name = timedReport, Report Name; expenditures:
   Purpose = expenditurePurpose, Transaction Comments = description. Columns the search does not give are empty
   (Committee Name, Goods Donated/ Service Donated, Other Purpose Comments, Amended, the two filed dates).
   For "Under Threshold - Name Withheld" contributions the search also returns names and addresses that the state
   withholds everywhere else; those are not used (the name is kept as withheld, the address fields left empty).
   Expenditures: the search ignores the filing year, so records whose Transaction Id is in the bulk files are skipped.
Output: header names in snake case, plus filing_year (bulk: from the file name; search: 2026) and source
(bulk | search). Values as published.
"""
import csv, glob, json, os, re, sys
from functools import lru_cache
RAW, SEARCH, OUT = sys.argv[1:4]
Q = r'(?:"(?:[^"]|"(?!,))*"|[^,]*)'   # a quoted field ends at a quote followed by a comma; names hold "NICKNAMES",
                                      # quoted or not
START = re.compile(r'^\d+,' + Q + ',' + Q + ',' + Q + r',\d+,')
WITHHELD = 'Under Threshold - Name Withheld'

def snake(h):
    return re.sub(r'_+', '_', re.sub(r'[^a-z0-9]+', '_', h.strip().lower())).strip('_')

def regroup(rec, w):
    t = rec.split(','); n = len(t)
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

def s(v):
    return '' if v is None else str(v)

def money(v):
    return '' if v is None else '${:,.2f}'.format(v)

stats = {}
for kind, skind in (('receipts', 'contributions'), ('expenditures', 'expenditures')):
    st = {'bulk_files': 0, 'bulk_rows': 0, 'joined_lines': 0, 'regrouped': 0, 'failed': 0, 'search_rows': 0,
          'search_in_bulk_skipped': 0, 'search_withheld_blanked': 0}
    header, w, bulk_ids = None, None, set()
    out = csv.writer(open(os.path.join(OUT, 'vt_%s.csv' % kind), 'w', encoding='utf-8', newline=''))
    for f in sorted(glob.glob(os.path.join(RAW, 'vt_%s_*.csv' % kind))):
        year = re.search(r'_(\d{4})\.csv$', f).group(1)
        lines = open(f, 'rb').read().decode('utf-8').split('\r\n')
        if lines and lines[-1] == '': lines.pop()
        h = next(csv.reader([lines[0]]))
        if header is None:
            header, w = h, len(h); out.writerow([snake(x) for x in header] + ['filing_year', 'source'])
        assert h == header, (f, h)
        st['bulk_files'] += 1
        recs = []
        for ln in lines[1:]:
            if recs and not START.match(ln):
                recs[-1] += ' ' + ln; st['joined_lines'] += 1
            else:
                recs.append(ln)
        for rec in recs:
            rec = re.sub(r'[\r\n]+', ' ', rec)      # a lone CR or LF inside a field
            row = next(csv.reader([rec]), [])
            if len(row) != w:
                row = regroup(rec, w)
                if row is None:
                    st['failed'] += 1; print('FAILED', os.path.basename(f), rec); continue
                st['regrouped'] += 1; print('REGROUPED', os.path.basename(f), row)
            bulk_ids.add(row[4])
            out.writerow(row + [year, 'bulk']); st['bulk_rows'] += 1
    col = {c: i for i, c in enumerate(header)}
    seen = set()
    for f in sorted(glob.glob(os.path.join(SEARCH, 'vt_win_%s_*_p*.json' % skind))):
        for it in json.load(open(f))['data']['items']:
            tid = s(it['transactionID'])
            if tid in seen: continue
            seen.add(tid)
            if tid in bulk_ids:
                st['search_in_bulk_skipped'] += 1; continue
            row = [''] * w
            def put(name, v): row[col[name]] = s(v)
            put('Filing Entity Id', it.get('entityId', it.get('entityID')))
            put('Filing Entity Name', it['filerName']); put('Registration Type', it['filerTypeDescription'])
            put('Transaction Id', tid); put('Transaction Type', it['transactionTypeDescription'])
            put('Transaction Subtype', it['transactionSubTypeDescription'])
            put('Transaction Date', it['transactionDate']); put('Transaction Amount', money(it['transactionAmount']))
            put('Election Type', it.get('electionTypeDescription')); put('Election Year', it.get('electionYear'))
            put('Timed Report Name', it.get('timedReport')); put('Report Name', it.get('reportName'))
            last = s(it.get('lastName')).strip(); first = ' '.join(x for x in (s(it.get('firstName')).strip(), s(it.get('middleName')).strip()) if x)
            if kind == 'receipts':
                withheld = s(it.get('sourceName')).strip() == WITHHELD
                put('Contributor Type', it.get('transactionSource'))
                if withheld:
                    put('Contributor Last Name', WITHHELD); st['search_withheld_blanked'] += 1
                else:
                    put('Contributor Last Name', last or it.get('sourceName')); put('Contributor First Name', first if last else '')
                    put('Contributor Address Line 1', it.get('addressLine1')); put('Contributor Address Line 2', it.get('addressLine2'))
                    put('Contributor Address City', it.get('city')); put('Contributor Address State', it.get('stateCode'))
                    put('Contributor Address Zip Code', it.get('zipCode'))
            else:
                put('Payee Type', it.get('payeeType')); put('Purpose', it.get('expenditurePurpose'))
                put('Payee Last Name', last or it.get('sourceName')); put('Payee First Name', first if last else '')
                put('Payee Address Line 1', it.get('sourceAddressLine1')); put('Payee Address Line 2', it.get('sourceAddressLine2'))
                put('Payee Address City', it.get('sourceCity')); put('Payee Address State', it.get('sourceState'))
                put('Payee Address Zip Code', it.get('sourceZipCode')); put('Transaction Comments', it.get('description'))
            row = [re.sub(r'[\r\n]+', ' ', v) for v in row]
            out.writerow(row + ['2026', 'search']); st['search_rows'] += 1
    stats[kind] = st
print(json.dumps(stats, indent=1))
