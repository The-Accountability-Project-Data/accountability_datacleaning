"""Compare one county's StratMap 2026 land parcels zip with the same county's rows in the statewide file
(2026-11-09, user request): layers, CRS, fields, row counts, and per-record attribute and geometry differences.
    python -I state/tx/parcels/code/compare_county_state.py <state.gdb> <county.gdb> <FIPS>
Records are matched on all attribute values first; what's left is reported. Geometry is compared by centroid after
converting the statewide geometry to the county file's CRS.
"""
import collections
import sys

import numpy as np
import pyogrio
import pyogrio.raw as raw
import shapely
from pyproj import Transformer


def load(path, where=None):
    layer = pyogrio.list_layers(path)[0][0]
    info = pyogrio.read_info(path, layer=layer)
    meta, _, geom, data = raw.read(path, layer=layer, where=where)
    return layer, info, meta, geom, data


def norm(v):
    if v is None:
        return ''
    if hasattr(v, 'item') and not isinstance(v, np.datetime64):
        v = v.item()
    if isinstance(v, float):
        if np.isnan(v):
            return ''
        return str(int(v)) if v.is_integer() else f'{v:.12g}'
    if isinstance(v, np.datetime64):
        return '' if np.isnat(v) else str(v)
    return str(v.item() if hasattr(v, 'item') else v)


state, county, fips = sys.argv[1:4]
sl, si, sm, sg, sd = load(state, where=f"FIPS = '{fips}'")
cl, ci, cm, cg, cd = load(county)
print('state layer', sl, si['crs'], '| county layer', cl, ci['crs'])
print('rows: state', len(sg), 'county', len(cg))
print('fields equal:', list(sm['fields']) == list(cm['fields']), set(sm['fields']) ^ set(cm['fields']))
print('dtypes differ:', [(f, a, b) for f, a, b in zip(si['fields'], si['dtypes'], ci['dtypes']) if a != b])
SKIP = set(sys.argv[4].split(',')) if len(sys.argv) > 4 else set()
fields = [f for f in cm['fields'] if f not in ('SHAPE_Length', 'SHAPE_Area') and f not in SKIP]
for f in sorted(SKIP):
    a = sum(1 for v in dict(zip(sm['fields'], sd))[f] if norm(v)); b = sum(1 for v in dict(zip(cm['fields'], cd))[f] if norm(v))
    print('skipped', f, 'filled: state', a, 'county', b)
sc, cc = dict(zip(sm['fields'], sd)), dict(zip(cm['fields'], cd))
srows = [tuple(norm(sc[f][i]) for f in fields) for i in range(len(sg))]
crows = [tuple(norm(cc[f][i]) for f in fields) for i in range(len(cg))]
s_count, c_count = collections.Counter(srows), collections.Counter(crows)
only_s, only_c = s_count - c_count, c_count - s_count
print('identical attribute records:', sum((s_count & c_count).values()), '| only in state:', sum(only_s.values()),
      '| only in county:', sum(only_c.values()))
# for unmatched records, which fields differ (match on PROP_ID)
pi = fields.index('PROP_ID')
by_c = collections.defaultdict(list)
for r in only_c.elements():
    by_c[r[pi]].append(r)
diff_fields = collections.Counter()
examples = collections.defaultdict(list)
for r in only_s.elements():
    for c in by_c.get(r[pi], [])[:1]:
        for f, a, b in zip(fields, r, c):
            if a != b:
                diff_fields[f] += 1
                if len(examples[f]) < 3:
                    examples[f].append((r[pi], a, b))
print('fields differing in unmatched records (state vs county):', diff_fields.most_common())
for f, ex in examples.items():
    print('  ', f, ex)
# geometry: centroids
to_c = Transformer.from_crs(si['crs'], ci['crs'], always_xy=True)
sgeo = shapely.from_wkb(sg)
sgeo = shapely.transform(sgeo, lambda xy: np.column_stack(to_c.transform(xy[:, 0], xy[:, 1])))
cgeo = shapely.from_wkb(cg)
sk = collections.defaultdict(list)
for r, g in zip(srows, sgeo):
    sk[r].append(g)
dist, missing = [], 0
for r, g in zip(crows, cgeo):
    if sk.get(r):
        s = sk[r].pop()
        if s is None or g is None or shapely.is_empty(s) or shapely.is_empty(g):
            missing += 1
            continue
        a, b = shapely.centroid(s), shapely.centroid(g)
        dist.append(((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5)
d = np.array(dist)
print('centroid distance (degrees) for matched records: n', len(d), 'max', d.max() if len(d) else None,
      '>1e-6:', int((d > 1e-6).sum()), '>1e-4:', int((d > 1e-4).sum()), '| empty geometry pairs', missing)
print('vertex counts: state', int(shapely.get_num_coordinates(sgeo).sum()), 'county',
      int(shapely.get_num_coordinates(cgeo).sum()))
