U.S. Senate Disbursements
================
2026-10-13

- [Project](#project)
- [Source](#source)
- [History](#history)
- [Code](#code)
- [Process a report](#process-a-report)
- [What the parser handles](#what-the-parser-handles)
- [Checks](#checks)
- [Build the TAP files](#build-the-tap-files)
- [Results](#results)
- [Known gaps](#known-gaps)
- [Updating](#updating)

## Project

The Accountability Project is an effort to cut across data silos and give journalists, policy professionals,
activists, and the public at large a simple way to search across huge volumes of public data about people and
organizations. Each dataset row is a transaction with (at least) its parties, a date and an amount.

This diary builds **U.S. Senate disbursements**: itemized Senate spending, April 2011 to March 2026, from 30
semiannual reports. The House counterpart is `national/house_disbursements/`.

## Source

The Secretary of the Senate publishes the semiannual *Report of the Secretary of the Senate* (April–September and
October–March), as PDF only, about 1,500–3,100 pages each:
<https://www.senate.gov/legislative/common/generic/report_secsen.htm>. GovInfo hosts them as Senate Documents:

    https://www.govinfo.gov/content/pkg/GPO-CDOC-<congress>sdoc<n>/pdf/GPO-CDOC-<congress>sdoc<n>.pdf

e.g. S. Doc. 119-6 (Oct 2025 – Mar 2026) is `GPO-CDOC-119sdoc6`. The itemized pages begin around page 17. The
whole-document PDF is used, not GovInfo's Part I/II splits. There is no official machine-readable version.

## History

The parser was written for the Sunlight Foundation in 2014–15:
<https://github.com/jsfenfen/senate_disbursements> (Python 2; reports of 2011–2015). In October 2026 it was ported to
Python 3, extended, and run on all 30 reports, 112_sdoc4 (Apr–Sep 2011) through 119_sdoc6 (Oct 2025 – Mar 2026).

## Code

| file | does |
|---|---|
| `rip_pages.py` | extracts each page with `pdftotext -layout` into `pages/` and finds the itemized page range |
| `read_pages.py` | parses `pages/` into `senate_data.csv` (11 columns, no header), `missing_data.txt` (unparsed lines per page) and `subtotals.csv` (each printed subtotal checked against the rows it closes). `--baseline` uses the 2015 logic |
| `compare_reports.sh` | runs `read_pages.py` both ways in every report directory and writes `compare_reports.csv` |
| `group_errors.py` | groups unparsed lines by shape |
| `show_fix.py` | prints before/after examples of a parser change |
| `compare_to_references.py` | compares the output with the 2015 and ProPublica parses |
| `all_years/clean_files.py`, `parse_office_names.py`, `get_all_headers.py` | cleaning: 11 raw columns to 16 (office split into senator / office / funding year, salary flag) |
| `all_years/build_all_years.py` | cleans every report and combines them into `senate_disbursements_all.csv` |
| `all_years/build_tap_files.py` | writes one file per report and adds `year` |

Needs Python 3 and poppler (`pdftotext`, `pdfinfo`). `stats/` holds the October 2026 comparison tables.

## Process a report

One directory per report, outside the repo or in `national/senate_disbursements/data/` (gitignored):

```
mkdir 119_sdoc6 && cd 119_sdoc6
cp ../rip_pages.py ../read_pages.py .
curl -O https://www.govinfo.gov/content/pkg/GPO-CDOC-119sdoc6/pdf/GPO-CDOC-119sdoc6.pdf
python3 rip_pages.py              # -> pages/, prints the itemized page range
python3 read_pages.py             # -> senate_data.csv, missing_data.txt, subtotals.csv
python3 read_pages.py --baseline --out senate_data_baseline.csv   # optional: 2015 logic, to compare
```

The PDF and the page range are found automatically. Then, from the top directory:

```
bash compare_reports.sh                       # both modes, every report -> compare_reports.csv
cd all_years && python3 build_all_years.py    # -> <report>_senate_data_cleaned.csv, senate_disbursements_all.csv
python3 build_tap_files.py                    # -> ../../data/clean/senate-disbursements_<years>_<report>.csv
```

## What the parser handles

- The itemized page range is found automatically; amounts are read with or without "$" (2026 reports print
  "$500.00").

The default mode adds, beyond the 2015 logic:

- continuation lines at the top of a page attach to the previous page's entry, with the new page's column positions;
- payroll lines with only "LAST, FIRST" and an amount get their wrapped title reassembled; bare numbers ("31",
  "JAN. 2") are read as wrapped date ranges, not page numbers;
- subtotal labels match regardless of case and include BENEFITS FOR FORMER PERSONNEL; object-class codes before
  labels ("3.00 TRAVEL ...") are recognized;
- wrapped payee names and five-field lines split in two are rejoined;
- appendix page numbers ("C-4") and GPO print marks are skipped; INTERDEPARTMENTAL TRANSPORTATION is a description;
- a subtotal can match a subset of its group's rows.

## Checks

- 114_sdoc4 reproduces the 2015 repo's `senate_data.csv` exactly (46,492 rows). The other 2011–2014 reports match the
  2015 parses in 99.8–100% of fields, except 87 rows that current pdftotext (poppler 24.04) lays out differently
  (`stats/compare_to_references_2026-10.csv`).
- ProPublica's 114_sdoc13 parse (53,296 rows) is fully contained in this one, which has 152 more rows.
- Subtotal reconciliation, all 30 reports (`stats/compare_reports_2026-10.csv`):

| | 2015 logic | improved |
|---|---:|---:|
| rows | 1,470,039 | 1,474,410 |
| unparsed lines | 26,193 | 1,571 |
| subtotal groups matching the printed subtotal (exact or subset) | 12,620 of 23,416 (54%) | 21,470 of 24,364 (88%) |
| groups differing, with unparsed lines in them | 5,126 | 524 |
| groups differing, no unparsed lines | 5,664 | 2,369 |

- All output is valid UTF-8.

## Build the TAP files

One file per report, named by the report period's calendar years: `senate-disbursements_2025-2026_119-sdoc6.csv`
(Oct 2025 – Mar 2026), `senate-disbursements_2025_119-sdoc5.csv` (Apr–Sep 2025). Columns: the 16 cleaned columns
(`source_doc, senator_flag, senator_name, raw_office, funding_year, fiscal_year, congress_number, reference_page,
document_number, date_posted, start_date, end_date, description, salary_flag, amount, payee`) plus **`year`**:

- `funding_year` when it is a single fiscal year;
- otherwise the year of `date_posted`;
- otherwise (payroll lines without a date) the last calendar year of the report period.

Until early 2021, multi-year funds are written as two 2-digit years run together ("1214" = FY2012–2014, "2024" =
FY2020–2024); from 117_sdoc8 on, as "2021-2025". A 4-digit `funding_year` counts as a single year only if it falls
between 6 years before the report period and 1 year after. About 34 ambiguous rows ("2021" in the Apr–Sep 2020
report, "2022" in Oct 2020 – Mar 2021) are read as single years.

## Results

October 2026: 30 files, **1,474,410 rows** (per-file counts in `stats/build_tap_files_2026-10.log`).

Fill rates: document number and dates 81.7% (payroll lines have none); `senator_name` 79.7%; `funding_year` 94.1%;
`congress_number` 5.7%; `fiscal_year` 0.1%.

## Known gaps

- 2,369 subtotal groups (about 10%, mostly 2015–2020 reports) differ from the printed subtotal with no unparsed lines
  in them.
- 1,571 printed lines are not parsed (listed per page in each report's `missing_data.txt`), mostly amount lines at the
  top of a page and text-only lines.
- Different poppler versions lay out some lines differently, which can change a few rows.

## Updating

A new report appears twice a year. Make its directory, run the commands above, and compare its row in
`compare_reports.csv` with its neighbors (a jump in unparsed lines or differing groups means the format changed).
Then rebuild `all_years` and the per-report files.
