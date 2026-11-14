"""Build "New York Parcels 2026" from the NYS Tax Parcel Centroid Points file geodatabase (2025 roll).

    python build.py <path>/NYS_2025_Tax_Parcels_Centroid_Points_2605.gdb <output dir>/ny_parcels_2025.csv

Requires pyogrio.

Follows state/ny/parcels/fix_ny_output.py (2018), with these changes:
* reads the geodatabase layer directly (pyogrio, no geometry) instead of a CSV exported in a GIS program;
* after the 2018 file's 40 columns, in the same order, adds every other field of the layer except the ones the
  owner rows are made from (PRIMARY_OWNER, ADD_OWNER, ADD_MAIL_*).
As in 2018: one row per owner. The first row has PRIMARY_OWNER as OWNER with MAIL_ADDR, PO_BOX, MAIL_CITY,
MAIL_STATE and MAIL_ZIP; when ADD_OWNER is filled, a second row has ADD_OWNER as OWNER with the ADD_MAIL_* fields.
STATE is "NY". Values are written as published: blanks for missing values, whole numbers without a decimal point,
other numbers to 15 significant digits.
"""
import csv
import math
import sys

import pyogrio
import pyogrio.raw as raw

LAYER = 'NYS_Tax_Parcels_Centroid_Points'
CHUNK = 500_000

# the 2018 output columns, in order (fix_ny_output.py)
BASE_FIELDS = ['COUNTY_NAME', 'MUNI_NAME', 'PARCEL_ADDR', 'CITYTOWN_NAME', 'LOC_ST_NBR', 'LOC_STREET', 'LOC_UNIT',
               'LOC_ZIP', 'PROP_CLASS', 'ROLL_SECTION', 'LAND_AV', 'TOTAL_AV', 'FULL_MARKET_VAL', 'YR_BLT', 'FRONT',
               'DEPTH', 'SQ_FT', 'ACRES', 'SCHOOL_NAME', 'BLDG_STYLE_DESC', 'SQFT_LIVING', 'NBR_KITCHENS',
               'NBR_FULL_BATHS', 'NBR_BEDROOMS', 'USED_AS_DESC', 'BOOK', 'PAGE', 'GRID_EAST', 'GRID_NORTH',
               'MUNI_PARCEL_ID', 'ROLL_YR', 'OWNER_TYPE', 'CALC_ACRES']
OWNER_FIELDS = ['OWNER', 'MAIL_ADDR', 'PO_BOX', 'MAIL_CITY', 'MAIL_STATE', 'MAIL_ZIP']
MAIL = ['MAIL_ADDR', 'PO_BOX', 'MAIL_CITY', 'MAIL_STATE', 'MAIL_ZIP']
ADD_MAIL = ['ADD_MAIL_ADDR', 'ADD_MAIL_PO_BOX', 'ADD_MAIL_CITY', 'ADD_MAIL_STATE', 'ADD_MAIL_ZIP']
USED_FOR_OWNERS = {'PRIMARY_OWNER', 'ADD_OWNER', *ADD_MAIL}


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
    fields = list(info['fields'])
    total = info['features']
    missing = [f for f in BASE_FIELDS + MAIL + ['PRIMARY_OWNER', 'ADD_OWNER'] + ADD_MAIL if f not in fields]
    if missing:
        sys.exit(f'fields missing from {LAYER}: {missing}')
    extra = [f for f in fields if f not in BASE_FIELDS + MAIL and f not in USED_FOR_OWNERS]
    header = ['STATE'] + BASE_FIELDS + OWNER_FIELDS + extra
    parcels = rows = second = 0
    with open(out, 'w', encoding='utf-8', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(header)
        for skip in range(0, total, CHUNK):
            meta, _, _, data = raw.read(gdb, layer=LAYER, read_geometry=False, skip_features=skip, max_features=CHUNK)
            cols = {name: arr for name, arr in zip(meta['fields'], data)}
            for i in range(len(data[0])):
                rec = {f: value(cols[f][i]) for f in fields}
                base = ['NY'] + [rec[f] for f in BASE_FIELDS]
                tail = [rec[f] for f in extra]
                w.writerow(base + [rec['PRIMARY_OWNER']] + [rec[f] for f in MAIL] + tail)
                rows += 1
                if rec['ADD_OWNER'].strip():
                    w.writerow(base + [rec['ADD_OWNER']] + [rec[f] for f in ADD_MAIL] + tail)
                    rows += 1
                    second += 1
                parcels += 1
            print(f'{parcels:,} of {total:,} parcels, {rows:,} rows', flush=True)
    print(f'wrote {out}: {rows:,} rows ({parcels:,} parcels, {second:,} second-owner rows), {len(header)} columns')
    print('added columns:', ', '.join(extra))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
