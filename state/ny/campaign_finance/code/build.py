"""Build New York campaign contributions and expenditures from the NY State Board of Elections bulk
disclosure files, downloaded 2026-11-10 from
https://publicreporting.elections.ny.gov/DownloadCampaignFinanceData/DownloadCampaignFinanceData (the page is behind a
Cloudflare browser check): ALL_REPORTS_StateCandidate, ALL_REPORTS_StateCommittee, ALL_REPORTS_CountyCandidate,
ALL_REPORTS_CountyCommittee (Disclosure Report, all years) and commcand (Filer Data), extracted in
state/ny/campaign_finance/data/raw/ (one folder per zip: ALL_REPORTS_StateCandidate/, ..., commcand/).

    python3 state/ny/campaign_finance/code/build.py [output dir]   (default state/ny/campaign_finance/data/clean/)

Rows: contributions are schedules A-E (the schedules the 2021 build used: monetary contributions from individuals and
partnerships, from corporations, from all other contributors, in-kind contributions, other receipts); expenditures are
schedule F (expenditures/payments). Every row of those schedules, in file order (State Candidate, State Committee, County
Candidate, County Committee). The files hold one version of each report (R_AMEND marks a report that was amended);
3,206 groups of rows are identical in every column and are kept as published.
Columns: the 59 disclosure columns, named as in the BOE file format reference (FileFormatReference.pdf, 56 fields) plus
FILER_PREVIOUS_ID, ELECTION_TYPE and COUNTY_DESC (positions 2, 5, 6; the 2021 build's names) and COLUMN_59 (position 59,
not in the reference); then SOURCE_FILE; then the filer's record from COMMCAND.CSV joined on FILER_ID, prefixed FILER_
(FILER_NAME ... FILER_MUNICIPALITY_DESC) or TREASURER_ (treasurer name and address, the reference's description of
ADDRESS, CITY, STATE, ZIPCODE). Values as published, stripped of surrounding spaces.
Encoding: the source lines are ASCII except about 1,500 that are Windows-1252; each line is decoded as UTF-8, else as
Windows-1252. Output UTF-8.
"""
import collections
import csv
import os
import sys
from pathlib import Path

csv.field_size_limit(10 ** 9)
HERE = Path(__file__).resolve().parent
DATA = HERE.parent / 'data'
RAW = str(DATA / 'raw')
FILES = ['ALL_REPORTS_StateCandidate/STATE_CANDIDATE.csv', 'ALL_REPORTS_StateCommittee/STATE_COMMITTEE.csv',
         'ALL_REPORTS_CountyCandidate/COUNTY_CANDIDATE.csv', 'ALL_REPORTS_CountyCommittee/COUNTY_COMMITTEE.csv']
COLS = ['FILER_ID', 'FILER_PREVIOUS_ID', 'CAND_COMM_NAME', 'ELECTION_YEAR', 'ELECTION_TYPE', 'COUNTY_DESC',
        'FILING_ABBREV', 'FILING_DESC', 'R_AMEND', 'FILING_CAT_DESC', 'FILING_SCHED_ABBREV', 'FILING_SCHED_DESC',
        'LOAN_LIB_NUMBER', 'TRANS_NUMBER', 'TRANS_MAPPING', 'SCHED_DATE', 'ORG_DATE', 'CNTRBR_TYPE_DESC',
        'CNTRBN_TYPE_DESC', 'TRANSFER_TYPE_DESC', 'RECEIPT_TYPE_DESC', 'RECEIPT_CODE_DESC', 'PURPOSE_CODE_DESC',
        'R_SUBCONTRACTOR', 'FLNG_ENT_NAME', 'FLNG_ENT_FIRST_NAME', 'FLNG_ENT_MIDDLE_NAME', 'FLNG_ENT_LAST_NAME',
        'FLNG_ENT_ADD1', 'FLNG_ENT_CITY', 'FLNG_ENT_STATE', 'FLNG_ENT_ZIP', 'FLNG_ENT_COUNTRY', 'PAYMENT_TYPE_DESC',
        'PAY_NUMBER', 'OWED_AMT', 'ORG_AMT', 'LOAN_OTHER_DESC', 'TRANS_EXPLNTN', 'R_ITEMIZED', 'R_LIABILITY',
        'ELECTION_YEAR_R', 'OFFICE_DESC', 'DISTRICT', 'DIST_OFF_CAND_BAL_PROP', 'R_CLAIM', 'R_IN_DISTRICT', 'R_MINOR',
        'R_VENDOR', 'R_LOBBYIST', 'R_SUPPORT_OPPOSE', 'R_CONTRBUTIONS', 'EMPLOYER', 'EMP_OCCUPATION', 'EMP_ADDR_ADDR1',
        'EMP_ADDR_CITY', 'EMP_ADDR_STATE', 'EMP_ADDR_ZIP', 'COLUMN_59']
FILER_COLS = ['FILER_NAME', 'FILER_COMPLIANCE_TYPE_DESC', 'FILER_TYPE_DESC', 'FILER_STATUS',
              'FILER_COMMITTEE_TYPE_DESC', 'FILER_OFFICE_DESC', 'FILER_DISTRICT', 'FILER_COUNTY_DESC',
              'FILER_MUNICIPALITY_DESC', 'TREASURER_FIRST_NAME', 'TREASURER_MIDDLE_NAME', 'TREASURER_LAST_NAME',
              'TREASURER_ADDRESS', 'TREASURER_CITY', 'TREASURER_STATE', 'TREASURER_ZIPCODE']
SCHED = COLS.index('FILING_SCHED_ABBREV')


def lines(path, stats):
    with open(path, 'rb') as fb:
        for b in fb:
            try:
                t = b.decode('utf-8')
            except UnicodeDecodeError:
                t = b.decode('cp1252', errors='replace')
                stats['cp1252 lines'] += 1
            yield t


def main(outdir):
    os.makedirs(outdir, exist_ok=True)
    stats = collections.Counter()
    filers = {}
    for r in csv.reader(lines(os.path.join(RAW, 'commcand/COMMCAND.CSV'), stats)):
        filers[r[0].strip()] = [v.strip() for v in r[1:]]
    blank = [''] * len(FILER_COLS)
    outs = {'contribs': open(os.path.join(outdir, 'ny_contribs_1999-2026.csv'), 'w', encoding='utf-8', newline=''),
            'expends': open(os.path.join(outdir, 'ny_expends_1999-2026.csv'), 'w', encoding='utf-8', newline='')}
    writers = {k: csv.writer(v) for k, v in outs.items()}
    for w in writers.values():
        w.writerow(COLS + ['SOURCE_FILE'] + FILER_COLS)
    years = {'contribs': collections.Counter(), 'expends': collections.Counter()}
    for f in FILES:
        src = os.path.basename(f)
        for r in csv.reader(lines(os.path.join(RAW, f), stats)):
            if len(r) != len(COLS):
                stats['bad column count'] += 1
                continue
            s = r[SCHED].strip()
            kind = 'contribs' if s in ('A', 'B', 'C', 'D', 'E') else 'expends' if s == 'F' else None
            if not kind:
                stats['other schedules'] += 1
                continue
            r = [v.strip() for v in r]
            fil = filers.get(r[0])
            stats['no filer record'] += fil is None
            writers[kind].writerow(r + [src] + (fil or blank))
            stats[kind] += 1
            years[kind][r[15][:4]] += 1
    for v in outs.values():
        v.close()
    print(dict(stats))
    for k in years:
        print(k, dict(sorted(years[k].items())))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else str(DATA / 'clean'))
