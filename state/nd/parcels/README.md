# North Dakota Parcels

_Built 2026-11-09. The runnable script is
[`code/build.py`](code/build.py)._

North Dakota parcels come from the [State Parcel Program][ndpp] of the North Dakota GIS Hub. Counties and their vendors
send parcel maps and tax roll data to the GIS Hub, monthly to yearly depending on the county. The program's focus is
rural parcels; some city parcels are not in it. The file `nd_parcels_2026.csv` has 749,142 tax roll records in all 53
counties, mostly from the 2026 tax roll. It is the first North Dakota parcels dataset.

[ndpp]: https://north-dakota-state-parcel-program-ndgov.hub.arcgis.com/

## Source

`NDParcelsFGDB.gdb.zip` (ArcGIS item `c9e6956684c14fa299ee9e38c90dc003`), downloaded 2026-11-09 (Last-Modified
2026-11-09). It holds two layers:

* `Parcels_TaxRoll`, a table of 749,142 tax roll records with 56 fields.
* `Parcels`, 723,208 parcel polygons in WGS 84.

They join on `UniqueGISID`: one parcel can have several tax roll records.

`TaxRollYear` is 2026 for 541,339 records, 2025 for 65,475, 2024 for 9,184 (Dickey County), 0 for 1,290 (McKenzie
County) and blank for 131,854 (13 counties, among them Burke, Cavalier, Richland and part of Burleigh). Rows, tax roll
years, blank owners and rows without a point by county are in
[`nd_parcels_2026_counties.tsv`](nd_parcels_2026_counties.tsv).

## Columns

One row per tax roll record: the table's 56 fields, in its order and with its names, then:

* `site_state`: `ND`. The table has property city and ZIP fields but no property state.
* `LATITUDE` and `LONGITUDE`: the centroid of the record's parcel, in WGS 84, to 6 decimal places. It is computed from
  every `Parcels` feature with the record's `UniqueGISID`, in CONUS Albers (EPSG:5070). 16,611 parcels are stored as
  more than one feature; their centroid is the area-weighted mean of the features' centroids. 102,491 records have no
  coordinates, as no feature has their `UniqueGISID`; most are in Ward (21,951), Stutsman, Barnes, Wells and Mercer
  counties. The polygons are not in the file.

Values are as published: blanks are missing values, whole numbers have no decimal point, other numbers have up to 15
significant digits, and `DateImported` is written as `YYYY-MM-DDTHH:MM:SS`. UTF-8.

## Owners

Each record has an owner and a second owner, each with a mailing address in parts (street, city, state, country,
ZIP, ZIP+4). `OwnerName` is blank for 9,686 records and `OwnerMailingAddress` for 39,461.
