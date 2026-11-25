# Utah campaign contributions -- full rebuild from the Utah disclosures per-year downloads, November 2026 (replaces
# ut_contribs_2000-20210827.csv, ut_contribs_2000-2023.csv and ut_contribs_clean.csv; the first and last overlapped,
# so 2000-2021 was in the dataset twice). From the repo root:
#   python3 state/ut/code/reparse.py <raw dir>; Rscript state/ut/code/ut_contribs.R
# Output: state/ut/contribs/data/clean/ut_contribs_<first report year>-<last report year>.csv.
#
# - Source and reading: see ut_common.R.
# - Rows: TRAN_TYPE "Contribution", every filer type and report year, as published.
# - Layout: the earlier build's 27 columns in its order: filed, entity_name (the filer), report, tran_id, tran_type,
#   tran_date, tran_amt, inkind, loan, amends, name (the contributor), purpose, address1, address2, city, state, zip,
#   inkind_comments, entity_type, report_year, na_flag, dupe_flag, tran_year, address_clean, city_clean, state_clean,
#   zip_clean. tran_date as YYYY-MM-DD, tran_amt as a number.
# - All rows kept. na_flag: tran_date, tran_amt, name or entity_name missing. dupe_flag: every copy of a row identical
#   on all source columns but tran_id. tran_year = year(tran_date).
library(here)
here::i_am("state/ut/code/ut_contribs.R")
source(here("state", "ut", "code", "ut_common.R"))
RENAME <- c(filed = "FILED", entity_name = "ENTITY_NAME", report = "REPORT", tran_id = "TRAN_ID", tran_type = "TRAN_TYPE",
            tran_date = "TRAN_DATE", tran_amt = "TRAN_AMT", inkind = "INKIND", loan = "LOAN", amends = "AMENDS",
            name = "NAME", purpose = "PURPOSE", address1 = "ADDRESS1", address2 = "ADDRESS2", city = "CITY",
            state = "STATE", zip = "ZIP", inkind_comments = "INKIND_COMMENTS", entity_type = "ENTITY_TYPE",
            report_year = "REPORT_YEAR")
LAYOUT <- c(names(RENAME), "na_flag", "dupe_flag", "tran_year", "address_clean", "city_clean", "state_clean", "zip_clean")
out_dir <- dir_create(here("state", "ut", "contribs", "data", "clean"))
build_ut(here("state", "ut", "data", "parsed", "ut_transactions.csv"), "Contribution", RENAME,
         c(date = "tran_date", amount = "tran_amt", year = "tran_year", name = "name", filer = "entity_name", id = "tran_id",
           report_year = "report_year"),
         list(src = c("address1", "address2", "city", "state", "zip"), out = c("address_clean", "city_clean", "state_clean", "zip_clean")),
         LAYOUT, "ut_contribs", out_dir)
