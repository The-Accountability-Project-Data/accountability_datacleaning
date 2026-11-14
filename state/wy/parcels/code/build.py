"""Build "Wyoming Parcels 2026" from the Wyoming Department of Revenue Property Tax Division assessment data download.

    python build.py <data.mdb> <output.csv>

Source: https://wyo-prop-div.wyo.gov/assessment-data-download, downloaded 2026-11-09 and unzipped to an
Access database (data.mdb). Read with mdbtools (mdb-export). Every table has TAXYEAR 2026 and covers all 23 counties
(JURISDICTION). Tables used, joined on (JURISDICTION, ACCOUNTNO):
* OWNER (one row per owner of an account; 400,023 rows) -- one output row per OWNER row;
* ACCOUNT (one row per account; 373,415 rows);
* PROPERTYADDRESS (one or more site addresses per account, numbered by ORDERNO) -- the address with the lowest
  ORDERNO (1 for all but 66 accounts).
Columns: OWNER's 16 columns in its order; then ACCOUNT's columns except the join keys and TAXYEAR and PARCELNO, which
equal OWNER's (checked); then PROPERTYADDRESS's columns except ACCOUNTNO, TAXYEAR, JURISDICTION and PARCELNO, from the
lowest-ORDERNO address (blank when the account has none); then PROPERTYADDRESS_COUNT (the account's number of site
addresses); then site_state "WY". Values as published, as mdb-export writes them. Not used: ACCOUNTABSTVALUE,
ACCOUNTDOCUMENTS, DOCUMENTS, IMPROVEMENT, IMPROVEMENTBLTAS, IMPROVEMENTDETAIL.
Writes <out>.counties.tsv with each JURISDICTION's owner rows, accounts, blank owner names and redacted owners.
"""
import collections
import csv
import io
import subprocess
import sys

KEYS = ('JURISDICTION', 'ACCOUNTNO')


def table(mdb, name):
    out = subprocess.run(['mdb-export', mdb, name], capture_output=True, check=True).stdout.decode('utf-8')
    r = csv.DictReader(io.StringIO(out, newline=''))
    return r.fieldnames, list(r)


def main(mdb, out):
    of, owners = table(mdb, 'OWNER')
    af, accounts = table(mdb, 'ACCOUNT')
    pf, addresses = table(mdb, 'PROPERTYADDRESS')
    acct = {tuple(r[k] for k in KEYS): r for r in accounts}
    assert len(acct) == len(accounts), 'duplicate account keys'
    first, count = {}, collections.Counter()
    for r in addresses:
        k = tuple(r[k] for k in KEYS)
        count[k] += 1
        if k not in first or int(r['ORDERNO']) < int(first[k]['ORDERNO']):
            first[k] = r
    a_cols = [c for c in af if c not in KEYS + ('TAXYEAR', 'PARCELNO')]
    p_cols = [c for c in pf if c not in KEYS + ('TAXYEAR', 'PARCELNO')]
    header = of + a_cols + p_cols + ['PROPERTYADDRESS_COUNT', 'site_state']
    assert len(set(header)) == len(header), [c for c in header if header.count(c) > 1]
    county = collections.defaultdict(lambda: {'rows': 0, 'accounts': set(), 'blank': 0, 'redacted': 0})
    no_address = 0
    with open(out, 'w', encoding='utf-8', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(header)
        for o in owners:
            k = tuple(o[c] for c in KEYS)
            a = acct[k]
            assert a['PARCELNO'] == o['PARCELNO'] and a['TAXYEAR'] == o['TAXYEAR'], k
            p = first.get(k, {})
            no_address += not p
            w.writerow([o[c] for c in of] + [a[c] for c in a_cols] + [p.get(c, '') for c in p_cols]
                       + [count.get(k, 0), 'WY'])
            c = county[o['JURISDICTION']]
            c['rows'] += 1
            c['accounts'].add(o['ACCOUNTNO'])
            c['blank'] += not o['NAME1'].strip()
            c['redacted'] += o['PRIVATEFLAG'] == '1'
    with open(out + '.counties.tsv', 'w') as tsv:
        tsv.write('jurisdiction\towner_rows\taccounts\tname1_blank\tprivateflag_redacted\n')
        for name, c in sorted(county.items(), key=lambda kv: kv[0].upper()):
            tsv.write(f'{name}\t{c["rows"]}\t{len(c["accounts"])}\t{c["blank"]}\t{c["redacted"]}\n')
    print(f'wrote {out}: {len(owners):,} rows, {len(header)} columns, {len(county)} jurisdictions; '
          f'{len(acct) - len({tuple(o[c] for c in KEYS) for o in owners}):,} accounts without an owner (not written), '
          f'{no_address:,} owner rows whose account has no site address')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
