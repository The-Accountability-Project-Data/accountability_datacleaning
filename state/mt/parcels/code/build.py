"""Build "Montana Parcels 2026" from the Montana Cadastral Framework statewide parcels file geodatabase.

    python build.py <path>/Montana_Parcels.gdb <output dir>/mt_parcels_2026.csv

Source: https://ftpgeoinfo.msl.mt.gov/Data/Spatial/MSDI/Cadastral/Parcels/Statewide/MTParcels_GDB.zip (Montana State
Library, Montana Cadastral Framework; owner, address, value and agricultural fields copied from the Montana Department
of Revenue's ORION database). One feature class, OwnerParcel (parcel polygons).
Columns: the 2023 file's 46 columns (csv/MT_parcels.csv, Nov. 2023), in that order:
* the layer's 43 attribute fields, under the 2023 file's names (the shapefile's 10-character names, e.g. AddressLine1 ->
  AddressLin);
* site_city, site_state, site_zip, split from CityStateZip as in the 2023 file: the last word is site_zip, the one
  before it site_state, the rest site_city (so "SAINT REGIS, MT 59866" -> "SAINT REGIS,", "MT", "59866"); blank when
  CityStateZip has fewer than three words; except that site_state is "MT" in every row (every parcel is in Montana;
  CityStateZip is blank for 411,353 parcels);
then LATITUDE and LONGITUDE: the centroid of the parcel polygon (shapely), converted from Montana State Plane
(EPSG:6514) to WGS 84 (EPSG:4326), to 6 decimal places. The polygons themselves are not written.
Every value is written as published: blanks for missing values, whole numbers without a decimal point, other numbers to
15 significant digits. Stops if a layer field is not in the list below.
Row order is the layer's, except that rows with no PARCELID, OwnerName or TaxYear (polygons with no tax record; 33,562
on 2026-11-06) are written after all the others, in their own order, so that a preview of the top of the file shows
records.
Writes <out>.counties.tsv with each county's rows and tax years.
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

LAYER = 'OwnerParcel'
CHUNK = 200_000
# layer field -> 2023 column, in the 2023 file's order
FIELDS = [('PARCELID', 'PARCELID'), ('COUNTYCD', 'COUNTYCD'), ('CountyName', 'CountyName'),
          ('CountyAbbr', 'CountyAbbr'), ('GISAcres', 'GISAcres'), ('TaxYear', 'TaxYear'), ('PropertyID', 'PropertyID'),
          ('AssessmentCode', 'Assessment'), ('Township', 'Township'), ('Range', 'Range'), ('Section', 'Section'),
          ('LegalDescriptionShort', 'LegalDescr'), ('Subdivision', 'Subdivisio'), ('CertificateOfSurvey', 'Certificat'),
          ('AddressLine1', 'AddressLin'), ('AddressLine2', 'AddressL_1'), ('CityStateZip', 'CityStateZ'),
          ('PropAccess', 'PropAccess'), ('LevyDistrict', 'LevyDistri'), ('PropType', 'PropType'),
          ('ContinuousCropAcres', 'Continuous'), ('FallowAcres', 'FallowAcre'), ('FarmsiteAcres', 'FarmsiteAc'),
          ('ForestAcres', 'ForestAcre'), ('GrazingAcres', 'GrazingAcr'), ('WildHayAcres', 'WildHayAcr'),
          ('IrrigatedAcres', 'IrrigatedA'), ('NonQualAcres', 'NonQualAcr'), ('TotalAcres', 'TotalAcres'),
          ('TotalBuildingValue', 'TotalBuild'), ('TotalLandValue', 'TotalLandV'), ('TotalValue', 'TotalValue'),
          ('OwnerName', 'OwnerName'), ('OwnerAddress1', 'OwnerAddre'), ('OwnerAddress2', 'OwnerAdd_1'),
          ('OwnerAddress3', 'OwnerAdd_2'), ('OwnerCity', 'OwnerCity'), ('OwnerState', 'OwnerState'),
          ('OwnerZipCode', 'OwnerZipCo'), ('DbaName', 'DbaName'), ('CareOfTaxpayer', 'CareOfTaxp'),
          ('Shape_Length', 'Shape_Leng'), ('Shape_Area', 'Shape_Area')]
HEADER = [old for _, old in FIELDS] + ['site_city', 'site_state', 'site_zip', 'LATITUDE', 'LONGITUDE']


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


def split_csz(csz):
    words = csz.split()
    if len(words) < 3:
        return ['', '', '']
    return [' '.join(words[:-2]), words[-2], words[-1]]


def main(gdb, out):
    info = pyogrio.read_info(gdb, layer=LAYER)
    fields, total, crs = list(info['fields']), info['features'], info['crs']
    names = [f for f, _ in FIELDS]
    if sorted(fields) != sorted(names):
        sys.exit(f'layer fields differ: not listed {set(fields) - set(names)}; missing {set(names) - set(fields)}')
    print(f'layer {LAYER}: {total:,} features, crs {crs}')
    to_wgs84 = Transformer.from_crs(crs, 'EPSG:4326', always_xy=True)
    rows = no_point = 0
    held = []
    pi, oi, ti = names.index('PARCELID'), names.index('OwnerName'), names.index('TaxYear')
    county = collections.defaultdict(lambda: {'rows': 0, 'years': collections.Counter()})
    with open(out, 'w', encoding='utf-8', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(HEADER)
        for skip in range(0, total, CHUNK):
            meta, _, geom, data = raw.read(gdb, layer=LAYER, skip_features=skip, max_features=CHUNK)
            cols = dict(zip(meta['fields'], data))
            shapes = shapely.from_wkb(geom)
            cent = shapely.centroid(shapes)
            x, y = shapely.get_x(cent), shapely.get_y(cent)
            ok = ~(np.isnan(x) | np.isnan(y))
            lon, lat = np.full(len(x), np.nan), np.full(len(x), np.nan)
            lon[ok], lat[ok] = to_wgs84.transform(x[ok], y[ok])
            for i in range(len(geom)):
                rec = [value(cols[f][i]) for f in names]
                csz = split_csz(rec[names.index('CityStateZip')])
                csz[1] = 'MT'
                rec += csz
                if ok[i]:
                    rec += [f'{lat[i]:.6f}', f'{lon[i]:.6f}']
                else:
                    rec += ['', '']
                    no_point += 1
                if rec[pi].strip() or rec[oi].strip() or rec[ti].strip():
                    w.writerow(rec)
                else:
                    held.append(rec)
                rows += 1
                c = county[(rec[names.index('COUNTYCD')], rec[names.index('CountyName')])]
                c['rows'] += 1
                c['years'][rec[names.index('TaxYear')]] += 1
            print(f'{rows:,} of {total:,} rows', flush=True)
        w.writerows(held)
        print(f'{len(held):,} rows with no PARCELID, OwnerName or TaxYear written last', flush=True)
    with open(out + '.counties.tsv', 'w') as tsv:
        tsv.write('countycd\tcountyname\trows\ttaxyears\n')
        for (cd, name), c in sorted(county.items(), key=lambda kv: kv[0][1]):
            years = ', '.join(f'{y or "blank"} {n}' for y, n in sorted(c['years'].items()))
            tsv.write(f'{cd}\t{name}\t{c["rows"]}\t{years}\n')
    print(f'wrote {out}: {rows:,} rows, {len(HEADER)} columns, {len(county)} counties, {no_point:,} without a point')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
