"""Per-county counts for the StratMap 2026 land parcels county files (2026-11-09): parcels, OWNER_NAME
populated, mailing street populated (MAIL_LINE1 or MAIL_LINE2), MAIL_CITY populated, SITUS street populated, tax years,
source and acquisition date. Unzips each county's file geodatabase to a temporary folder, reads attributes only.
    python owner_counts.py <folder of county zips> <owner_counts.tsv>
A value counts as populated when it is not blank after trimming and is not just commas/spaces.
"""
import collections
import glob
import os
import re
import shutil
import sys
import tempfile
import zipfile

import pyogrio
import pyogrio.raw as raw

COLS = ['OWNER_NAME', 'MAIL_LINE1', 'MAIL_LINE2', 'MAIL_CITY', 'SITUS_STRE', 'TAX_YEAR', 'SOURCE', 'DATE_ACQ', 'COUNTY']
EMPTY = re.compile(r'^[\s,.]*$')


def filled(v):
    return v is not None and not EMPTY.match(str(v)) and str(v).strip().lower() not in ('nan', 'nat', 'none', 'null')


def main(raw_dir, out):
    rows = []
    for z in sorted(glob.glob(os.path.join(raw_dir, 'stratmap26-landparcels_48???_lp.zip'))):
        fips = re.search(r'_(48\d{3})_lp', z).group(1)
        tmp = tempfile.mkdtemp(dir=os.path.dirname(out))
        try:
            with zipfile.ZipFile(z) as zf:
                zf.extractall(tmp, [n for n in zf.namelist() if '.gdb/' in n])
            gdb = glob.glob(os.path.join(tmp, '**', '*.gdb'), recursive=True)[0]
            layer = pyogrio.list_layers(gdb)[0][0]
            meta, _, _, data = raw.read(gdb, layer=layer, read_geometry=False, columns=COLS)
            c = dict(zip(meta['fields'], data))
            n = len(data[0])
            own = sum(1 for v in c['OWNER_NAME'] if filled(v))
            mail = sum(1 for a, b in zip(c['MAIL_LINE1'], c['MAIL_LINE2']) if filled(a) or filled(b))
            city = sum(1 for v in c['MAIL_CITY'] if filled(v))
            situs = sum(1 for v in c['SITUS_STRE'] if filled(v))
            years = collections.Counter(str(v) if filled(v) else 'blank' for v in c['TAX_YEAR'])
            src = collections.Counter(str(v) for v in c['SOURCE']).most_common(1)[0][0] if n else ''
            acq = collections.Counter(str(v)[:10] for v in c['DATE_ACQ']).most_common(1)[0][0] if n else ''
            name = collections.Counter(str(v) for v in c['COUNTY']).most_common(1)[0][0] if n else ''
            rows.append((fips, name, n, own, mail, city, situs,
                         ', '.join(f'{y} {k}' for y, k in sorted(years.items())), src, acq))
            print(fips, name, n, own, flush=True)
        finally:
            shutil.rmtree(tmp)
    with open(out, 'w') as fh:
        fh.write('fips\tcounty\tparcels\towner_name\tpct_owner\tmail_street\tpct_mail\tmail_city\tsitus_street\t'
                 'tax_years\tsource\tdate_acq\n')
        for fips, name, n, own, mail, city, situs, years, src, acq in rows:
            pct = lambda k: f'{100 * k / n:.1f}' if n else ''
            fh.write(f'{fips}\t{name}\t{n}\t{own}\t{pct(own)}\t{mail}\t{pct(mail)}\t{city}\t{situs}\t{years}\t{src}\t'
                     f'{acq}\n')
    print('wrote', out, len(rows), 'counties')


if __name__ == '__main__':
    main(*sys.argv[1:3])
