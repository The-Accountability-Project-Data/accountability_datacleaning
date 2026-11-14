# North Carolina Parcels

_Built 2026-11-06. The runnable script is
[`code/build.py`](code/build.py)._

North Carolina parcels come from [NC OneMap][ncom], which assembles the parcel data of all 100 county data producers
into one statewide dataset with a standard set of fields. The new file, `nc_parcels_2026.csv`, has 5,925,955 parcels
in all 100 counties. The earlier edition is `nc_parcels.csv` (July 2019, 5,533,784 parcels).

[ncom]: https://www.nconemap.gov/pages/parcels

## Source

`nc-parcels-gdb-most-recent.zip`, NC OneMap's statewide file geodatabase, downloaded 2026-11-06 from
`https://dit-cgia-gis-data.s3.amazonaws.com/NCOM-data/parcels/nc-parcels-gdb-most-recent.zip` (Last-Modified
2026-11-06). It holds `NC_Parcels_all.gdb` with three feature classes:
`nc_parcels_poly` (parcel boundaries, 5,938,804), `nc_parcels_pt` (one point per parcel, at or near its center,
5,925,955) and `nc_parcels_participants` (one record per county with its transfer date and file). The field
definitions are on NC OneMap's [data dictionary page][dd].

[dd]: https://assets.nconemap.gov/pages/hub/ncom-parcels-dd.htm

The file is read from the point feature class.

Counties send their data to NC OneMap at different times. `TRANSFDATE` is the date a county's data was transferred;
it runs from 2025-03-25 (Hyde) to 2026-08-31 (Alleghany), and 72 counties are from May 2026. Each county's rows and
transfer date are in [`nc_parcels_2026_counties.tsv`](nc_parcels_2026_counties.tsv).

## Columns

The 2019 file's 68 columns, in its order, then two new ones:

* The 67 attribute fields of the point feature class, in upper case. Their names and order are those of the 2019
  file.
* `OBJECTID` is the feature class's feature id.
* `LATITUDE` and `LONGITUDE`: the point, converted from North Carolina State Plane (EPSG:2264) to WGS 84 (EPSG:4326),
  to 6 decimal places. Every row has a point.

Values are as published. Blanks are missing values; whole numbers have no decimal point; dates are as the
geodatabase stores them (`2026-03-24T00:00:00.000`). Some values are not what their field names suggest: for example, `SOURCEDATE` has dates from 1664 to 9999, and `CNTYFIPS` is `5` for Alleghany
and three digits for other counties. 62,074 rows have no `OWNNAME`. UTF-8.

One change from the source: `OWNNAME` and `OWNNAME2` list several owners separated by semicolons, with no spaces
("HUGENSCHMIDT, MARY B;RUCKER, BRADLEY K"). Each semicolon is written with a space on each side
("HUGENSCHMIDT, MARY B ; RUCKER, BRADLEY K") in 494,485 `OWNNAME` values and 18,311 `OWNNAME2` values. Semicolons in other fields are as published.

## Differences from 2019

* 2019 has the Eastern Band of Cherokee Indians as a 101st `CNTYNAME` (57 rows). The 2026 source has no rows with
  that name or source agent.
* 2019 has no coordinates.
