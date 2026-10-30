U.S. Senate Disbursements
================
Claude (for Jacob Fenton), 2026-10-13

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

This diary builds TAP dataset 520, **U.S. Senate disbursements**: itemized Senate spending, April 2011 to March
2026, from 30 semiannual reports. The House counterpart is `national/house_disbursements/`.

## Source

The **Secretary of the Senate** publishes the semiannual *Report of the Secretary of the Senate*, covering six months
(April–September, or October–March), some months after the period closes:
<https://www.senate.gov/legislative/common/generic/report_secsen.htm>. The reports are **PDF only** (about
1,500–3,100 pages each). GovInfo hosts them as Senate Documents:

    https://www.govinfo.gov/content/pkg/GPO-CDOC-<congress>sdoc<n>/pdf/GPO-CDOC-<congress>sdoc<n>.pdf

e.g. S. Doc. 119-6 (Oct 2025 – Mar 2026) is `GPO-CDOC-119sdoc6`. The itemized pages ("DOCUMENT NO. / DATE POSTED /
PAYEE NAME / OBLIGATION/SERVICE DATES START END / DESCRIPTION / AMOUNT") begin around page 17. The report pages
list every report; GovInfo also splits some into Part I/II, but the whole-document PDF is used here.

No official machine-readable version exists. Others: Sunlight Foundation 2014 (three years of spreadsheets, one-off);
ProPublica's fork github.com/propublica/senate_disbursements (three more reports with the 2015 logic, last commit
2017); POPVOX's Senate Expenditure Explorer (search only, no downloads).

## History

The parser was written by Jacob Fenton for the Sunlight Foundation in 2014–15:
<https://github.com/jsfenfen/senate_disbursements> (Python 2; reports of the 112th–114th Congress, 2011–2015;
`all_years/` cleaned CSVs). In October 2026 it was ported to Python 3 and improved over six rounds of fixes, and
run on all 30 reports from 112_sdoc4 (Apr–Sep 2011) to 119_sdoc6 (Oct 2025 – Mar 2026). The working copy, with
every report's PDF, `pages/` and outputs, is `~/uc_berkeley/senate_disbursements_update` (laid out like the 2015
repo so it can be copied into it); its `README.md` has the round-by-round history.

## Code

`code/` (copied from the working copy, 2026-10-13):

| file | does |
|---|---|
| `rip_pages.py` | `pdftotext -layout` per page into `pages/`; finds the itemized page range itself (pages with exactly one detail header) and prints it |
| `read_pages.py` | parses `pages/` into `senate_data.csv` (no header, 11 columns, the 2015 format), `missing_data.txt` (unparsed lines per page, as 2015), and `subtotals.csv` (new: every printed subtotal reconciled against the parsed rows it closes). `--baseline` runs the 2015 logic for comparison |
| `compare_reports.sh` | reruns `read_pages.py` in both modes in every report directory and tabulates rows / unparsed lines / reconciliation into `compare_reports.csv` |
| `group_errors.py` | groups `missing_data.txt` lines by shape, to pick the next class of errors to fix |
| `show_fix.py` | prints before/after examples of a fix |
| `compare_to_references.py` | compares our output with the 2015 repo's and ProPublica's parses |
| `all_years/clean_files.py`, `parse_office_names.py`, `get_all_headers.py` | the 2015 cleaning step: 11 raw columns -> 16 (office split into senator / office / funding year, salary flag) |
| `all_years/build_all_years.py` | cleans every report and concatenates them into `senate_disbursements_all.csv` |
| `all_years/build_tap_files.py` | splits that into one TAP file per report and adds `year` |

Needs Python 3 and poppler (`pdftotext`, `pdfinfo`). `stats/` holds the October 2026 comparison tables.

## Process a report

Work outside the repo or in `national/senate_disbursements/data/` (gitignored). One directory per report:

```
mkdir 119_sdoc6 && cd 119_sdoc6
cp ../rip_pages.py ../read_pages.py .
curl -O https://www.govinfo.gov/content/pkg/GPO-CDOC-119sdoc6/pdf/GPO-CDOC-119sdoc6.pdf
python3 rip_pages.py              # -> pages/, prints the itemized page range
python3 read_pages.py             # -> senate_data.csv, missing_data.txt, subtotals.csv
python3 read_pages.py --baseline --out senate_data_baseline.csv   # optional: 2015 logic, to compare
```

No hand edits: the PDF is found in the directory and the page range is detected. Then, from the top directory:

```
bash compare_reports.sh                       # both modes, every report -> compare_reports.csv
cd all_years && python3 build_all_years.py    # -> <report>_senate_data_cleaned.csv, senate_disbursements_all.csv
python3 build_tap_files.py --out <dir>        # -> senate-disbursements_<years>_<report>.csv
```

## What the parser handles

Both modes: Python 3; automatic page range; amounts with "$" (2026 reports print "$500.00"; the 2015 amount pattern
matched 0% of 2026 detail lines, the widened one 100% of a sample).

