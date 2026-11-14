"""Build "North Dakota Parcels 2026" from the North Dakota GIS Hub State Parcel Program file geodatabase.

    python build.py <path>/NDParcelsFGDB.gdb <output dir>/nd_parcels_2026.csv

Source: NDParcelsFGDB.gdb.zip, ArcGIS item c9e6956684c14fa299ee9e38c90dc003 (NDGISHub; Last-Modified 2026-11-09),
downloaded 2026-11-09. Two layers: the Parcels_TaxRoll table (one row per tax roll record) and the Parcels feature class
(parcel polygons, WGS 84). They join on UniqueGISID, one parcel to many tax roll records.
Columns: the table's 56 fields, in its order and with its names, one row per tax roll record, as published: blanks for
missing values, whole numbers without a decimal point, other numbers to 15 significant digits, DateImported as
YYYY-MM-DDTHH:MM:SS. Then site_state "ND" (the table has no property state). Then LATITUDE and LONGITUDE: the
centroid of the record's parcel, from every Parcels feature with
its UniqueGISID (16,611 parcels are stored as more than one feature; the centroid is the area-weighted mean of the
features' centroids), computed in CONUS Albers (EPSG:5070) and converted to WGS 84, to 6 decimal places. Blank when no
feature has the record's UniqueGISID. The polygons are not written.
Writes <out>.counties.tsv with each county's rows, tax roll years, blank owners and rows without a point.
"""
import collections
import csv
import math
import sys

import numpy as np
import pyogrio.raw as raw
import shapely
from pyproj import Transformer


def value(v):
    if v is None:
        return ''
    if isinstance(v, np.datetime64):
        return '' if np.isnat(v) else str(v.astype('datetime64[s]'))
    if isinstance(v, float):
        if math.isnan(v):
            return ''
        return str(int(v)) if v.is_integer() else f'{v:.15g}'
    if hasattr(v, 'item'):          # numpy scalar
        return value(v.item())
    return str(v)


def points(gdb):
    meta, _, geom, (gid,) = raw.read(gdb, layer='Parcels', columns=['UniqueGISID'])
    to_alb = Transformer.from_crs(meta['crs'], 'EPSG:5070', always_xy=True)
    to_ll = Transformer.from_crs('EPSG:5070', 'EPSG:4326', always_xy=True)
    shapes = shapely.from_wkb(geom)
    shapes = shapely.transform(shapes, lambda xy: np.column_stack(to_alb.transform(xy[:, 0], xy[:, 1])))
    cent, area = shapely.centroid(shapes), shapely.area(shapes)
    x, y = shapely.get_x(cent), shapely.get_y(cent)
    acc = collections.defaultdict(lambda: [0.0, 0.0, 0.0])
    for g, xi, yi, a in zip(gid, x, y, area):
        if not g or math.isnan(xi) or math.isnan(yi):
            continue
        w = a if a > 0 else 1e-9
        s = acc[g]
        s[0] += xi * w
        s[1] += yi * w
        s[2] += w
    keys = list(acc)
    xs = np.array([acc[k][0] / acc[k][2] for k in keys])
    ys = np.array([acc[k][1] / acc[k][2] for k in keys])
    lon, lat = to_ll.transform(xs, ys)
    print(f'{len(gid):,} Parcels features, {len(keys):,} UniqueGISIDs with a centroid', flush=True)
    return {k: (f'{la:.6f}', f'{lo:.6f}') for k, la, lo in zip(keys, lat, lon)}


def main(gdb, out):
    pts = points(gdb)
    meta, _, _, data = raw.read(gdb, layer='Parcels_TaxRoll', read_geometry=False)
    fields = list(meta['fields'])
    gi, ci, yi, oi = (fields.index(f) for f in ('UniqueGISID', 'CountyName', 'TaxRollYear', 'OwnerName'))
    county = collections.defaultdict(lambda: {'rows': 0, 'years': collections.Counter(), 'blank': 0, 'nopoint': 0})
    rows = nopoint = 0
    with open(out, 'w', encoding='utf-8', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(fields + ['site_state', 'LATITUDE', 'LONGITUDE'])
        for i in range(len(data[0])):
            rec = [value(col[i]) for col in data]
            p = pts.get(rec[gi])
            w.writerow(rec + ['ND'] + list(p or ('', '')))
            rows += 1
            c = county[rec[ci]]
            c['rows'] += 1
            c['years'][rec[yi]] += 1
            c['blank'] += not rec[oi].strip()
            if not p:
                c['nopoint'] += 1
                nopoint += 1
    with open(out + '.counties.tsv', 'w') as tsv:
        tsv.write('countyname\trows\ttaxrollyears\towner_blank\tno_point\n')
        for name, c in sorted(county.items()):
            years = ', '.join(f'{y or "blank"} {n}' for y, n in sorted(c['years'].items()))
            tsv.write(f'{name}\t{c["rows"]}\t{years}\t{c["blank"]}\t{c["nopoint"]}\n')
    print(f'wrote {out}: {rows:,} rows, {len(fields) + 3} columns, {len(county)} counties, {nopoint:,} without a point')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
