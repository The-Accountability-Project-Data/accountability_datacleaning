# Oregon Expenditures

_Built 2026-11-06. The runnable script is [`code/or_expends_2026.R`](code/or_expends_2026.R)._

Oregon campaign expenditures come from [ORESTAR][orestar], the Oregon Secretary of State's campaign finance system.
The dataset has one file, `OR_expenditures_2018_2026.csv`: 468,172 transactions dated 2018-07-16 to 2026-11-04.

[orestar]: https://sos.oregon.gov/elections/Pages/orestar.aspx

**Source.** The same exports and current versions as the 2018-2026 file of Oregon contributions; see
[`../contribs/README.md`](../contribs/README.md). ORESTAR's [public transaction search][search] was exported by
filed date for every day from 2018-07-16 to 2026-11-04, with deleted and superseded versions included, retrieved
2026-11-04 to 2026-11-06. Of the versions of each transaction, the one filed last is kept; transactions whose last
version is deleted or expired are left out. This leaves 1,615,722 transactions of every type.

[search]: https://secure.sos.state.or.us/orestar/gotoPublicTransactionSearch.do

**Expenditures.** The file keeps the sub types of ORESTAR's Expenditure transaction type, from the
[ORESTAR User's Manual: Transaction Filing][manual], p. 32:

| Sub type | Rows |
|---|---|
| Cash Expenditure | 423,611 |
| Personal Expenditure for Reimbursement | 36,970 |
| Account Payable | 6,673 |
| Loan Payment (Non-Exempt) | 918 |

[manual]: https://sos.oregon.gov/elections/documents/orestartransfiling.pdf

Sub types of other types, such as Return or Refund of Contribution and Miscellaneous Other Disbursement, are not in
the file.

By transaction year: 2018 (from July 16) 38,777; 2019 34,550; 2020 67,367; 2021 35,701; 2022 75,837; 2023 37,999;
2024 74,715; 2025 38,146; 2026 (through Nov. 4) 65,080.

**Columns.** The same 46 columns as the Oregon contributions files: ORESTAR's export columns with snake-case names,
plus `agent_name`, which is blank (the export has no Agent Name column). The filer (`filer`, `filer_id`) is the
committee that spent the money; `contributor_payee` is the payee, filled in every row. The address columns
(`addr_line1`, `city`, `state`, `zip`) are the payee's; 363,178 rows have a street or city. For a Personal
Expenditure for Reimbursement, `payer_personal_expend` is the person who paid and is reimbursed (filled in 23,616
of 36,970). Values are as published. UTF-8.
