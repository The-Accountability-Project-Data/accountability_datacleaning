"""Build "Connecticut Parcels 2025" from the CT Office of Policy and Management's Connecticut CAMA and Parcel Layer 2025.

    python build.py <csv download> <geojson download> <output.csv>

Source: geodata.ct.gov item 45cc26320c634f64a67f1b6c6afbd9d1 (CC0), downloaded 2026-11-07 as CSV and as GeoJSON (WGS 84).
Both are the site's export of Oct. 24, 2026 and have the same 1,282,833 OBJECTIDs. The site does not make a shapefile of
this layer ("The dataset is too large for shapefile generation").
Columns: the CSV's 56 columns, in its order and with its names, as published (the CSV's text, unchanged); then
site_state "CT"; then LATITUDE and LONGITUDE: the centroid of the parcel polygon from the GeoJSON, joined on OBJECTID,
computed in Connecticut State Plane (EPSG:6434, the layer's own system) and converted to WGS 84, to 6 decimal places.
Blank when the parcel has no polygon. The polygons are not written. Stops if the two files' OBJECTIDs differ.
Writes UTF-8 without the source's byte-order mark, and <out>.towns.tsv with each Town_Name's rows, collection years,
"Current Owner" rows and blank-owner rows.
"""
import collections
import csv
import sys

import numpy as np
import pyogrio.raw as raw
import shapely
from pyproj import Transformer


def centroids(geojson):
    meta, _, geom, (oid,) = raw.read(geojson, columns=['OBJECTID'])
    shapes = shapely.from_wkb(geom)
    to_sp = Transformer.from_crs('EPSG:4326', 'EPSG:6434', always_xy=True)
    to_ll = Transformer.from_crs('EPSG:6434', 'EPSG:4326', always_xy=True)
    shapes = shapely.transform(shapes, lambda xy: np.column_stack(to_sp.transform(xy[:, 0], xy[:, 1])))
    cent = shapely.centroid(shapes)
    x, y = shapely.get_x(cent), shapely.get_y(cent)
    ok = ~(np.isnan(x) | np.isnan(y))
    lon, lat = np.full(len(x), np.nan), np.full(len(x), np.nan)
    lon[ok], lat[ok] = to_ll.transform(x[ok], y[ok])
    return {int(o): ((f'{la:.6f}', f'{lo:.6f}') if k else ('', '')) for o, la, lo, k in zip(oid, lat, lon, ok)}


def main(src_csv, src_geojson, out):
    points = centroids(src_geojson)
    print(f'{len(points):,} polygons read, {sum(1 for p in points.values() if not p[0]):,} without a centroid', flush=True)
    town = collections.defaultdict(lambda: {'rows': 0, 'years': collections.Counter(), 'current': 0, 'blank': 0})
    seen = set()
    with open(src_csv, encoding='utf-8-sig', newline='') as fh, open(out, 'w', encoding='utf-8', newline='') as oh:
        r = csv.reader(fh)
        header = next(r)
        oi, ti, yi, wi = (header.index(c) for c in ('OBJECTID', 'Town_Name', 'Collection_year', 'Owner'))
        w = csv.writer(oh)
        w.writerow(header + ['site_state', 'LATITUDE', 'LONGITUDE'])
        for rec in r:
            assert len(rec) == len(header), rec
            o = int(rec[oi])
            if o not in points:
                sys.exit(f'OBJECTID {o} is in the CSV but not the GeoJSON')
            seen.add(o)
            w.writerow(rec + ['CT', *points[o]])
            t = town[rec[ti]]
            t['rows'] += 1
            t['years'][rec[yi]] += 1
            t['current'] += rec[wi].strip().lower() == 'current owner'
            t['blank'] += not rec[wi].strip()
    if seen != set(points):
        sys.exit(f'{len(set(points) - seen)} GeoJSON OBJECTIDs are not in the CSV')
    with open(out + '.towns.tsv', 'w') as tsv:
        tsv.write('town_name\trows\tcollection_years\towner_current_owner\towner_blank\n')
        for name, t in sorted(town.items()):
            years = ', '.join(f'{y or "blank"} {n}' for y, n in sorted(t['years'].items()))
            tsv.write(f'{name}\t{t["rows"]}\t{years}\t{t["current"]}\t{t["blank"]}\n')
    print(f'wrote {out}: {len(seen):,} rows, {len(header) + 3} columns, {len(town)} Town_Name values')


if __name__ == '__main__':
    main(*sys.argv[1:4])
