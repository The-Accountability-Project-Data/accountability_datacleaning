# Tennessee Parcels

_Built 2026-11-10. The runnable scripts are
[`code/fetch.py`](code/fetch.py), [`code/profile.py`](code/profile.py) and [`code/build.py`](code/build.py)._

Tennessee parcels come from the [Tennessee Comptroller of the Treasury, Division of Property Assessments][page], which
maintains parcel maps and assessment records for 86 of the state's 95 counties. The file `tn_parcels_2026.csv` has
2,269,704 assessment records from those 86 counties. Chester, Davidson, Hamilton, Hickman, Knox, Montgomery,
Rutherford, Shelby and Williamson counties keep their own records and are not in it.

[page]: https://comptroller.tn.gov/office-functions/pa/gisredistricting/redistricting-and-land-use-maps/parcel-data.html

## Source

Each county's data is a zip file, linked after submitting the Comptroller's parcel data request form (name, address and
an attestation; no fee). The 86 zips (5.1 GB) were downloaded on 2026-11-10; their URLs are in [`code/sources.json`](code/sources.json). The Comptroller updates the files weekly. Its terms: "Any company
or organization can use, save, and maintain the shapefile data for any use case."

Each zip holds a parcel polygon shapefile (`Parcels_##`), an assessment table (`ASSESSMENT_DATA_##.dbf`) joined to it
on `GISLINK`, a field dictionary (`Field Dictionary.xlsx`) and other map layers (streets, water, lot lines), which are
not used. The assessment tables were last updated between 2026-10-28 and 2026-10-31.

## Records

The assessment tables have 2,895,320 records. A county can include two tax years: the current year (`TAXYR` "C") and
the next year (`TAXYR` "F"). The file has every current-year record (2,265,960) and the next-year record of the 3,744
parcels that have no current-year record. A parcel is `PARCELID` without its trailing tax year. One map parcel
(`GISLINK`) can carry several parcels, such as leaseholds and separately assessed interests (`SI`); each is its own
row. The current tax year is 2027 in 62 counties and 2026 in 24.

Per-county counts are in [`tn_parcels_2026_counties.tsv`](tn_parcels_2026_counties.tsv).

## Columns

`COUNTY`, the county file's name, then the assessment table's fields in its order and with its names, as published.
Tipton County's table has two more fields, `STNUM` and `STNAME`, which are at the end of the source fields and blank for
the other counties. Then:

* `site_state`: TN on every row.
* `LATITUDE` and `LONGITUDE`: the centroid of the parcel's polygons with the same `GISLINK`, area-weighted over all of
  them, computed in CONUS Albers (EPSG:5070) and converted to WGS 84, to 6 decimal places. 2,203 records have no
  polygon and no coordinates.

`ADDRESS` is the property address with the street name first and the house number last ("DUNCAN LN 419"). The mailing
address is in `MAILADDR`, `MAILCITY`, `STATE` and `ZIP`. Values are as published: blanks are missing values, whole
numbers have no decimal point, and dates are written as `YYYY-MM-DD`. UTF-8.

Owner names contain 254 semicolons next to a letter, typos and remnants of HTML entities ("ATTN;REAL ESTATE
DEPT", "&AMP; JOSHUA KANE HINCH"); they are as published.
