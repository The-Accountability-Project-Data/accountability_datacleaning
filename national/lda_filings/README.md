# Federal lobbying (LDA)

Six TAP datasets come from the Lobbying Disclosure Act filings, now published by <https://lda.gov/api/v1/>
(it replaced `lda.senate.gov`, sunset July 31, 2026). Updated October 2026.

| Dataset | Title | File prefix | One row per |
|---|---|---|---|
| 414 | Federal lobbying clients | `lda_client-firm` | filing (registrant, client, income or expenses) |
| 424 | Federal lobbyist work | `lda_firm-lobbyist` | filing × lobbyist, issues collapsed |
| 422 | Federal lobbying affiliates | `lda_client-affiliate` | filing × affiliated organization |
| 427 | Federal lobbying foreign entities | `lda_client-foreign` | filing × foreign entity |
| 426 | Federal lobbyist convictions | `lda_convict-lobbyist` | filing × conviction disclosure |
| 2 | Lobbyist contributions (LD-203) | `lda_contributions` | contribution item |

## Files

**Filings (414, 422, 424, 426, 427).** The earlier files stay as they were: a full history (`lda_<table>.csv`) and
two updates by posting date (`_20211029-20220404`, `_20220405-20230111`). Added in October 2026, per table:

* `lda_<table>_2022_posted-after-20230111.csv`: 2022 filings posted after Jan. 11, 2023 (21,958 filings; the 157
  posted on Jan. 11 are in the earlier update file and are left out);
* `lda_<table>_<year>.csv` for filing years 2023–2026. 2023 leaves out the 39 filings already in the Jan. 2023 update
  file (95,270 filings). 2024: 96,945; 2025: 109,046; 2026: 58,134 (as of Oct. 7, 2026).

Every file of a table has the same columns, in the order of the Jan. 2023 files (46, 17, 20, 12 and 15 columns).

**Contributions (2).** `lda_contributions_<year>.csv` for 2019–2026, from the API's `contributions` endpoint. 2019
replaces the House XML file for that year (46 rows); the House XML files for earlier years stay as they were. One row per contribution item, only for
reports that list contributions:

| Year | Reports | Items |
|---|---:|---:|
| 2019 | 35,381 | 164,951 |
| 2020 | 35,165 | 165,446 |
| 2021 | 36,166 | 125,225 |
| 2022 | 38,493 | 167,314 |
| 2023 | 38,906 | 149,693 |
| 2024 | 38,883 | 170,784 |
| 2025 | 40,496 | 151,554 |
| 2026 | 19,365 | 89,604 |

The first 22 columns keep the House XML files' names; 12 API fields follow (34 columns). Some values differ in form
from the XML files: `filenum` is the filing UUID, `filerType` is "Lobbyist" or "Organization", `signedDate` is the
posting time in UTC, and `date` is MM/DD/YYYY. The header of `parse_lda_contributions.R` lists every difference.

## Code

Run in this order, from the repository root (R):

1. [`scrape_lda_filings.R`](scrape_lda_filings.R) `filings|contributions <year> ...`: pages the API one filing year
   at a time and saves each page as JSON. It needs an API key in `LDA_API_KEY`
   (register at <https://lda.gov/api/register/>), waits between requests and can resume.
   `LDA_POSTED_AFTER=yyyy-mm-dd` limits it to filings posted after a date.
2. [`parse_lda_filings.R`](parse_lda_filings.R) `<year> ...`: writes the five filings tables per year, with columns
   from [`lda_cols.csv`](lda_cols.csv). `LDA_EXCLUDE_UUIDS=<file>` skips filings already in an older file.
3. [`parse_lda_contributions.R`](parse_lda_contributions.R) `<year> ...`: writes the contributions file per year.

Values are as published. `dt_posted` is converted to UTC. `lda_contribs_py/` is the older parser for the House XML
files and is no longer used.

## Updating

Scrape and parse the current year again and replace its files. Filings posted after the last run of an earlier year
can be added with `LDA_POSTED_AFTER` and `LDA_EXCLUDE_UUIDS`, as was done for 2022.
