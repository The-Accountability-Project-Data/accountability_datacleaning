# Federal campaign contributions and payments

TAP datasets 62 (Federal campaign contributions, FEC Schedule A) and 63 (Federal campaign payments, FEC Schedule B),
read from the raw `.fec` filings the Federal Election Commission publishes. Built with
[fec2file](https://github.com/The-Accountability-Project-Data/fec2file) (`master`), which uses
[fecfile](https://github.com/esonderegger/fecfile).

## Source

| | |
|---|---|
| Publisher | Federal Election Commission |
| Files | daily zips of electronic filings, `https://cg-519a459a-0ea3-42c2-b7bc-fa1143481f74.s3-us-gov-west-1.amazonaws.com/bulk-downloads/electronic/<YYYYMMDD>.zip` |
| Committee and candidate names | the FEC's committee and candidate master files, `https://www.fec.gov/files/bulk-downloads/<YYYY>/cm<YY>.zip` and `cn<YY>.zip` |

## Update: September 2026

Coverage years 2024, 2025 and 2026 were rebuilt and replace the 2024 files loaded earlier. Files for 2007–2023 are
unchanged.

* Daily zips dated Jan. 1, 2024, through Sept. 25, 2026 (`metadata/electronic_zipfiles.txt`, 999 zips). Electronic
  filings only; no paper filings.
* Forms F3, F3X and F3P. The 24- and 48-hour reports are not used. Filings superseded by an amendment are dropped.
* Each filing goes to the file for the year of its coverage start date. Search shows that year.
* Schedule A and Schedule B line items only. Schedule E and F13 inaugural-committee receipts (F132) are not included.
* Line items with a blank date, or a date before 2021, are dropped.
* Added columns: `year` (from the transaction date) and the filer's committee name and address and candidate ID and
  name, from the master files for the transaction's two-year cycle (`CMTE_NM`, `CMTE_ST1`, `CMTE_ST2`, `CMTE_CITY`,
  `CMTE_ST`, `CMTE_ZIP`, `CAND_ID`, `CAND_NAME`). Line items whose committee is not in the master file are kept
  without them.
* Everything else is kept as filed, including street addresses and memo entries.
* Output is UTF-8. Each year's file is split into parts on record boundaries, each part with the header row.

| File | Dataset | Parts | Rows |
|---|---:|---:|---:|
| `ScheduleA-2024_annotated.csv`, `-part2` … `-part7` | 62 | 7 | 200,069,361 |
| `ScheduleA-2025_annotated-part1` … `-part11` | 62 | 11 | 107,400,887 |
| `ScheduleA-2026_annotated-part1` … `-part3` | 62 | 3 | 72,588,977 |
| `ScheduleB-2024_annotated.csv`, `-part2` … `-part6` | 63 | 6 | 117,830,254 |
| `ScheduleB-2025_annotated-part1` … `-part7` | 63 | 7 | 66,295,354 |
| `ScheduleB-2026_annotated-part1`, `-part2` | 63 | 2 | 48,219,885 |

Schedule A columns: `filing_number, line_sequence, form_type, filer_committee_id_number, transaction_id,
back_reference_tran_id_number, back_reference_sched_name, entity_type, contributor_organization_name,
contributor_name, contributor_last_name, contributor_first_name, contributor_middle_name, contributor_prefix,
contributor_suffix, contributor_street_1, contributor_street_2, contributor_city, contributor_state,
contributor_zip_code, election_code, election_other_description, contribution_date, contribution_amount,
contribution_aggregate, contribution_purpose_descrip, contributor_employer, contributor_occupation,
donor_committee_fec_id, donor_committee_name, donor_candidate_fec_id, donor_candidate_last_name,
donor_candidate_first_name, donor_candidate_middle_name, donor_candidate_prefix, donor_candidate_suffix,
donor_candidate_office, donor_candidate_state, donor_candidate_district, conduit_name, conduit_street1,
conduit_street2, conduit_city, conduit_state, conduit_zip_code, memo_code, memo_text_description, reference_code`,
then the added columns.

Schedule B columns: `filing_number, line_sequence, form_type, filer_committee_id_number, transaction_id_number,
back_reference_tran_id_number, back_reference_sched_name, entity_type, payee_organization_name, payee_name,
payee_last_name, payee_first_name, payee_middle_name, payee_prefix, payee_suffix, payee_street_1, payee_street_2,
payee_city, payee_state, payee_zip_code, election_code, election_other_description, expenditure_date,
expenditure_amount, semi_annual_refunded_bundled_amt, expenditure_purpose_descrip, category_code,
beneficiary_committee_fec_id, beneficiary_committee_name, beneficiary_candidate_fec_id,
beneficiary_candidate_last_name, beneficiary_candidate_first_name, beneficiary_candidate_middle_name,
beneficiary_candidate_prefix, beneficiary_candidate_suffix, beneficiary_candidate_office, beneficiary_candidate_state,
beneficiary_candidate_district, conduit_name, conduit_street_1, conduit_street_2, conduit_city, conduit_state,
conduit_zip_code, memo_code, memo_text_description, reference_to_si_or_sl_system_code_that_identifies_the_account`,
then the added columns.

## Earlier files

| Years | Files |
|---|---|
| 2021–2023 | `ScheduleA-<year>_annotated.csv`, `ScheduleB-<year>_annotated.csv`, electronic filings |
| 2007–2020 | `ScheduleA-<year>_annotated.csv`, `ScheduleB-<year>_annotated.csv`, plus paper filings in `Schedule{A,B}-<year>-paper_annotated.csv` and F13 receipts in `F132-2008_annotated.csv`, `F132-2012_annotated.csv` and `F132-2016-paper_annotated.csv` |

## Updating

In [fec2file](https://github.com/The-Accountability-Project-Data/fec2file), with `fecfile>=0.9.1`
(`requirements.txt`). Set the years in `process_filing_headers.py` (`START_YEAR`), `read_filings_from_amended_headers.py`
and `match_skeds_to_committees.py` (`YEARS`), list the daily zips in `metadata/electronic_zipfiles.txt` and put the
current `cm.txt` and `cn.txt` in `data/<YY>/`. Then:

```
python get_daily_filings.py
python unzip_filings.py
python process_filing_headers.py
python amend_headers.py
python read_filings_from_amended_headers.py
python match_skeds_to_committees.py -w 6            # or SKED:YEAR pairs, e.g. A:2026 B:2026
python split_csv.py schedules/ScheduleA-2026_annotated.csv --rows 30000000
```

The September 2026 run used a 600 GB data disk.
