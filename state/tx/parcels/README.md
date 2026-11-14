# Texas Parcels

_Built 2026-11-09; address columns added 2026-11-10. The scripts are [`code/build.py`](code/build.py), which writes `tx_parcels_2026_base.csv`, and
[`code/address_columns.py`](code/address_columns.py), which writes `tx_parcels_2026.csv` from it._

Texas parcels come from [StratMap Land Parcels][stratmap], published by the Texas Geographic Information Office
(TxGIO). Each county's appraisal district, or its vendor, sends its parcel map and appraisal roll; TxGIO puts them in a
common schema without changing the values. The file `tx_parcels_2026.csv` is StratMap 2026 (published Oct. 1, 2026):
14,279,876 parcels in 253 of the state's 254 counties, all with `TAX_YEAR` 2026. Donley County is not in it. It is the
first Texas parcels dataset.

[stratmap]: https://www.geographic.texas.gov/stratmap/land-parcels.html

## Source

`stratmap26-landparcels_48_lp.zip`, the statewide file geodatabase, downloaded 2026-11-09 from
`https://data.geographic.texas.gov/1d33dafb-6e9c-40ac-887d-f4577909ed9b/resources/` (2,714,287,962 bytes, CC0). It holds
one feature class, `stratmap_2026_land_parcels_48`: 14,279,876 parcel polygons in Web Mercator (EPSG:3857), with 36
attribute fields. The fields are defined in the [TxGIO land parcel schema][schema].

[schema]: https://www.geographic.texas.gov/_uploads/TxGIO-land-parcel-schema.pdf

TxGIO also publishes a file for each county, with the same records, owners, addresses, values and polygons
([`code/compare_county_state.py`](code/compare_county_state.py)). In the statewide file, `GIS_AREA_UNIT`,
`LGL_AREA_UNIT`, `LOC_LAND_USE` and `STAT_LAND_USE` are blank in every row, and `YEAR_BUILT` values that list several
years are cut short (Kenedy's "82,1982" is "82,1"). Hunt County has 70,343 parcels in the statewide file and 70,341 in
its county file. This dataset uses the statewide file.

## Columns

The layer's 36 attribute fields, in its order and with its names, then:

* `LATITUDE` and `LONGITUDE`: the centroid of each parcel polygon, computed in Texas Centric Albers Equal Area
  (EPSG:3083) and converted to WGS 84, to 6 decimal places. Every parcel has one. The polygons are not in the file.
* `site_state`: TX on every row. `SITUS_STAT` is blank for 18% of parcels, including all of Bexar County.
* `SITE_STREET`, `SITE_CITY`, `SITE_ZIP`: the property address in separate parts. Counties fill the situs fields
  differently: some fill the parts (`SITUS_NUM`, `SITUS_STRE`, `SITUS_ST_1`, `SITUS_ST_2`), others only the whole
  address in `SITUS_ADDR` ("802 ORCHARD ST, CEDAR PARK, TX 78613", "22818 BLACK CHERRY ELMENDORF, TX 78112", "4612
  BAYONNE CT"). `SITE_STREET` is the four parts joined with spaces; when all four are blank, it is the text of
  `SITUS_ADDR` before the first comma (2,294,655 parcels, most of them in Tarrant, Bexar, Hidalgo and Williamson
  counties). `SITE_CITY` is `SITUS_CITY`; when that is blank, the text of `SITUS_ADDR` after the first comma, without
  TX and the ZIP. When only the state and ZIP follow the comma, a city name at the end of the street is moved to
  `SITE_CITY`: a city seen at least 20 times in the county's `SITUS_CITY` or 50 times in its Texas mailing cities, or
  a Texas city seen at least 500 times statewide when the street left ends in a street type or a road number.
  `SITE_ZIP` is `SITUS_ZIP` when it has 5 digits, otherwise a ZIP at the end of `SITUS_ADDR`. Filled: street 90.6%,
  city 64.8%, ZIP 67.3%. Tarrant County's `SITUS_ADDR` has no city or ZIP.
* `MAIL_CITY_PARSED`, `MAIL_STATE_PARSED`: the mailing city and state. Tarrant County writes the state in `MAIL_CITY`
  ("FORT WORTH, TX") and the first two letters of the city in `MAIL_STAT`; Dallas County writes "TE" in `MAIL_STAT`
  and the full state name in `MAIL_ADDR` ("ROWLETT, TEXAS 750898805, UNITED STATES OF AMERICA").
  `MAIL_CITY_PARSED` is `MAIL_CITY` without a trailing ", XX" state. `MAIL_STATE_PARSED` is that state; else the full
  state name before the ZIP in `MAIL_ADDR`; else `MAIL_STAT` when it is a U.S. state, territory or military
  abbreviation; else blank. It differs from `MAIL_STAT` for 1,394,086 parcels and is filled for 94.6%.

The 64,037 parcels with no `PROP_ID` and no `OWNER_NAME` are written at the end of the file.

Values are as published: blanks are missing values, whole numbers have no decimal point, other numbers have up to 15
significant digits, and `DATE_ACQ` is written as `YYYY-MM-DD`. UTF-8.

Rows, tax years and blank owners by county are in [`tx_parcels_2026_counties.tsv`](tx_parcels_2026_counties.tsv).

## Owners

`OWNER_NAME` is filled for 96.3% of parcels. Counts of owner names, mailing streets, mailing cities and property
streets for each county file are in
[`tx_parcels_2026_county_files_owners.tsv`](tx_parcels_2026_county_files_owners.tsv)
([`code/owner_counts.py`](code/owner_counts.py)). 49 counties have an owner name for at least 99% of parcels and 163 for
90% to 99%. Smith County has no owner names. Motley (39%) and Frio (48%) have owner names for fewer than half.

63,383 parcels have no `PROP_ID`, `GEO_ID` or owner, most of them in Floyd (6,026), Dimmit (5,871), Motley (4,938),
Montague, Parker and Erath counties.

## Earlier work

[`download_texas_fips.py`](download_texas_fips.py) downloaded selected county files of the 2019 edition (StratMap 2019
Land Parcels). Its notes say Dallas and Travis counties provided no meaningful ownership data in 2019. In the 2026
edition, Dallas has owner names for 92.4% of parcels and Travis for 98.2%.
Single-county files from that work, for the largest counties found then with owner names, are kept as they are:
`Harris_TX_parcels.csv` and `Tarrant_TX_parcels.csv` (2019) and `travis_co_tx_parcels.csv` (2020).
