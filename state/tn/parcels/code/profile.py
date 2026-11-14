"""Profile the 86 Tennessee county parcel zips (data/raw/): extracts each county's ASSESSMENT_DATA_##.dbf and
Parcels_## shapefile to data/x/<county>/, then reports per county: assessment rows, parcel polygons,
GISLINK matches, tax years, owner / mailing / site address fill, field-set differences. Writes
data/profile_2026.tsv.
    python state/tn/parcels/code/profile.py   (from any directory; paths are relative to this script)
"""
import collections, json, os, re, zipfile
from pathlib import Path
import pyogrio, pyogrio.raw as raw
HERE = Path(__file__).resolve().parent
DATA = HERE.parent / 'data'
src = json.load(open(HERE / 'sources.json'))
rows = []; base_fields = None; field_diffs = collections.Counter(); crs = collections.Counter()
for c in src['counties']:
    name = c['county']; d = str(DATA / 'x' / name); os.makedirs(d, exist_ok=True)
    z = zipfile.ZipFile(DATA / 'raw' / ('%s.zip' % name))
    for n in z.namelist():
        b = n.replace('\\', '/').split('/')[-1]
        if re.match(r'(ASSESSMENT_DATA|Parcels)_\d+\.', b, re.I) or b.lower() == 'field dictionary.xlsx':
            p = os.path.join(d, b)
            if not os.path.exists(p): open(p, 'wb').write(z.read(n))
    adbf = [f for f in os.listdir(d) if f.upper().startswith('ASSESSMENT_DATA') and f.lower().endswith('.dbf')]
    pshp = [f for f in os.listdir(d) if f.lower().startswith('parcels_') and f.lower().endswith('.shp')]
    if not adbf or not pshp:
        rows.append({'county': name, 'note': 'missing ' + ('assessment' if not adbf else 'parcels')}); continue
    meta, _, _, data = raw.read(os.path.join(d, adbf[0]), read_geometry=False)
    f = list(meta['fields']); col = {k: data[i] for i, k in enumerate(f)}
    if base_fields is None: base_fields = f
    if f != base_fields: field_diffs[tuple(sorted(set(f) ^ set(base_fields)))] += 1
    n = len(data[0])
    def filled(k): return sum(1 for v in col.get(k, []) if v is not None and str(v).strip() not in ('', 'nan')) / n if n else 0
    yrs = collections.Counter(str(v) for v in col.get('TAXYR_NUM', []))
    addr = [str(v).strip() for v in col.get('ADDRESS', []) if v is not None and str(v).strip()]
    num_last = sum(1 for a in addr if re.search(r'\s\d+[A-Z]?$', a)); num_first = sum(1 for a in addr if re.match(r'\d', a))
    pinfo = pyogrio.read_info(os.path.join(d, pshp[0])); crs[pinfo['crs']] += 1
    pm, _, _, pdata = raw.read(os.path.join(d, pshp[0]), read_geometry=False, columns=['GISLINK'])
    links = set(str(v).strip() for v in pdata[0])
    match = sum(1 for v in col['GISLINK'] if str(v).strip() in links) / n if n else 0
    rows.append({'county': name, 'assessment_rows': n, 'parcel_polygons': pinfo['features'], 'gislink_match': round(match, 3),
                 'tax_years': ' '.join('%s:%d' % kv for kv in yrs.most_common(3)),
                 'owner': round(filled('OWNER'), 3), 'owner2': round(filled('OWNER2'), 3), 'mailaddr': round(filled('MAILADDR'), 3),
                 'mailcity': round(filled('MAILCITY'), 3), 'zip': round(filled('ZIP'), 3), 'site_address': round(filled('ADDRESS'), 3),
                 'site_num_last': round(num_last / len(addr), 3) if addr else 0, 'site_num_first': round(num_first / len(addr), 3) if addr else 0,
                 'lastupdate_max': max((str(v) for v in col.get('LASTUPDATE', []) if v is not None), default='')})
    print(name, rows[-1]['assessment_rows'], rows[-1]['owner'], rows[-1]['tax_years'], flush=True)
keys = ['county', 'assessment_rows', 'parcel_polygons', 'gislink_match', 'tax_years', 'owner', 'owner2', 'mailaddr', 'mailcity',
        'zip', 'site_address', 'site_num_last', 'site_num_first', 'lastupdate_max', 'note']
with open(DATA / 'profile_2026.tsv', 'w') as fh:
    fh.write('\t'.join(keys) + '\n')
    for r in rows: fh.write('\t'.join(str(r.get(k, '')) for k in keys) + '\n')
print('field set differences:', dict(field_diffs)); print('crs:', dict(crs))
print('total assessment rows', sum(r.get('assessment_rows', 0) for r in rows), 'polygons', sum(r.get('parcel_polygons', 0) for r in rows))
