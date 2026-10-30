# Federal prime contracts and grants (USAspending)

TAP datasets 375, **Federal Prime Contracts**, and 377, **Federal Prime Grants**: prime award transactions from
<https://www.usaspending.gov/>. Updated October 2026. The sub-award datasets (374, 376) were not updated.

## Files

One set of files per federal fiscal year (Oct. 1 to Sept. 30), split into parts of up to 1,000,000 rows:
`us_contract-prime_<FY>-<n>.csv` (375) and `us_assist-prime_<FY>-<n>.csv` (377).

* FY2001–FY2020 are the files built in 2021, unchanged.
* FY2021–FY2026 were rebuilt in October 2026. They replace the partial FY2021 files and the date-range update files
  (`_20210318-20210607` through `_20220405-20230104`), which are moved to `csv_archive/` on S3.

| FY | Prime grants (377) | Parts | Prime contracts (375) | Parts |
|---|---:|---:|---:|---:|
| 2021 | 20,637,065 | 21 | 6,405,488 | 7 |
| 2022 | 8,811,266 | 9 | 6,668,009 | 7 |
| 2023 | 6,176,269 | 7 | 6,693,769 | 7 |
| 2024 | 5,195,615 | 6 | 6,692,741 | 7 |
| 2025 | 6,439,162 | 7 | 6,639,176 | 7 |
| 2026 | 4,491,868 | 5 | 4,705,099 | 5 |

FY2026 grants cover action dates through Sept. 30, 2026. FY2026 contracts cover action dates through Sept. 4, 2026:
the archive file is dated Sept. 6, and Defense Department contracts are published with a 90-day delay.

## Source

USAspending's pre-generated archive files, one per fiscal year and award family, listed by
`POST https://api.usaspending.gov/api/v2/bulk_download/list_monthly_files/` and downloaded from
`https://files.usaspending.gov/award_data_archive/FY<year>_All_<Assistance|Contracts>_Full_<date>.zip`. The files
used are dated Sept. 6–7, 2026.

## Columns

The FY2021–FY2026 files have the columns of the 2021 files, in the same order ([`spend_cols.csv`](spend_cols.csv)),
with `recipient_uei` and `recipient_parent_uei` appended: 97 columns for grants, 284 for contracts.

* Columns USAspending renamed are given their old names (the COVID-19 amount columns,
  `prime_award_base_transaction_description` as `award_description`).
* Columns USAspending added since 2021, other than the UEIs, are dropped.
* Columns USAspending no longer publishes are left blank: the county codes and congressional districts of the
  recipient and the place of performance.
* Values are as published.

The year shown in search is the calendar year of `action_date`. FY2001–FY2020 rows indexed before October 2026
show the fiscal year.

## Code

[`spend_history.R`](spend_history.R), revised October 2026; its header lists the changes.

```
Rscript --vanilla national/omb_spending/spend_history.R <first FY> <last FY> <assistance|contracts>
```

With `assistance` or `contracts` it downloads the archive file for each fiscal year, unzips it, aligns the
columns, and writes `data/clean/us_<type>-prime_<FY>-<n>.csv`. It appends the file names to
[`spend_names.csv`](spend_names.csv) and a row per file to `data/spend_check.csv` (rows, columns, action-date
range). Without the third argument, it requests a bulk download from the API instead; in October 2026 those requests
failed, for a full year and for one month. FY2021, FY2022 and all contract years were run on an EC2 box in
us-east-1; the other grant years were run locally. [`spend_update.R`](spend_update.R) is the 2021 script for
date-range updates and was not used.

## Updating

Run `spend_history.R` for the current fiscal year and replace its files. Run contracts for a fiscal year again 90
days after it ends to pick up Defense Department contracts.
