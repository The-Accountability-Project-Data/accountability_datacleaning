# Oregon Contributions

The Accountability Project's Oregon campaign contributions come from [ORESTAR][orestar], the Oregon Secretary of
State's campaign finance system. The dataset has four files:

| File | Transaction dates | Rows |
|---|---|---|
| `OR_contributions_2002_2010.csv` | 2002-2010 | 284,722 |
| `OR_contributions_2011_2014.csv` | 2011-2014 | 320,181 |
| `OR_contributions_20150101-20180715.csv` | 2015-01-01 to 2018-07-15 | 322,705 |
| `OR_contributions_20180716-20261104.csv` | 2018-07-16 to 2026-11-04 | 1,054,007 |

Each record is one transaction of sub type Cash Contribution, In-Kind Contribution, or Return or Refund of
Contribution. `docs/or_contribs_diary.Rmd` is a separate 2022 build (transactions Jan. 1, 2015 to Nov. 12, 2022)
that is not one of these files.

[orestar]: https://sos.oregon.gov/elections/Pages/orestar.aspx

## Update: November 2026

_Updated 2026-11-06. The runnable script is [`code/or_contribs_2026.R`](code/or_contribs_2026.R)._

The three earlier files are unchanged; `OR_contributions_20150101-20180715.csv` was named
`OR_contributions_2015_2018.csv` until 2026-11-06. The new file, `OR_contributions_20180716-20261104.csv`, starts
the day after the last transaction date in them.

**Source.** ORESTAR's [public transaction search][search], exported by filed date for every day from 2018-07-16 to
2026-11-04, with deleted and superseded versions included ("all versions"), retrieved 2026-11-04 to 2026-11-06. Days
with 5,000 or more rows were exported in amount ranges. The exports cover 1,676,382 transaction versions.

[search]: https://secure.sos.state.or.us/orestar/gotoPublicTransactionSearch.do

**Current versions.** Versions of one transaction share an `original_id`:

1. Each `tran_id` is taken from its newest export.
2. Of the versions of a transaction, the one filed last is kept (ties: the highest `tran_id`).
3. Transactions whose kept version is deleted (5,405) or marked expired, "Original \*" or "Amended \*" (1,097),
   are left out. 46,783 superseded versions are left out.

This leaves 1,615,722 transactions dated 2018-07-16 to 2026-11-04, of every type.

**Contributions.** The file keeps the three sub types in the earlier files:

| Sub type | Rows |
|---|---|
| Cash Contribution | 1,009,571 |
| In-Kind Contribution | 39,607 |
| Return or Refund of Contribution | 4,829 |

By transaction year: 2018 (from July 16) 96,620; 2019 84,270; 2020 136,333; 2021 92,101; 2022 148,517;
2023 93,667; 2024 143,925; 2025 112,647; 2026 (through Nov. 4) 145,927. No `tran_id` or `original_id` is also in
`OR_contributions_20150101-20180715.csv`.

**Columns.** The earlier files' 44 columns, in their order, then `country` and `foreign_postal_code`, which the
export now has. Values are as published:

* The export has no Agent Name column; `agent_name` is blank.
* `tran_status` is `Original` or `Amended`; the earlier files have `O` and `A`.
* `attest_date`, `filed_date`, `due_date` and the other dates are MM/DD/YYYY; the earlier files have spreadsheet
  serial numbers for the dates other than `tran_date`.

**Encoding.** windows-1252, as in the earlier files. One character windows-1252 cannot encode (U+0090, in the
contributor name of transaction 3790662) is written as `?`.

Transactions dated through 2018-07-15 that were filed or amended after the earlier files were made are not in any
file.
