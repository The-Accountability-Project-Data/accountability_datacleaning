"""Build "Mississippi Parcels 2024" from the MDEQ Cadastral Framework statewide shapefiles (2024 release, via MARIS).

    python build.py <path>/MS_East_MDEQPARCELS_2024.shp <path>/MS_West_MDEQPARCELS_2024.shp \
        <output dir>/ms_parcels_2024.csv

Source: https://maris.mississippi.edu/MARISdata/Parcels/MS_StatewideParcels_Aug2024/MS_East_MDEQPARCELS_2024.zip and
MS_West_MDEQPARCELS_2024.zip (Mississippi Department of Environmental Quality, Office of Geology and Energy Resources,
Cadastral Framework; distributed by MARIS), downloaded 2026-11-09. East: 44 counties, Mississippi East State Plane;
West: 38 counties, Mississippi West State Plane. The two have the same 53 attribute fields; West also has OBJECTID.
Columns: the 53 shared fields, in the East file's order and with its names, as published, then OBJECTID (blank for
East rows, as East has none), then source_file ("East" or "West"). LATDEC and LONGDEC are fields of the source (the
parcel's point, in decimal degrees); the polygons are not read. Every value is written as published: blanks for missing
values, whole numbers without a decimal point, other numbers to 15 significant digits, PLATDATE as YYYY-MM-DD.
Writes <out>.counties.tsv with each county's rows, source file, tax years and blank owners.
"""
import collections
import csv
import math
import sys

import numpy as np
import pyogrio
import pyogrio.raw as raw

CHUNK = 300_000


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


def main(east, west, out):
    fields = [f for f in pyogrio.read_info(east)['fields'] if f != 'OBJECTID']
    county = collections.defaultdict(lambda: {'rows': 0, 'file': '', 'years': collections.Counter(), 'blank': 0})
    rows = 0
    with open(out, 'w', encoding='utf-8', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(fields + ['OBJECTID', 'source_file'])
        for label, path in (('East', east), ('West', west)):
            info = pyogrio.read_info(path)
            have = set(info['fields'])
            assert set(fields) <= have and have - set(fields) <= {'OBJECTID'}, (label, have ^ set(fields))
            for skip in range(0, info['features'], CHUNK):
                meta, _, _, data = raw.read(path, read_geometry=False, skip_features=skip, max_features=CHUNK)
                cols = dict(zip(meta['fields'], data))
                n = len(data[0])
                oid = cols.get('OBJECTID')
                for i in range(n):
                    rec = [value(cols[f][i]) for f in fields]
                    w.writerow(rec + [value(oid[i]) if oid is not None else '', label])
                    rows += 1
                    c = county[rec[fields.index('CNTYNAME')]]
                    c['rows'] += 1
                    c['file'] = label
                    c['years'][rec[fields.index('TAXYEAR')]] += 1
                    c['blank'] += not rec[fields.index('OWNNAME')].strip()
                print(f'{label}: {rows:,} rows so far', flush=True)
    with open(out + '.counties.tsv', 'w') as tsv:
        tsv.write('cntyname\tsource_file\trows\ttaxyears\towner_blank\n')
        for name, c in sorted(county.items()):
            years = ', '.join(f'{y or "blank"} {n}' for y, n in sorted(c['years'].items()))
            tsv.write(f'{name}\t{c["file"]}\t{c["rows"]}\t{years}\t{c["blank"]}\n')
    print(f'wrote {out}: {rows:,} rows, {len(fields) + 2} columns, {len(county)} counties')


if __name__ == '__main__':
    main(*sys.argv[1:4])
