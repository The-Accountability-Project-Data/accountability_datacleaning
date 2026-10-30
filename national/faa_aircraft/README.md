# FAA Aircraft 2026

TAP dataset 507, built 2026-10-05 from the FAA's Aircraft Registration Database. Uploaded as
`csv/aircraft_2026-10-02.csv` (317,239 rows, 48 columns).

## Source

| | |
|---|---|
| Publisher | Federal Aviation Administration, Aircraft Registry |
| Landing page | <https://www.faa.gov/licenses_certificates/aircraft_certification/aircraft_registry/releasable_aircraft_download> |
| File | `https://registry.faa.gov/database/ReleasableAircraft.zip` (same name every release; this release's files are dated Oct. 2, 2026) |
| Documentation | <https://registry.faa.gov/database/ardata.pdf> |

The zip holds UTF-8 text files with a byte-order mark, a trailing comma on each header and space-padded values:

| File | Rows | Contents |
|---|---:|---|
| `MASTER.txt` | 317,239 | registered aircraft, with owner name and address |
| `ACFTREF.txt` | 94,102 | aircraft models: manufacturer, model, type, seats and others, keyed by model code |
| `ENGINE.txt` | 4,752 | engine models |
| `DEREG.txt` | 383,532 | deregistered aircraft |
| `RESERVED.txt` | 127,468 | reserved N-numbers |
| `DEALER.txt` | 12,474 | dealer certificates |
| `DOCINDEX.txt` | 25,299 | document index |

## Build

[`code/build.py`](code/build.py) (Python; helpers in [`code/buildlib.py`](code/buildlib.py)):

* joins `MASTER.txt` to `ACFTREF.txt` on the manufacturer/model code; every `MASTER` row is kept, and all of them
  match a model. `ACFTREF`'s columns come first (its code column named `mfr_mdl_code`), then `MASTER`'s;
* does not use `ENGINE`, `DEREG`, `RESERVED`, `DEALER` or `DOCINDEX`;
* names the columns in lower case with underscores;
* strips the byte-order mark, trims space padding from every value and drops the empty trailing columns;
* adds `uszip5` (the first five digits of a US ZIP, blank otherwise; 98.0% filled) and `year` (2026 on every row);
* keeps everything else as published.

Columns: `mfr_mdl_code, mfr, model, type_acft, type_eng, ac_cat, build_cert_ind, no_eng, no_seats, ac_weight, speed,
tc_data_sheet, tc_data_holder, n_number, serial_number, eng_mfr_mdl, year_mfr, type_registrant, name, street,
street2, city, state, zip_code, region, county, country, last_action_date, cert_issue_date, certification,
type_aircraft, type_engine, status_code, mode_s_code, fract_owner, air_worth_date, other_names_1` through
`other_names_5, expiration_date, unique_id, kit_mfr, kit_model, mode_s_code_hex, uszip5, year`.

Input and output sha256: input `86ed524d…f186`, output `a41c8a39…40ff`.

## Updating

Download the current `ReleasableAircraft.zip` and run `python build.py ReleasableAircraft.zip`; it writes
`aircraft_<release date>.csv`.
