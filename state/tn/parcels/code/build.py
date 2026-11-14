"""Build "Tennessee Parcels" from the Tennessee Comptroller of the Treasury, Division of Property Assessments, county
parcel files (86 counties; the 9 counties the Comptroller does not maintain are not in them).

    python state/tn/parcels/code/build.py [output.csv]   (default data/clean/tn_parcels_2026.csv)

Input: data/x/<County>/ASSESSMENT_DATA_##.dbf and Parcels_##.shp, extracted from the county zips by
profile.py (zips listed in code/sources.json, downloaded 2026-11-10 through the Comptroller's request form).
One row per assessment record of the current tax year (TAXYR "C"), plus the future-tax-year record (TAXYR "F") of any
parcel ID with no current-year record (one record per parcel, from the current year where there is one). A parcel
ID is PARCELID without its trailing tax year; one map parcel (GISLINK) can carry several parcel IDs (special interests,
SI), each its own row. Columns: COUNTY (the county file's name), then
the assessment table's fields in its order and with its names, as published (Tipton's extra STNUM and STNAME at the end of
the source fields, blank elsewhere): blanks for missing values, whole numbers without a decimal point, other numbers to 15
significant digits, dates as YYYY-MM-DD. Then site_state (TN on every row), LATITUDE and LONGITUDE: the centroid of the
parcel's polygons in Parcels_## with the same GISLINK (area-weighted over all of them), computed in CONUS Albers
(EPSG:5070) and converted to WGS 84, 6 decimal places; blank when no polygon has the GISLINK. Counties in file order of
sources.json. Writes <out>.counties.tsv with per-county counts.
"""
import collections
import csv
import json
import math
import os
import sys
from pathlib import Path

import numpy as np
import pyogrio
import pyogrio.raw as raw
import shapely
from pyproj import Transformer

HERE = Path(__file__).resolve().parent
DATA = HERE.parent / 'data'

TO_LL = Transformer.from_crs('EPSG:5070', 'EPSG:4326', always_xy=True)


def value(v):
    if v is None:
        return ''
    if isinstance(v, np.datetime64):
        return '' if np.isnat(v) else str(v.astype('datetime64[D]'))
    if isinstance(v, float):
        if math.isnan(v):
            return ''
        return str(int(v)) if v.is_integer() else f'{v:.15g}'
    if hasattr(v, 'item'):
        return value(v.item())
    return str(v).strip()


def find(d, prefix, ext):
    return [os.path.join(d, f) for f in os.listdir(d) if f.upper().startswith(prefix) and f.lower().endswith(ext)][0]


def centroids(shp):
    info = pyogrio.read_info(shp)
    to_alb = Transformer.from_crs(info['crs'], 'EPSG:5070', always_xy=True)
    meta, _, geom, data = raw.read(shp, columns=['GISLINK'])
    shapes = shapely.from_wkb(geom)
    shapes = shapely.transform(shapes, lambda xy: np.column_stack(to_alb.transform(xy[:, 0], xy[:, 1])))
    area = shapely.area(shapes)
    c = shapely.centroid(shapes)
    x, y = shapely.get_x(c), shapely.get_y(c)
    acc = collections.defaultdict(lambda: [0.0, 0.0, 0.0])
    for k, a, cx, cy in zip(data[0], area, x, y):
        if k is None or np.isnan(cx) or np.isnan(cy):
            continue
        w = a if a > 0 else 1e-9
        s = acc[str(k).strip()]
        s[0] += w; s[1] += w * cx; s[2] += w * cy
    out = {}
    for k, (w, sx, sy) in acc.items():
        lon, lat = TO_LL.transform(sx / w, sy / w)
        out[k] = (f'{lat:.6f}', f'{lon:.6f}')
    return out, info['features']


def main(out):
    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    counties = [c['county'] for c in json.load(open(HERE / 'sources.json'))['counties']]
    base, extra = None, []
    for c in counties:
        m = pyogrio.read_info(find(str(DATA / 'x' / c), 'ASSESSMENT_DATA', '.dbf'))
        f = list(m['fields'])
        base = base or f
        extra += [k for k in f if k not in base and k not in extra]
    fields = base + extra
    stats = []
    with open(out, 'w', encoding='utf-8', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['COUNTY'] + fields + ['site_state', 'LATITUDE', 'LONGITUDE'])
        for c in counties:
            d = str(DATA / 'x' / c)
            meta, _, _, data = raw.read(find(d, 'ASSESSMENT_DATA', '.dbf'), read_geometry=False)
            f = list(meta['fields'])
            recs = [dict(zip(f, (value(col[i]) for col in data))) for i in range(len(data[0]))]
            pid = lambda r: r['PARCELID'].rsplit(' ', 1)[0]
            current = {pid(r) for r in recs if r['TAXYR'] == 'C'}
            seen_f, rows_out = set(), []
            for r in recs:
                if r['TAXYR'] == 'C':
                    rows_out.append(r)
                elif pid(r) not in current and pid(r) not in seen_f:
                    seen_f.add(pid(r)); rows_out.append(r)
            dup = len([r for r in rows_out if r['TAXYR'] == 'C']) - len({pid(r) for r in rows_out if r['TAXYR'] == 'C'})
            cent, polys = centroids(find(d, 'PARCELS_', '.shp'))
            n = nopoint = fut = 0
            for r in rows_out:
                ll = cent.get(r['GISLINK'], ('', ''))
                nopoint += not ll[0]
                fut += r['TAXYR'] != 'C'
                w.writerow([c] + [r.get(x, '') for x in fields] + ['TN', ll[0], ll[1]])
                n += 1
            s = {'county': c, 'assessment_records': len(recs), 'rows': n, 'future_only': fut, 'duplicate_current': dup,
                 'no_point': nopoint, 'polygons': polys, 'polygon_links_without_record': len(set(cent) - {r['GISLINK'] for r in rows_out}),
                 'tax_years': ' '.join(sorted({r['TAXYR_NUM'] for r in rows_out}))}
            stats.append(s)
            print(c, n, s['tax_years'], 'no point', nopoint, flush=True)
    keys = list(stats[0])
    with open(out + '.counties.tsv', 'w') as fh:
        fh.write('\t'.join(keys) + '\n')
        for s in stats:
            fh.write('\t'.join(str(s[k]) for k in keys) + '\n')
    tot = {k: sum(s[k] for s in stats) for k in keys if isinstance(stats[0][k], int)}
    print(f'wrote {out}: {tot["rows"]:,} rows, {len(fields) + 4} columns; {tot}')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else str(DATA / 'clean' / 'tn_parcels_2026.csv'))
