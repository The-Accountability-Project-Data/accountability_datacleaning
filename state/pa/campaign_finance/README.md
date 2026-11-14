# Pennsylvania Campaign Contributions and Expenditures, 2023-2026

_Built 2026-11-10. The runnable script is
[`code/pa_append_2023_2026.R`](code/pa_append_2023_2026.R); [`code/fetch.sh`](code/fetch.sh) downloads the source files.
The 2000-2022 files were built in 2023: [`../contribs`](../contribs) and [`../expends`](../expends)._

The Pennsylvania datasets have two files each: the 2000-2022 file built in 2023 (`pa_contribs_clean.csv`,
`pa_expends_clean.csv`) and a 2023-2026 file built from the Department of State's current exports
(`pa_contribs_2023-2026.csv`, `pa_expends_2023-2026.csv`). The 2023-2026 files have the same columns as the earlier ones.

## Source

The Department of State publishes a [full export][page] for each year from 2000 to 2026, a zip of five comma-separated
files (filer, contribution, expense, debt and receipt) described in `readme-cf-data.txt`. The 2023 to 2026 zips were
downloaded on 2026-11-10. In these exports, the `ADDRESS1` and `ADDRESS2` columns are blank in all but 15 rows (8 contributions, 7 expenses);
city, state and ZIP code are filled. The 2000-2022 files built in 2023 have street addresses and were not rebuilt.

[page]: https://www.pa.gov/agencies/dos/resources/voting-and-elections-resources/campaign-finance-data

## Records

Each filer file row is a report, identified by `CampaignfinanceID`; contribution and expense rows carry the ID of their
report. A filer can file more than one report for the same year (`EYEAR`) and cycle (`CYCLE`); only the latest
(`SubmittedDate`, then the highest ID) is kept, and the contributions and expenses of the earlier ones are dropped. Report
432861 is listed in both the 2025 and 2026 filer files with different years; reports are matched on ID and year.

| | Source rows | Kept |
|:--|--:|--:|
| Reports | 41,363 | 41,094 |
| Contributions | 4,322,240 | 4,292,886 |
| Expenses | 850,781 | 843,974 |

Expenses dated 2025 include 378,626 Stripe and ActBlue processing fees itemized by one filer (20250112).

## Columns

The columns of the 2000-2022 files: the contribution or expense fields from the export, the filer fields from the
row's report, `na_flag` (a missing name, date, amount or filer), `dupe_flag` (contributions only, rows identical to
another), `year` (from the contribution or expense date), and city, ZIP and address columns normalized with the
`campfin` package. Dates are written as `YYYY-MM-DD`. Source lines are read as Windows-1252; the files are UTF-8.
