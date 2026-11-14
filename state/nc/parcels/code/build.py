"""Build "North Carolina Parcels 2026" from NC OneMap's statewide parcels file geodatabase (points layer).

    python build.py <path>/<name>.gdb <output dir>/nc_parcels_2026.csv

Source: https://dit-cgia-gis-data.s3.amazonaws.com/NCOM-data/parcels/nc-parcels-gdb-most-recent.zip (NC OneMap,
"North Carolina Parcels", all 100 counties and the Eastern Band of Cherokee Indians), which has a polygon and a point
feature class with the same attributes. This reads the point feature class (one point per parcel, at or near its
center).
Columns: the 2019 file's 68 columns (csv/nc_parcels.csv, 2019), which are the layer's attribute fields, in that order and
in upper case (OBJECTID is the layer's feature id); then LATITUDE and LONGITUDE, the point in WGS 84 (EPSG:4326) to 6 decimal places. Every value is
written as published: blanks for missing values, whole numbers without a decimal point, other numbers to 15
significant digits, dates as the geodatabase stores them. Stops if a 2019 column is missing from the layer or the
layer has a field not in the 2019 columns.
In OWNNAME and OWNNAME2, which list several owners separated by semicolons ("HUGENSCHMIDT, MARY B;RUCKER, BRADLEY K"),
each semicolon and the spaces around it are written as " ; " ("HUGENSCHMIDT, MARY B ; RUCKER, BRADLEY K"), so that
each name is its own word for search. No other values are changed.
Writes <out>.counties.tsv with each county's rows, its range of TRANSFDATE (the date the county's data was
transferred to NC OneMap) and its SOURCEAGNT.
"""
import collections
import csv
import math
import re
import struct
import sys

import pyogrio
import pyogrio.raw as raw
from pyproj import Transformer

CHUNK = 500_000
NAME_FIELDS = ('OWNNAME', 'OWNNAME2')
SEMI = re.compile(r'\s*;\s*')
COLUMNS_2019 = ('OBJECTID,PARNO,ALTPARNO,OWNNAME,IMPROVVAL,LANDVAL,PARVAL,MAILADD,MUNIT,MCITY,MSTATE,MZIP,SITEADD,'
                'SUNIT,SCITY,GISACRES,STRUCT,MULTISTRUC,SALEDATE,SALEDATETX,LEGDECFULL,PARUSECODE,PARUSEDESC,'
                'PARUSECD2,PARUSEDSC2,PARVALTYPE,OWNTYPE,RECAREANO,RECAREATX,REVISEDATE,SOURCEREF,SOURCEDATE,'
                'SOURCEDATX,SUBDIVISIO,NPARNO,CNTYNAME,CNTYFIPS,STFIPS,STCNTYFIPS,GNISID,SOURCEAGNT,TRANSFDATE,'
                'MADDPREF,MADDRNO,MADDSTNAME,MADDSTR,MADDSTSUF,MADDSTTYP,OWNFRST,OWNLAST,REVDATETX,REVISEYEAR,'
                'SADDNO,SADDPREF,SADDSTNAME,SADDSTR,SADDSTSUF,SADDSTTYP,SSTATE,STNAME,SUBOWNTYPE,SUBSURFOWN,SZIP,'
                'STRUCTNO,STRUCTYEAR,OWNNAME2,MAPREF,PRESENTVAL').split(',')


def value(v):
    if v is None:
        return ''
    if isinstance(v, float):
        if math.isnan(v):
            return ''
        return str(int(v)) if v.is_integer() else f'{v:.15g}'
    if hasattr(v, 'item'):          # numpy scalar
        x = v.item()
        if x is None or (hasattr(v, 'dtype') and v.dtype.kind == 'M' and str(v) == 'NaT'):
            return ''
        return str(v) if v.dtype.kind == 'M' else value(x)
    return str(v)


