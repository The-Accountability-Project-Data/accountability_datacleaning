# NPI 2026

TAP dataset 505, built 2026-10-04 from the National Provider Identifier file published by the Centers for Medicare &
Medicaid Services (NPPES). Uploaded as `csv/npi_2026-09-13.csv` (9,443,429 rows, 81 columns): a snapshot of every
active NPI as of Sept. 13, 2026, individuals and organizations.

## Source

| | |
|---|---|
| Publisher | Centers for Medicare & Medicaid Services, NPPES |
| Download page | <https://download.cms.gov/nppes/NPI_Files.html> |
| Documentation | <https://www.cms.gov/Regulations-and-Guidance/Administrative-Simplification/NationalProvIdentStand/DataDissemination.html>; the readme and code values PDFs are in the zip |
| File | Monthly NPPES Downloadable File, Version 2: `NPPES_Data_Dissemination_September_2026_V2.zip` (released Sept. 14, 2026; data through Sept. 13, 2026) |
| Cadence | monthly full file, named `NPPES_Data_Dissemination_<Month>_<Year>_V2.zip` |

The main file in the zip, `npidata_pfile_20050523-20260913.csv` (11.7 GB, 330 columns), has one row per NPI:

| Entity type | Rows |
|---|---:|
| 1, individuals | 7,471,371 |
| 2, organizations | 1,972,058 |
| blank, deactivated | 355,329 |
| total | 9,798,758 |

The zip's other files (practice locations, endpoints, other organization names) are not used.

## Build

[`code/build.py`](code/build.py) (Python):

* keeps individuals and organizations and drops the 355,329 deactivated NPIs, which the file lists with only the NPI
  and deactivation date;
* keeps 80 of the 330 columns: all 55 single columns, and slots 1–5 of the five specialty/license blocks (taxonomy
  code, license number, license state, primary taxonomy switch, taxonomy group). It drops slots 6–15 of those blocks
  and all 50 "Other Provider Identifier" sets (200 columns);
* keeps the original column names and order;
* adds `year`, the year the data runs through (2026 on every row);
* copies every value as published.

The output is ASCII. Input zip sha256 `6573e0d1…3cec4`; output sha256 `5b833064…5b67`.

## Updating

Download the current month's zip from the download page and run `python build.py <zip>`; it writes
`npi_<data-through date>.csv`.
