# DC Property Tax

_Built 2026-11-06. The runnable script is
[`code/build.py`](code/build.py)._

DC property tax records come from the Office of Tax and Revenue's [Integrated Tax System Public Extract Facts][itspe]
on DC Open Data: one row per property, with owner names and mailing addresses, the property address, assessed values,
tax type and rate, homestead status and the last sale. The new file, `dc_property_tax_2026.csv`, has 215,770
properties as of July 17, 2026. The earlier edition is `dc_tax_extract_cleaned.csv` (April 2019, 207,459 properties).

[itspe]: https://opendata.dc.gov/datasets/integrated-tax-system-public-extract-facts

## Source

`Integrated_Tax_System_Public_Extract_Facts.csv`, the site's CSV download, retrieved 2026-11-06. It is a copy the
site made on July 17, 2026: every row has `LASTMODIFIEDDATE` 2026/07/17, and the latest `LAST_SALE_DATE` is July 10,
2026. The live service behind the page (`ITSPE_FACTS_05022025/FeatureServer/0`, 215,962 rows on Nov. 5, 2026) has no
bulk download.

## Columns

The file's 37 columns, in its order and with its names, then the five columns the 2019 build added, then three more:

* `site_state` (`DC`) and `site_city` (`Washington`).
* `OWNER_CITY`, `OWNER_STATE` and `OWNER_ZIP`, split from `OWNER_ADDRESS_CITYSTZIP`. When the value ends in a
  two-letter state code and a ZIP, the last word is the ZIP, the word before it the state and the rest the city, so
  "WASHINGTON DC 20001-4524" becomes `WASHINGTON`, `DC` and `20001-4524`. Otherwise the whole value is in
  `OWNER_CITY`: 216 rows, mostly foreign addresses such as "BORDEAUX  33200 FRANCE". 7,794 rows have no
  `OWNER_ADDRESS_CITYSTZIP`.
* `PROPERTY_ADDRESSCITY`, `PROPERTY_STATE` and `PROPERTY_ZIP`, split from `PROPERTY_ADDRESS`, so
  "555 E ST SW WASHINGTON DC 20024" becomes `555 E ST SW WASHINGTON`, `DC` and `20024`. `PROPERTY_STATE` is `DC` in
  every row. The source cuts `PROPERTY_ADDRESS` at 50 characters, so 8,065 values end in a partial ZIP
  ("... WASHINGTON DC 2000") or stop before the state. `PROPERTY_ZIP` is the ZIP after "DC" when at least five digits
  of it are there (the first five when a ZIP+4 is cut short), and blank otherwise: 4,708 rows have no `PROPERTY_ZIP`.
  When "DC" is not in the value, `PROPERTY_ADDRESSCITY` is the whole value.

Since 2019 the source dropped the base-year and phase-in values (`APPRAISED_VALUE_BASEYEAR_LAND`,
`APPRAISED_VALUE_BASEYEAR_BLDG`, `PHASEIN_VALUE_CURRENT_LAND`, `PHASEIN_VALUE_CURRENT_BLDG`), added the proposed values
(`APPRAISED_VALUE_PROPOSED_LAND`, `_IMPR`, `_TOTAL`), and renamed `APPRAISED_VALUE_CURRENT_IMPR` to
`APPRAISED_VALUE_CURRENT_BLDG`. `TAXRATE` is now per $100 (0.85) where in 2019 it was a fraction (0.0085). Dates are
written as published, e.g. "2023/08/10 00:00:00+00". 38,295 rows have no `LAST_SALE_DATE`. 28 rows have no
`OWNER_NAME_PRIMARY`. UTF-8.

## 2019 edition

`dc_tax_extract_cleaned.csv` was built by [`fix_dc_taxes.py`](fix_dc_taxes.py) from the same extract, downloaded in
April 2019. In that file the city and the state in `OWNER_ADDRESS_CITYSTZIP` were separated by a run of spaces, and
the script split on it.
