# Montana Parcels

_Built 2026-11-06. The runnable script is
[`code/build.py`](code/build.py)._

Montana parcels come from the [Montana Cadastral Framework][mtcad], published by the Montana State Library. Owner
names and addresses, site addresses, assessed values, agricultural acres and tax districts are copied from the Montana
Department of Revenue's ORION tax appraisal database. The new file, `mt_parcels_2026.csv`, has 921,278 parcels in all
56 counties, for tax year 2026. The earlier edition is `MT_parcels.csv` (Nov. 28, 2023, 913,419 parcels).

[mtcad]: https://svc.mt.gov/msl/mtcadastral

## Source

`MTParcels_GDB.zip`, the statewide file geodatabase, downloaded 2026-11-06 from
`https://ftpgeoinfo.msl.mt.gov/Data/Spatial/MSDI/Cadastral/Parcels/Statewide/MTParcels_GDB.zip` (Last-Modified
2026-11-03). It holds `Montana_Parcels.gdb` with one feature class,
`OwnerParcel`: 921,278 parcel polygons in Montana State Plane (EPSG:6514), with 43 attribute fields. The field
definitions are in `MontanaCadastral_ParcelMetadata.xml`, in the same zip.

Rows and tax years by county are in [`mt_parcels_2026_counties.tsv`](mt_parcels_2026_counties.tsv). Counties range
from Treasure (2,169) to Flathead (84,196).

## Columns

The 2023 file's 46 columns, in its order, then two new ones:

* The 43 attribute fields, under the 2023 file's names. Those are the shapefile's 10-character names: `AddressLine1`
  is `AddressLin`, `Subdivision` is `Subdivisio`, `CertificateOfSurvey` (the Certificate of Survey number) is `Certificat`,
  `OwnerAddress2` is `OwnerAdd_1`, and so on (`code/build.py` lists each pair).
* `site_city`, `site_state` and `site_zip`, split from `CityStateZip` as in the 2023 file. The last word is the ZIP,
  the word before it the state, and the rest the city, so "SAINT REGIS, MT 59866" becomes `SAINT REGIS,`, `MT` and
  `59866`. `site_city` and `site_zip` are blank when `CityStateZip` has fewer than three words; 509,925 rows have a
  `CityStateZip`. `site_state` is `MT` in every row.
* `LATITUDE` and `LONGITUDE`: the centroid of each parcel polygon, converted to WGS 84 (EPSG:4326), to 6 decimal
  places. Every row has one. The polygons are not in the file.

Values are as published: blanks are missing values, whole numbers have no decimal point, and other numbers have up to
15 significant digits. UTF-8.

37,293 polygons have no `TaxYear` and no owner (33,562 of them have no attributes at all but the county). In the 2023
file the same kind of rows have `TaxYear` 0. The 33,562 rows with no `PARCELID`, `OwnerName` or `TaxYear` are at
the end of the file; all rows are otherwise in the layer's order.
