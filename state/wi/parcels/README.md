# Wisconsin Parcels

_Built 2026-11-06. The script is
[`code/build.py`](code/build.py)._

Wisconsin parcels come from the [Statewide Parcel Map Initiative][sco], run by the Department of Administration and the
State Cartographer's Office, which collects every county's parcel and tax roll data each year in a standard schema. The
file `wi_parcels_2025.csv` is the V12 (2026) statewide database: 3,574,646 parcels in all 72 counties, almost all
from the 2025 tax roll. It is the first Wisconsin parcels dataset.

[sco]: https://www.sco.wisc.edu/parcels/data/

## Source

`V12.0.0_Wisconsin_Parcels_2026_10.3_Uncompressed.zip`, downloaded 2026-11-06 from
`https://web.s3.wisc.edu/parcels/v12_parcels/V12.0.0_Wisconsin_Parcels_2026_10.3_Uncompressed.zip` (759,926,092 bytes,
Last-Modified 2026-06-30, sha256 `b22bfaad...`). It holds one feature class, `V1200_WisconsinParcels_2026`: 3,574,646
parcel polygons with 45 attribute fields. The fields are defined in the
[V12 schema documentation][schema]. The compressed version of the file is in Esri's compressed geodatabase format.

[schema]: https://www.sco.wisc.edu/parcels/data/assets/V12/V12_Wisconsin_Statewide_Parcels_Schema_Documentation.pdf

`TAXROLLYEAR` is 2025 for 3,510,241 parcels, 2026 for 25,801, 2027 for 537, 2024 for 211 and 2021 for 21, and blank for
37,833. Rows, tax roll years and missing owners by county are in
[`wi_parcels_2025_counties.tsv`](wi_parcels_2025_counties.tsv). Counties range from Menominee (4,514) to Milwaukee
(280,676). One parcel has `CONAME` "MENOMONIE", as published.

## Columns

The 45 attribute fields of the feature class, in its order and with its names, then three columns split from the owner's mailing address. They include the parcel IDs, owner
names (`OWNERNME1`, `OWNERNME2`), the owner's mailing address in one field (`PSTLADRESS`), the site address in full
and in parts, the municipality (`PLACENAME`), school district, assessed, land, improvement and estimated market
values, net and gross property tax, property class, acres, county and load date. `LATITUDE` and `LONGITUDE` are
fields of the layer: a point for each parcel, in WGS 84. 8,268 parcels have no point. The polygons are not in the
file.

Then `OWNER_ADDRESSCITY`, `OWNER_STATE` and `OWNER_ZIP`, split from `PSTLADRESS`, which holds the owner's whole mailing
address: "2020 CHAMBERLAIN AVE , MADISON, WI 53726" becomes `2020 CHAMBERLAIN AVE , MADISON`, `WI` and `53726`. A value
is split when it ends in a US state or territory code and a ZIP, with or without commas between them ("PO BOX 360, EAU
CLAIRE, WI, 54702"). 3,443,942 values are split. The other 3,801, mostly foreign addresses, are in `OWNER_ADDRESSCITY`
whole, with `OWNER_STATE` and `OWNER_ZIP` blank. `PSTLADRESS` is blank for 126,903 parcels. The site address is already
in separate fields (`SITEADRESS`, `PLACENAME`, `ZIPCODE`, `STATE`).

Values are as published: blanks are missing values, whole numbers have no decimal point, and other numbers have up to
15 significant digits. UTF-8.

## Owners

`OWNERNME1` is "NOT AVAILABLE" for 90,652 parcels, as published: 64,144 of Kenosha County's 68,499 parcels and 25,034
of Dane County's 218,857, plus a few hundred in other counties. It is blank for 59,681. `PSTLADRESS` is blank or "NOT
AVAILABLE" for 126,903 parcels.
