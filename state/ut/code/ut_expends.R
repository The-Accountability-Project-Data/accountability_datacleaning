# Utah campaign expenditures -- full rebuild from the Utah disclosures per-year downloads, November 2026 (replaces
# ut_expends_clean.csv, 2000-2020). From the repo root:
#   python3 state/ut/code/reparse.py <raw dir>; Rscript state/ut/code/ut_expends.R
# Output: state/ut/expends/data/clean/ut_expends_<first report year>-<last report year>.csv.
#
# - Source and reading: see ut_common.R.
# - Rows: TRAN_TYPE "Expenditure", every filer type and report year, as published.
# - Layout: the earlier build's 26 columns in its order: filed, entity (the filer's entity type), committee (the
#   filer), report, id, type, date, amount, inkind, loan, amends, name (who was paid), purpose, address1, address2,
#   city, state, zip, inkind_comments, na_flag, dupe_flag, year, address_clean, zip_clean, state_clean, city_clean.
#   date as YYYY-MM-DD, amount as a number. (The report year is in the file name only, as before.)
# - All rows kept. na_flag: date, amount, name or committee missing. dupe_flag: every copy of a row identical on all
#   source columns but id. year = year(date).
library(here)
here::i_am("state/ut/code/ut_expends.R")
source(here("state", "ut", "code", "ut_common.R"))
RENAME <- c(filed = "FILED", entity = "ENTITY_TYPE", committee = "ENTITY_NAME", report = "REPORT", id = "TRAN_ID",
            type = "TRAN_TYPE", date = "TRAN_DATE", amount = "TRAN_AMT", inkind = "INKIND", loan = "LOAN",
            amends = "AMENDS", name = "NAME", purpose = "PURPOSE", address1 = "ADDRESS1", address2 = "ADDRESS2",
            city = "CITY", state = "STATE", zip = "ZIP", inkind_comments = "INKIND_COMMENTS", report_year = "REPORT_YEAR")
LAYOUT <- c(setdiff(names(RENAME), "report_year"), "na_flag", "dupe_flag", "year", "address_clean", "zip_clean", "state_clean", "city_clean")
out_dir <- dir_create(here("state", "ut", "expends", "data", "clean"))
build_ut(here("state", "ut", "data", "parsed", "ut_transactions.csv"), "Expenditure", RENAME,
         c(date = "date", amount = "amount", year = "year", name = "name", filer = "committee", id = "id",
           report_year = "report_year"),
         list(src = c("address1", "address2", "city", "state", "zip"), out = c("address_clean", "city_clean", "state_clean", "zip_clean")),
         LAYOUT, "ut_expends", out_dir)
