# Wyoming Parcels

_Built 2026-11-09. The script is
[`code/build.py`](code/build.py)._

Wyoming property records come from the [assessment data download][wy] of the Wyoming Department of Revenue's Property
Tax Division, which holds the county assessors' 2026 tax roll for all 23 counties. The file `wy_parcels_2026.csv` has
400,023 owner records on 373,406 accounts. It is the first Wyoming parcels dataset.

[wy]: https://wyo-prop-div.wyo.gov/assessment-data-download

## Source

The download, retrieved 2026-11-09, unzips to an Access database, `data.mdb` (1,498,537,984 bytes, sha256
`bba3dbee...`), read with [mdbtools](https://github.com/mdbtools/mdbtools). Every table has `TAXYEAR` 2026. The tables
join on `JURISDICTION` (the county) and `ACCOUNTNO`:

* `ACCOUNT`: 373,415 accounts, with the parcel number, account type, actual and assessed values, legal description,
  subdivision, lot and block.
* `OWNER`: 400,023 owners, with names (`NAME1`, `NAME2`) and the owner's mailing address in parts.
* `PROPERTYADDRESS`: 384,670 site addresses; some accounts have more than one, numbered by `ORDERNO`.
* `ACCOUNTABSTVALUE`, `IMPROVEMENT`, `IMPROVEMENTBLTAS`, `IMPROVEMENTDETAIL`, `ACCOUNTDOCUMENTS` and `DOCUMENTS`: values
  by class, building details and recorded documents. These are not in the file.

Owner rows, accounts, blank names and redacted owners by county are in
[`wy_parcels_2026_counties.tsv`](wy_parcels_2026_counties.tsv). Counties range from Niobrara (2,910 owner rows) to
Laramie (70,717).

## Columns

One row per owner:

* `OWNER`'s 16 columns, in its order and with its names.
* `ACCOUNT`'s columns, except `JURISDICTION`, `ACCOUNTNO`, `TAXYEAR` and `PARCELNO`, which are the same as the owner's.
* `PROPERTYADDRESS`'s columns, except those four, from the account's site address with the lowest `ORDERNO` (1 for all
  but 66 accounts). 12,099 owner rows are on accounts with no site address.
* `PROPERTYADDRESS_COUNT`: the account's number of site addresses.
* `site_state`: `WY`. The source has no property state.

Nine accounts have no owner and are not in the file. Values are as published, as mdbtools writes them. UTF-8.

`ACCTTYPE` is Residential for 228,780 rows, then Res Vacant Land (43,596), Agricultural (39,972), Mobile Home (32,727),
Commercial (22,777), Personal (16,400), Oil & Gas (5,418) and smaller types.

## Owners

26,613 rows are additional owners (`PRIMARYOWNERFLAG` 0) of an account. 20 owners are marked private (`PRIVATEFLAG` 1)
and named "OWNER NAME REDACTED", with no mailing address. `NAME1` is blank for 19 rows and `MAILADDRESS1` for 26,446.
