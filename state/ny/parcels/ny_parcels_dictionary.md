# New York Parcels 2026: data dictionary

Columns of `ny_parcels_2025.csv`, in file order. Definitions are from the state's metadata,
[NYS 2025 Statewide Tax Parcel Centroid Points](https://gis.ny.gov/current-parcel-centroid-metadata) (publication date
May 2026), except where a row says otherwise. Assessment terms are explained in the
[ORPTS Assessor's Manuals](https://www.tax.ny.gov/research/property/assess/manuals/assersmanual.htm). New York City
parcels come from [MapPLUTO](https://www.nyc.gov/content/planning/pages/resources/datasets/mappluto-pluto-change).

Each parcel has one row for its primary owner and, when the roll lists an additional owner, a second row for that owner.
The two rows are the same except for `OWNER` and the mailing-address columns.

## Columns 1–40 (same as `ny_parcels_2018.csv`)

| # | Column | Meaning |
|---:|---|---|
| 1 | STATE | "NY" on every row (added by the build) |
| 2 | COUNTY_NAME | Parcel location county |
| 3 | MUNI_NAME | Parcel location municipality (city, town or village), or NYC borough |
| 4 | PARCEL_ADDR | Physical address of the parcel: building number and street name |
| 5 | CITYTOWN_NAME | City or town where the parcel is located (excludes villages) |
| 6 | LOC_ST_NBR | Parcel location street number |
| 7 | LOC_STREET | Parcel location street, with pre-direction, name, post-direction and suffix |
| 8 | LOC_UNIT | Parcel location unit number |
| 9 | LOC_ZIP | Parcel location ZIP code |
| 10 | PROP_CLASS | Property class: 3-digit [NYS property class code](https://www.tax.ny.gov/research/property/assess/manuals/prclas.htm); in NYC, the 2-digit PLUTO land use code |
| 11 | ROLL_SECTION | Part of the assessment roll: 1 taxable, 3 taxable state land, 5 special franchise, 6 utility, 7 ceiling railroad, 8 wholly exempt |
| 12 | LAND_AV | Assessed land value |
| 13 | TOTAL_AV | Assessed total value |
| 14 | FULL_MARKET_VAL | Full market value |
| 15 | YR_BLT | Year built |
| 16 | FRONT | Width of the parcel |
| 17 | DEPTH | Depth of the parcel |
| 18 | SQ_FT | Assessed area, square feet |
| 19 | ACRES | Assessed area, acres |
| 20 | SCHOOL_NAME | School district of the parcel |
| 21 | BLDG_STYLE_DESC | Building style (residential); in NYC, the building class |
| 22 | SQFT_LIVING | Living area, square feet (residential) |
| 23 | NBR_KITCHENS | Number of kitchens (residential) |
| 24 | NBR_FULL_BATHS | Number of full baths (residential) |
| 25 | NBR_BEDROOMS | Number of bedrooms (residential) |
| 26 | USED_AS_DESC | Primary commercial use |
| 27 | BOOK | Deed book (only for parcels sold in the last 10–12 years) |
| 28 | PAGE | Deed page (only for parcels sold in the last 10–12 years) |
| 29 | GRID_EAST | Easting coordinate of the parcel, State Plane |
| 30 | GRID_NORTH | Northing coordinate of the parcel, State Plane |
| 31 | MUNI_PARCEL_ID | CITYTOWN_SWIS joined to the ORPTS parcel ID; links to other ORPTS data |
| 32 | ROLL_YR | Tax year of the assessment roll (2025 on every row) |
| 33 | OWNER_TYPE | 1 federal, 2 state, 3 county, 4 city, 5 town, 6 village, 7 mixed government, 8 private, 9 public school district or BOCES, 10 road right of way, 11 water, -999 unknown |
| 34 | CALC_ACRES | GIS-calculated acres of the parcel (inflated where DUP_GEO is "Y") |
| 35 | OWNER | Owner: the state's PRIMARY_OWNER on a parcel's first row, ADD_OWNER on its second row |
| 36 | MAIL_ADDR | Owner's mailing address: MAIL_ADDR on the first row, ADD_MAIL_ADDR on the second |
| 37 | PO_BOX | Owner's mailing PO box: PO_BOX or ADD_MAIL_PO_BOX |
| 38 | MAIL_CITY | Owner's mailing city: MAIL_CITY or ADD_MAIL_CITY |
| 39 | MAIL_STATE | Owner's mailing state: MAIL_STATE or ADD_MAIL_STATE |
| 40 | MAIL_ZIP | Owner's mailing ZIP: MAIL_ZIP or ADD_MAIL_ZIP |

NYC parcels have no mailing address.

## Columns 41–67 (new in 2026)

| # | Column | Meaning |
|---:|---|---|
| 41 | SWIS | 6-digit code for the parcel's city, town, village or part of one |
| 42 | PRINT_KEY | Formatted section-block-lot ID |
| 43 | SBL | Section-block-lot ID |
| 44 | CITYTOWN_SWIS | 6-digit code for the parcel's city or town, excluding villages |
| 45 | SCHOOL_CODE | ORPTS school district code |
| 46 | SEWER_TYPE | Sewer type code |
| 47 | SEWER_DESC | Sewer type |
| 48 | WATER_SUPPLY | Water supply code |
| 49 | WATER_DESC | Water supply |
| 50 | UTILITIES | Utilities code |
| 51 | UTILITIES_DESC | Utilities |
| 52 | BLDG_STYLE | Building style code (residential); in NYC, the 2-digit building class code |
| 53 | HEAT_TYPE | Heat type code (residential) |
| 54 | HEAT_TYPE_DESC | Heat type (residential) |
| 55 | FUEL_TYPE | Fuel type code (residential) |
| 56 | FUEL_TYPE_DESC | Fuel type (residential) |
| 57 | GFA | Gross floor area of a commercial building, all floors except the basement |
| 58 | USED_AS_CODE | Primary commercial use code |
| 59 | AG_DIST_CODE | Agricultural district code |
| 60 | AG_DIST_NAME | Agricultural district |
| 61 | SWIS_SBL_ID | SWIS joined to SBL; unique per parcel |
| 62 | SWIS_PRINT_KEY_ID | SWIS joined to PRINT_KEY; unique per parcel |
| 63 | SPATIAL_YR | Year of the parcel polygon |
| 64 | NYS_NAME | For state-owned parcels (OWNER_TYPE 2), the agency that owns or occupies it |
| 65 | NYS_NAME_SOURCE | How the state agency was determined: code X-Y-ZZ-y (owner-name match, verifying-dataset match, single/multiple/no agency, verifying dataset), explained in the metadata |
| 66 | DUP_GEO | "Y" where the parcel polygon is shared by several assessment records (for example condominium units) |
| 67 | ORIG_FID | Row number of the parcel in the state's layer (not described in the metadata) |

## Code tables

The state's geodatabase also holds lookup tables: NYS_Property_Class_Codes (PROP_CLASS), NYC_LandUse_Codes and
NYC_BldgClass_Codes (NYC's PROP_CLASS and BLDG_STYLE), SWIS_Muni_Codes (SWIS) and NYS_Name_Source_Table
(NYS_NAME_SOURCE).