def point_xy(wkb):
    """x, y of a WKB point (ISO or extended, either byte order); None for an empty or missing point."""
    if wkb is None or len(wkb) < 21:
        return None
    order = '<' if wkb[0] == 1 else '>'
    gtype = struct.unpack(order + 'I', wkb[1:5])[0]
    off = 5 + (4 if gtype & 0x20000000 else 0)       # EWKB SRID
    x, y = struct.unpack(order + 'dd', wkb[off:off + 16])
    return None if math.isnan(x) or math.isnan(y) else (x, y)


def main(gdb, out):
    layers = [(name, gtype) for name, gtype in pyogrio.list_layers(gdb)]
    print('layers:', layers)
    points = [name for name, gtype in layers if gtype and 'Point' in gtype]
    if len(points) != 1:
        sys.exit(f'expected one point layer, found {points}')
    layer = points[0]
    info = pyogrio.read_info(gdb, layer=layer)
    fields, total, crs = list(info['fields']), info['features'], info['crs']
    by_upper = {f.upper(): f for f in fields}
    missing = [c for c in COLUMNS_2019 if c not in by_upper and c != 'OBJECTID']   # OBJECTID is the feature id
    extra = [f for f in fields if f.upper() not in COLUMNS_2019]
    print(f'layer {layer}: {total:,} features, crs {crs}, {len(fields)} fields')
    if missing or extra:
        sys.exit(f'2019 columns missing: {missing}; fields not in the 2019 columns: {extra}')
    to_wgs84 = Transformer.from_crs(crs, 'EPSG:4326', always_xy=True)
    header = COLUMNS_2019 + ['LATITUDE', 'LONGITUDE']
    name_idx = [COLUMNS_2019.index(f) for f in NAME_FIELDS]
    spaced = collections.Counter()
    rows = no_point = 0
    county = collections.defaultdict(lambda: {'rows': 0, 'transf': set(), 'agent': set()})
    with open(out, 'w', encoding='utf-8', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(header)
        for skip in range(0, total, CHUNK):
            meta, fids, geom, data = raw.read(gdb, layer=layer, skip_features=skip, max_features=CHUNK,
                                              return_fids=True)
            cols = {name.upper(): arr for name, arr in zip(meta['fields'], data)}
            cols['OBJECTID'] = fids
            xy = [point_xy(g) for g in geom]
            ok = [p for p in xy if p]
            lon, lat = to_wgs84.transform([p[0] for p in ok], [p[1] for p in ok])
            ll = iter(zip(lat, lon))
            for i in range(len(geom)):
                rec = [value(cols[c][i]) for c in COLUMNS_2019]
                for j in name_idx:
                    if ';' in rec[j]:
                        new = SEMI.sub(' ; ', rec[j])
                        rec[j] = new[:-1] if new.endswith(' ; ') and not rec[j].endswith(' ') else new
                        spaced[COLUMNS_2019[j]] += 1
                if xy[i]:
                    la, lo = next(ll)
                    rec += [f'{la:.6f}', f'{lo:.6f}']
                else:
                    rec += ['', '']
                    no_point += 1
                w.writerow(rec)
                rows += 1
                c = county[(rec[COLUMNS_2019.index('CNTYNAME')], rec[COLUMNS_2019.index('CNTYFIPS')])]
                c['rows'] += 1
                c['transf'].add(rec[COLUMNS_2019.index('TRANSFDATE')][:10])
                c['agent'].add(rec[COLUMNS_2019.index('SOURCEAGNT')])
            print(f'{rows:,} of {total:,} rows', flush=True)
    print('semicolons spaced:', dict(spaced), flush=True)
    with open(out + '.counties.tsv', 'w') as tsv:
        tsv.write('cntyname\tcntyfips\trows\ttransfdate_min\ttransfdate_max\tsourceagnt\n')
        for (name, fips), c in sorted(county.items()):
            t = sorted(d for d in c['transf'] if d) or ['']
            a = '; '.join(sorted(x for x in c['agent'] if x))[:80]
            tsv.write(f'{name}\t{fips}\t{c["rows"]}\t{t[0]}\t{t[-1]}\t{a}\n')
    print(f'wrote {out}: {rows:,} rows, {len(header)} columns, {len(county)} counties, {no_point:,} without a point')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
