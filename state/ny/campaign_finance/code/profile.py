"""Profile the four NY BOE ALL_REPORTS disclosure files (lines decoded as UTF-8, else Windows-1252) (state/ny/campaign_finance/data/raw, downloaded
2026-11-10): rows, column counts, schedule counts, election years for contributions (A-E) and expenditures (F),
R_AMEND, filled share of key fields, column 59. Writes A-F transaction numbers to state/ny/campaign_finance/data/trans.txt for
a duplicate check (sort | uniq -d).
    python3 state/ny/campaign_finance/code/profile.py
"""
import csv, collections, glob
from pathlib import Path
HERE = Path(__file__).resolve().parent
DATA = HERE.parent / 'data'
csv.field_size_limit(10**9)
GUIDE = ['FILER_ID','FILER_PREVIOUS_ID','CAND_COMM_NAME','ELECTION_YEAR','ELECTION_TYPE','COUNTY_DESC','FILING_ABBREV',
 'FILING_DESC','R_AMEND','FILING_CAT_DESC','FILING_SCHED_ABBREV','FILING_SCHED_DESC','LOAN_LIB_NUMBER','TRANS_NUMBER',
 'TRANS_MAPPING','SCHED_DATE','ORG_DATE','CNTRBR_TYPE_DESC','CNTRBN_TYPE_DESC','TRANSFER_TYPE_DESC','RECEIPT_TYPE_DESC',
 'RECEIPT_CODE_DESC','PURPOSE_CODE_DESC','R_SUBCONTRACTOR','FLNG_ENT_NAME','FLNG_ENT_FIRST_NAME','FLNG_ENT_MIDDLE_NAME',
 'FLNG_ENT_LAST_NAME','FLNG_ENT_ADD1','FLNG_ENT_CITY','FLNG_ENT_STATE','FLNG_ENT_ZIP','FLNG_ENT_COUNTRY',
 'PAYMENT_TYPE_DESC','PAY_NUMBER','OWED_AMT','ORG_AMT','LOAN_OTHER_DESC','TRANS_EXPLNTN','R_ITEMIZED','R_LIABILITY',
 'ELECTION_YEAR_R','OFFICE_DESC','DISTRICT','DIST_OFF_CAND_BAL_PROP','R_CLAIM','R_IN_DISTRICT','R_MINOR','R_VENDOR',
 'R_LOBBYIST','R_SUPPORT_OPPOSE','R_CONTRBUTIONS','EMPLOYER','EMP_OCCUPATION','EMP_ADDR_ADDR1','EMP_ADDR_CITY',
 'EMP_ADDR_STATE','EMP_ADDR_ZIP','COL59']
ix = {k: i for i, k in enumerate(GUIDE)}
KEY = ['FLNG_ENT_NAME','FLNG_ENT_LAST_NAME','FLNG_ENT_ADD1','FLNG_ENT_CITY','FLNG_ENT_STATE','FLNG_ENT_ZIP','SCHED_DATE',
       'ORG_AMT','EMPLOYER','EMP_OCCUPATION','COL59']
out = open(DATA / 'trans.txt', 'w')
for f in sorted(glob.glob(str(DATA / 'raw' / 'ALL_REPORTS_*' / '*.csv'))):
    ncol = collections.Counter(); sched = collections.Counter(); yr = {'A-E': collections.Counter(), 'F': collections.Counter()}
    amend = collections.Counter(); fill = {'A-E': collections.Counter(), 'F': collections.Counter()}; n = 0; c59 = collections.Counter()
    bad = 0
    enc = collections.Counter()
    def lines(path):
        with open(path, 'rb') as fb:
            for b in fb:
                try:
                    t = b.decode('utf-8'); enc['utf-8 (non-ascii)' if any(x > 127 for x in b) else 'ascii'] += 1
                except UnicodeDecodeError:
                    t = b.decode('cp1252', errors='replace'); enc['cp1252'] += 1
                yield t
    if True:
        try:
            for r in csv.reader(lines(f)):
                n += 1; ncol[len(r)] += 1
                if len(r) != 59: continue
                s = r[ix['FILING_SCHED_ABBREV']]; sched[s] += 1
                g = 'A-E' if s in 'ABCDE' and s else ('F' if s == 'F' else None)
                if r[58]: c59[r[58][:20]] += 1
                if not g: continue
                yr[g][r[ix['SCHED_DATE']][:4]] += 1; amend[(g, r[ix['R_AMEND']])] += 1
                for k in KEY:
                    if r[ix[k]].strip(): fill[g][k] += 1
                out.write(r[ix['TRANS_NUMBER']] + '\n')
        except UnicodeDecodeError as e:
            bad = str(e)[:120]
    print('==', f.split('/')[-1], 'rows', n, 'columns', dict(ncol), 'utf8 error' if bad else '', bad)
    print('  schedules', dict(sorted(sched.items())))
    for g in ('A-E', 'F'):
        t = sum(yr[g].values())
        print(f'  {g}: {t:,} rows; years', {k: v for k, v in sorted(yr[g].items()) if v > t * 0.002})
        print('    filled', {k: round(fill[g][k] / t, 3) for k in KEY} if t else '')
    print('  R_AMEND', dict(amend), 'col59', c59.most_common(5)); print('  line encodings', dict(enc))