Improved mode (default), added in rounds 1–6:

- continuation lines at the top of a page attach to the previous page's entry (2015 reset per page and lost them,
  amounts included); an entry continued from the previous page takes the new page's column positions (they can
  shift ~30 characters at a page break); rows are written at the end so those continuations reach earlier rows;
- payroll lines with only "LAST, FIRST" and an amount (title wrapped above or below) parse as three-data lines with
  the title reassembled; bare numbers ("31", "JAN. 2") are wrapped title date ranges, not page numbers;
- subtotal labels match case-insensitively ("Net Payroll Expenses") and include BENEFITS FOR FORMER PERSONNEL;
  object-class codes before labels ("3.00 TRAVEL ...") and alone at the margin;
- wrapped payee names rejoined (text below the row, and above it when the row's payee is blank); five-data lines
  that newer pdftotext splits in two are rejoined;
- appendix page numbers ("C-4") and GPO print marks skipped; INTERDEPARTMENTAL TRANSPORTATION read as a description;
- subtotal reconciliation recognizes a subtotal that equals a subset of the group's parsed rows (match_subset).

## Checks

- **Fidelity to 2015.** 114_sdoc4 (the last report of the 2015 repo) in improved mode reproduces the repo's
  `senate_data.csv` exactly: 46,492 rows, all identical. In baseline mode the other 2011–2014 reports have the same
  rows as the repo's parses (matched by key; 99.8–100% identical in every field), except 46 rows of 113_sdoc25 and
  41 of 114_sdoc4 that today's pdftotext (poppler 24.04) lays out differently
  (`stats/compare_to_references_2026-10.csv`).
- **ProPublica.** Their raw 114_sdoc13 parse (2015 logic) is fully contained in ours (53,296 rows; we have 152 more).
- **Reconciliation** (`stats/compare_reports_2026-10.csv`), all 30 reports:

| | 2015 logic | improved |
|---|---:|---:|
| rows | 1,470,039 | 1,474,410 |
| unparsed lines | 26,193 | 1,571 |
| subtotal groups matching the printed subtotal (exact or subset) | 12,620 of 23,416 (54%) | 21,470 of 24,364 (88%) |
| groups differing, with unparsed lines in them | 5,126 | 524 |
| groups differing, no unparsed lines | 5,664 | 2,369 |

- Encoding: all output valid UTF-8.

## Build the TAP files

`build_tap_files.py` writes one file per report, named by the report period's calendar years:
`senate-disbursements_2025-2026_119-sdoc6.csv` (Oct 2025 – Mar 2026), `senate-disbursements_2025_119-sdoc5.csv`
(Apr–Sep 2025). Columns: the 2015 repo's 16 `all_years` columns (`source_doc, senator_flag, senator_name,
raw_office, funding_year, fiscal_year, congress_number, reference_page, document_number, date_posted, start_date,
end_date, description, salary_flag, amount, payee`) plus **`year`**:

- `funding_year` when it is a single fiscal year;
- otherwise the year of `date_posted` (multi-year funds, or no funding year);
- otherwise (payroll lines without a date) the last calendar year of the report period.

Until early 2021 multi-year funds are written as two 2-digit years run together ("1214" = FY2012–2014, "2024" =
FY2020–2024); from 117_sdoc8 on as "2021-2025". So a 4-digit `funding_year` counts as a single year only when it is
plausible for the report: from 6 years before the period through 1 year after. That keeps "2024" in a 2020 report
from being read as 2024. About 34 rows ("2021" in the Apr–Sep 2020 report, "2022" in Oct 2020 – Mar 2021) could be
either and are read as single years.

## Results

October 2026: 30 files, **1,474,410 rows** (`stats/build_tap_files_2026-10.log` has per-file counts and how each
row's year was set). On S3 as `csv/senate-disbursements_<years>_<report>.csv`; TAP dataset 520, DataFiles 2276–2305.

Fill rates in the combined file: document number and dates 81.7% (payroll lines have none, as printed);
`senator_name` 79.7%; `funding_year` 94.1%; `congress_number` 5.7% and `fiscal_year` 0.1% (2015 columns that the
cleaning step rarely fills).

## Known gaps

- 2,369 subtotal groups (about 10%, mostly 2015–2020 reports) differ from the printed subtotal with no unparsed
  lines in them. Not explained: could be the Senate's arithmetic or rows we parse wrong.
- 1,571 printed lines are not parsed (listed per page in each report's `missing_data.txt`): mostly amount lines at
  the top of a page that aren't continuations, and text-only lines that don't attach.
- pdftotext versions lay out some lines differently, so re-ripping a report with a different poppler can change a
  few rows.

## Updating

A new report appears twice a year. Make its directory, run the three commands above, check its row in
`compare_reports.csv` against its neighbors (a jump in unparsed lines or differing groups means the format drifted;
`group_errors.py` shows how), rebuild `all_years` and the TAP files, and add the new file to dataset 520.
