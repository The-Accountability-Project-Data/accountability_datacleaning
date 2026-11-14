"""Profile the Pennsylvania yearly exports (state/pa/campaign_finance/data/raw/x, the zips extracted): rows, encoding, contribution/expense years,
reports per filer-year-cycle and whether superseded (amended) reports still have itemized rows.
    python3 state/pa/campaign_finance/code/profile.py
"""
import csv, collections, glob, re
from pathlib import Path
HERE = Path(__file__).resolve().parent
DATA = HERE.parent / 'data'
X = DATA / 'raw' / 'x'
csv.field_size_limit(10**9)
def lines(p, enc):
    for b in open(p, 'rb'):
        try: t = b.decode('utf-8'); enc['non-ascii utf-8' if any(x > 127 for x in b) else 'ascii'] += 1
        except UnicodeDecodeError: t = b.decode('cp1252', errors='replace'); enc['cp1252'] += 1
        yield t
enc = collections.Counter()
reports = {}  # CampaignfinanceID -> (FILERID, EYEAR, CYCLE, AMMEND, SubmittedDate)
for p in sorted(glob.glob(str(X / 'filer_*.txt'))):
    r = csv.DictReader(lines(p, enc))
    if 'FILERID' not in (r.fieldnames or []):
        print('skipping (old layout, no header):', p); continue
    for x in r:
        reports[x['CampaignfinanceID']] = (x['FILERID'].strip(), x['EYEAR'], x['CYCLE'], x['AMMEND'], x['SubmittedDate'])
groups = collections.defaultdict(list)
for cid, (f, y, c, a, d) in reports.items(): groups[(f, y, c)].append(cid)
print('reports', len(reports), 'filer-year-cycles', len(groups), 'with >1 report', sum(1 for v in groups.values() if len(v) > 1))
print('AMMEND', collections.Counter(v[3] for v in reports.values()))
latest = set()
for k, v in groups.items():
    latest.add(max(v, key=lambda c: (reports[c][4], int(c))))
for kind, idcol, dcols, ncols in (('contrib', 'CampaignFinanceID', ['CONTDATE1'], ['CONTRIBUTOR']), ('expense', 'CampaignFinanceID', ['EXPDATE'], ['EXPNAME'])):
    n = 0; nolink = 0; superseded = 0; yr = collections.Counter(); badcols = 0; fill = collections.Counter(); keys = None
    for p in sorted(glob.glob(str(X / f'{kind}_*.txt'))):
        rd = csv.reader(lines(p, enc)); head = next(rd)
        if head[0] != 'CampaignFinanceID':
            print('skipping (old layout, no header):', p); continue
        keys = head; ix = {k: i for i, k in enumerate(head)}
        for r in rd:
            if len(r) != len(head): badcols += 1; continue
            n += 1; cid = r[0]
            if cid not in reports: nolink += 1
            elif cid not in latest: superseded += 1
            yr[r[ix[dcols[0]]][:4]] += 1
            for k in head:
                if r[ix[k]].strip() and r[ix[k]].strip() not in ('0', '0.00'): fill[k] += 1
    print(f'== {kind}: rows {n:,} bad column count {badcols} not linked to a report {nolink:,} in superseded reports {superseded:,}')
    print('   years', {k: v for k, v in sorted(yr.items()) if v > n * 0.001})
    print('   filled', {k: round(fill[k] / n, 3) for k in keys})
print('encodings', dict(enc))
