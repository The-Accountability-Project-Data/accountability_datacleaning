# Mississippi Parcels

_Built 2026-11-09. The runnable script is [`code/build.py`](code/build.py)._

Mississippi parcels come from the [Cadastral Framework][maris] compiled by the Mississippi Department of Environmental
Quality's Office of Geology and Energy Resources and distributed by MARIS. Counties submit their tax maps and
assessment data each year; MDEQ releases the statewide layer a few months after the end of August. The file
`ms_parcels_2024.csv` is the 2024 release: 2,006,049 parcels in all 82 counties, all with `TAXYEAR` 2024.

[maris]: https://maris.mississippi.edu/HTML/DATA/data_Cadastral/CadastralFramework.html

## Source

Two shapefile zips, downloaded 2026-11-09 from
`https://maris.mississippi.edu/MARISdata/Parcels/MS_StatewideParcels_Aug2024/`:

* `MS_East_MDEQPARCELS_2024.zip` (dated 2026-04-22): 1,127,050 parcels in 44 counties, in Mississippi East State
  Plane.
* `MS_West_MDEQPARCELS_2024.zip` (dated 2026-04-22): 878,999 parcels in 38 counties, in Mississippi West State Plane.

Both have the same 53 attribute fields; the West file also has `OBJECTID`. Field definitions are in the metadata PDF in
each zip. Rows, tax years and blank owners by county are in
[`ms_parcels_2024_counties.tsv`](ms_parcels_2024_counties.tsv); counties range from Issaquena (2,846) to Hinds
(114,935).

## Columns

The 53 shared fields, in the East file's order and with its names, then:

* `OBJECTID`, from the West file; blank for East rows.
* `source_file`: `East` or `West`.

`LATDEC` and `LONGDEC` (from the source) give a point for every parcel, in decimal degrees.
`INSIDE_X`, `INSIDE_Y`, `SHAPE_Leng` and `SHAPE_Area` are in the state plane system of the parcel's file, so East and
West values are not on the same grid. The polygons are not in the file.

Values are as published: blanks are missing values, whole numbers have no decimal point, other numbers have up to 15
significant digits, and `PLATDATE` is written as `YYYY-MM-DD`. `DEEDDATE` is text, as published (e.g. "7/2/1996").
`ZONING` is filled for 16,930 parcels, all in the West file. UTF-8.

## Owners

`OWNNAME` is blank for 8,160 parcels. Each parcel has two sets of mailing address fields (`MAILADD1`, `MCITY1`,
`MSTATE1`, `MZIP1` and `MAILADD2`, `MCITY2`, `MSTATE2`, `MZIP2`), as published.
