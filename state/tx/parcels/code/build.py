"""Build "Texas Parcels 2026" from the TxGIO StratMap 2026 Land Parcels statewide file geodatabase.

    python build.py <stratmap-2026-land-parcels_48.gdb> <tx_parcels_2026_base.csv>

Source: https://data.geographic.texas.gov/1d33dafb-6e9c-40ac-887d-f4577909ed9b/resources/stratmap26-landparcels_48_lp.zip
(Texas Geographic Information Office, StratMap 2026 Land Parcels, CC0; data from the county appraisal districts),
downloaded 2026-11-09. One feature class, stratmap_2026_land_parcels_48: 14,279,876 parcel polygons in 253 counties
(Donley is not in it), Web Mercator (EPSG:3857). The statewide file is used rather than the 253 county files; it has the same records, owners and polygons as the county files, but GIS_AREA_UNIT, LGL_AREA_UNIT,
LOC_LAND_USE and STAT_LAND_USE are blank in it, and YEAR_BUILT values listing several years are cut short
(compare_county_state.py).
Columns: the layer's 36 attribute fields, in its order and with its names, as published: blanks for missing values,
whole numbers without a decimal point, other numbers to 15 significant digits, DATE_ACQ as YYYY-MM-DD. Then LATITUDE and
LONGITUDE: the centroid of the parcel polygon, computed in Texas Centric Albers Equal Area (EPSG:3083) and converted to
WGS 84, to 6 decimal places; blank when the parcel has no polygon. The polygons are not written.
address_columns.py then adds separate address columns. Writes <out>.counties.tsv with each county's rows, tax years, blank owners and rows without a point.
"""
import collections
import csv
import math
import sys

import numpy as np
import pyogrio
import pyogrio.raw as raw
import shapely
from pyproj import Transformer

CHUNK = 500_000


def value(v):
    if v is None:
        return ''
    if isinstance(v, np.datetime64):
        return '' if np.isnat(v) else str(v.astype('datetime64[D]'))
    if isinstance(v, float):
        if math.isnan(v):
            return ''
        return str(int(v)) if v.is_integer() else f'{v:.15g}'
    if hasattr(v, 'item'):          # numpy scalar
        return value(v.item())
    return str(v)


def main(gdb, out):
    layer = pyogrio.list_layers(gdb)[0][0]
    info = pyogrio.read_info(gdb, layer=layer)
    fields, total = list(info['fields']), info['features']
    to_alb = Transformer.from_crs(info['crs'], 'EPSG:3083', always_xy=True)
    to_ll = Transformer.from_crs('EPSG:3083', 'EPSG:4326', always_xy=True)
    ci, yi, oi = fields.index('COUNTY'), fields.index('TAX_YEAR'), fields.index('OWNER_NAME')
    county = collections.defaultdict(lambda: {'rows': 0, 'years': collections.Counter(), 'blank': 0, 'nopoint': 0})
    rows = nopoint = 0
    with open(out, 'w', encoding='utf-8', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(fields + ['LATITUDE', 'LONGITUDE'])
        for skip in range(0, total, CHUNK):
            meta, _, geom, data = raw.read(gdb, layer=layer, skip_features=skip, max_features=CHUNK)
            assert list(meta['fields']) == fields
            shapes = shapely.from_wkb(geom)
            shapes = shapely.transform(shapes, lambda xy: np.column_stack(to_alb.transform(xy[:, 0], xy[:, 1])))
            cent = shapely.centroid(shapes)
            x, y = shapely.get_x(cent), shapely.get_y(cent)
            ok = ~(np.isnan(x) | np.isnan(y))
            lon, lat = np.full(len(x), np.nan), np.full(len(x), np.nan)
            lon[ok], lat[ok] = to_ll.transform(x[ok], y[ok])
            for i in range(len(geom)):
                rec = [value(col[i]) for col in data]
                c = county[rec[ci]]
                if ok[i]:
                    rec += [f'{lat[i]:.6f}', f'{lon[i]:.6f}']
                else:
                    rec += ['', '']
                    nopoint += 1
                    c['nopoint'] += 1
                w.writerow(rec)
                rows += 1
                c['rows'] += 1
                c['years'][rec[yi]] += 1
                c['blank'] += not rec[oi].strip()
            print(f'{rows:,} of {total:,} rows', flush=True)
    with open(out + '.counties.tsv', 'w') as tsv:
        tsv.write('county\trows\ttax_years\towner_blank\tno_point\n')
        for name, c in sorted(county.items()):
            years = ', '.join(f'{y or "blank"} {n}' for y, n in sorted(c['years'].items()))
            tsv.write(f'{name}\t{c["rows"]}\t{years}\t{c["blank"]}\t{c["nopoint"]}\n')
    print(f'wrote {out}: {rows:,} rows, {len(fields) + 2} columns, {len(county)} counties, {nopoint:,} without a point')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
