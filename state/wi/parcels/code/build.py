"""Build "Wisconsin Parcels 2025" from the Wisconsin Statewide Parcel Map Initiative V12 (2026) file geodatabase.

    python build.py <V12.0.0_Wisconsin_Parcels_2026_10.3_Uncompressed.gdb> <output.csv>

Source: https://web.s3.wisc.edu/parcels/v12_parcels/V12.0.0_Wisconsin_Parcels_2026_10.3_Uncompressed.zip (Wisconsin
State Cartographer's Office and Department of Administration, Statewide Parcel Map Initiative, V12; the compressed
version of the same file uses Esri's compressed format, which GDAL does not read). One feature class,
V1200_WisconsinParcels_2026 (parcel polygons).
Columns: the layer's 45 attribute fields, in its order and with its names, as published. LATITUDE and LONGITUDE are
attribute fields of the layer (the parcel's point, in WGS 84); the polygons are not read. Every value is written as
published: blanks for missing values, whole numbers without a decimal point, other numbers to 15 significant digits.
Then OWNER_ADDRESSCITY, OWNER_STATE, OWNER_ZIP, split from PSTLADRESS (the owner's mailing address in one field, e.g.
"2020 CHAMBERLAIN AVE , MADISON, WI 53726"): when the value ends in a US state or territory code and a ZIP (5 digits or
ZIP+4, with or without the hyphen), optionally separated by commas ("EAU CLAIRE, WI, 54702"), the code is OWNER_STATE,
the ZIP is OWNER_ZIP and the text before them, without trailing commas and spaces, is OWNER_ADDRESSCITY. Otherwise
(foreign addresses, "NOT AVAILABLE", blanks) the whole value is OWNER_ADDRESSCITY and the other two are blank.
Writes <out>.counties.tsv with each county's rows, tax roll years, and rows whose OWNERNME1 is blank or "NOT AVAILABLE".
"""
import collections
import csv
import math
import re
import sys

import pyogrio
import pyogrio.raw as raw

LAYER = 'V1200_WisconsinParcels_2026'
CHUNK = 500_000
STATES = ('AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK '
          'OR PA RI SC SD TN TX UT VT VA WA WV WI WY PR VI GU AS MP AA AE AP').split()
MAIL = re.compile(r'^(.*?)[\s,]+(' + '|'.join(STATES) + r')[\s,]+(\d{5}(?:-?\d{4})?)$')


def split_mail(v):
    m = MAIL.match(v.strip())
    if not m:
        return [v.strip(), '', '']
    return [m.group(1).rstrip(' ,'), m.group(2), m.group(3)]


def value(v):
    if v is None:
        return ''
    if isinstance(v, float):
        if math.isnan(v):
            return ''
        return str(int(v)) if v.is_integer() else f'{v:.15g}'
    if hasattr(v, 'item'):          # numpy scalar
        return value(v.item())
    return str(v)


def main(gdb, out):
    info = pyogrio.read_info(gdb, layer=LAYER)
    fields, total = list(info['fields']), info['features']
    print(f'layer {LAYER}: {total:,} features, {len(fields)} fields')
    ci, yi, oi = fields.index('CONAME'), fields.index('TAXROLLYEAR'), fields.index('OWNERNME1')
    pi = fields.index('PSTLADRESS')
    split_counts = collections.Counter()
    county = collections.defaultdict(lambda: {'rows': 0, 'years': collections.Counter(), 'blank': 0, 'na': 0})
    rows = 0
    with open(out, 'w', encoding='utf-8', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(fields + ['OWNER_ADDRESSCITY', 'OWNER_STATE', 'OWNER_ZIP'])
        for skip in range(0, total, CHUNK):
            meta, _, _, data = raw.read(gdb, layer=LAYER, read_geometry=False, skip_features=skip, max_features=CHUNK)
            assert list(meta['fields']) == fields
            for i in range(len(data[0])):
                rec = [value(col[i]) for col in data]
                mail = split_mail(rec[pi])
                split_counts['split' if mail[1] else ('blank' if not rec[pi].strip() else 'not split')] += 1
                w.writerow(rec + mail)
                rows += 1
                c = county[rec[ci]]
                c['rows'] += 1
                c['years'][rec[yi]] += 1
                if not rec[oi].strip():
                    c['blank'] += 1
                elif rec[oi] == 'NOT AVAILABLE':
                    c['na'] += 1
            print(f'{rows:,} of {total:,} rows', flush=True)
    with open(out + '.counties.tsv', 'w') as tsv:
        tsv.write('coname\trows\ttaxrollyears\towner_blank\towner_not_available\n')
        for name, c in sorted(county.items()):
            years = ', '.join(f'{y or "blank"} {n}' for y, n in sorted(c['years'].items()))
            tsv.write(f'{name}\t{c["rows"]}\t{years}\t{c["blank"]}\t{c["na"]}\n')
    print(f'wrote {out}: {rows:,} rows, {len(fields) + 3} columns, {len(county)} CONAME values; PSTLADRESS {dict(split_counts)}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
