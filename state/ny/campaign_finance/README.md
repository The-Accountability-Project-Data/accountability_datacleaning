# New York Campaign Contributions and Expenditures

_Built 2026-11-10. The runnable script is
[`code/build.py`](code/build.py); [`code/profile.py`](code/profile.py) profiles the source files. The 2021 builds are
in [`../contribs`](../contribs) and [`../expends`](../expends)._

The data comes from the [Public Reporting System][dl] of the New York State Board of Elections: every disclosure report
filed by state and county candidates and committees from 1999 through November 2026.

[dl]: https://publicreporting.elections.ny.gov/DownloadCampaignFinanceData/DownloadCampaignFinanceData

## Source

Five files were downloaded on 2026-11-10: the four Disclosure Report
files for all years (State Candidate, State Committee, County Candidate, County Committee) and the Filer Data file.

| File | Rows |
|:--|--:|
| `STATE_CANDIDATE.csv` | 21,250 |
| `STATE_COMMITTEE.csv` | 12,178,813 |
| `COUNTY_CANDIDATE.csv` | 57,190 |
| `COUNTY_COMMITTEE.csv` | 6,454,827 |
| `COMMCAND.CSV` (filers) | 64,810 |

The disclosure files have no header row and 59 columns. Each zip's `FileFormatReference.pdf` lists 56 of them; the
others are `FILER_PREVIOUS_ID`, `ELECTION_TYPE` and `COUNTY_DESC` (positions 2, 5 and 6, named as in the 2021 build) and a
59th column that is not in the reference, named `COLUMN_59`; it is blank except for about 1,500 values of Y, N or a
space. The lines are ASCII except 1,495 in Windows-1252; each line is read as UTF-8, else as Windows-1252.

## Records

Contributions (`ny_contribs_1999-2026.csv`, 13,197,456 rows) are the rows of schedules A through E: monetary
contributions from individuals and partnerships, from corporations and from all other contributors, in-kind
contributions, and other receipts. Expenditures (`ny_expends_1999-2026.csv`, 4,274,641 rows) are the rows of schedule F.
The other schedules (1,239,983 rows: loans, transfers, liabilities and others) are not included.

The files hold one version of each report; `R_AMEND` is Y for a report that has been amended. `TRANS_NUMBER` is unique
only within a filer. 3,206 groups of rows are identical in every column. 175 contributions and 231 expenditures have no
`SCHED_DATE`, and a few hundred have dates before 1999 or after 2026.

## Columns

The 59 disclosure columns as published, with surrounding spaces removed; `SOURCE_FILE`, the disclosure file of the row;
then the filer's record from `COMMCAND.CSV`, joined on `FILER_ID` (every row has one): `FILER_NAME`,
`FILER_COMPLIANCE_TYPE_DESC`, `FILER_TYPE_DESC`, `FILER_STATUS`, `FILER_COMMITTEE_TYPE_DESC`, `FILER_OFFICE_DESC`,
`FILER_DISTRICT`, `FILER_COUNTY_DESC`, `FILER_MUNICIPALITY_DESC`, and the treasurer's name and address
(`TREASURER_FIRST_NAME` through `TREASURER_ZIPCODE`). UTF-8.

The contributor or payee is in `FLNG_ENT_NAME` (organizations) or `FLNG_ENT_FIRST_NAME`, `FLNG_ENT_MIDDLE_NAME` and
`FLNG_ENT_LAST_NAME` (individuals), with the address in `FLNG_ENT_ADD1`, `FLNG_ENT_CITY`, `FLNG_ENT_STATE` and
`FLNG_ENT_ZIP`. The amount is `ORG_AMT` and the date `SCHED_DATE`. `EMPLOYER` and `EMP_OCCUPATION` are filled for about
4% of State Committee contributions.
