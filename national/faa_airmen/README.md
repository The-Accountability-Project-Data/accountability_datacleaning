# FAA Airmen 2026

TAP dataset 506, built 2026-10-05 from the FAA's Releasable Airmen Database. Uploaded as `csv/airmen_2026-10-01.csv`
(972,675 rows, 18 columns).

## Source

| | |
|---|---|
| Publisher | Federal Aviation Administration, Airmen Certification |
| Landing page | <https://www.faa.gov/licenses_certificates/airmen_certification/releasable_airmen_download> |
| File | `https://registry.faa.gov/database/CS102026.zip`, comma separated format, release dated Oct. 1, 2026 |
| Documentation | `HelpComm.pdf`, in the zip and on the landing page |
| Cadence | monthly; the file is named `CS<MM><YYYY>.zip` |

The zip holds four files:

| File | Rows | Contents |
|---|---:|---|
| `PILOT_BASIC.csv` | 592,799 | one row per pilot: unique ID, name, address, region, medical class and dates |
| `NONPILOT_BASIC.csv` | 379,876 | one row per non-pilot airman (mechanics, dispatchers and others), same columns |
| `PILOT_CERT.csv` | 682,182 | pilots' certificates and ratings |
| `NONPILOT_CERT.csv` | 393,295 | non-pilots' certificates |

## Build

[`code/build.py`](code/build.py) (Python; helpers in [`code/buildlib.py`](code/buildlib.py)):

* stacks `PILOT_BASIC.csv` and `NONPILOT_BASIC.csv`; the certificate files are not used;
* adds `airman_type` (`pilot` or `non-pilot`), the file each row came from. 63,078 people are in both files and
  appear twice, once per type;
* names the columns in lower case with underscores (`UNIQUE ID` is `uniqueid`);
* trims space padding from every value and drops the empty trailing column;
* adds `uszip5` (the first five digits of a US ZIP, blank otherwise; 95.8% filled) and `year` (2026 on every row);
* keeps everything else as published, including `med_date` as `MMYYYY`.

Columns: `uniqueid, first_name, last_name, street_1, street_2, city, state, zip_code, country, region, med_class,
med_date, med_exp_date, basic_med_course_date, basic_med_cmec_date, airman_type, uszip5, year`.

The output is ASCII. Input and output sha256: input `ae59aed8…5584a4`, output `e10b7ea2…44b9`.

## Earlier editions

* 2023 (dataset 463, FAA Pilots, `csv/pilots_2023.csv`, 957,444 rows): built in Python by Janelle O'Dea,
  [`../faa_pilots/faa-pilots-py/`](../faa_pilots/faa-pilots-py/faa_pilots_README.md). Same two files stacked, without
  `airman_type`. `med_date` was rewritten as `med_date_revised` (MM/YYYY) and `med_exp_date` written as a number.
  `uszip5` is filled for `country` USA; the code fills it with `00000` for other countries. `year` is 2023.
* 2021: [`../faa_pilots/docs/faa_pilots_basic.md`](../faa_pilots/docs/faa_pilots_basic.md) (`airmen_2021.csv`).

## Updating

Download the current `CS<MM><YYYY>.zip` and run `python build.py CS<MM><YYYY>.zip`; it writes
`airmen_<release date>.csv`.
