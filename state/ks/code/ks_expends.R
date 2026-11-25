# Kansas campaign expenditures -- full rebuild from the Kansas Secretary of State campaign finance viewer, November
# 2026 (replaces ks_expends_20050318-20220101.csv). From the repo root:
#   python3 state/ks/code/reparse.py <raw dir>; Rscript state/ks/code/ks_expends.R
# Output: state/ks/expends/data/clean/ks_expends_<first year>-<last year>.csv.
#
# - Source and reading: see ks_common.R. The expenditure export labels the payee "Contributor" and the expense
#   type "TypeofTender"; they become recipient and typeof_expense, as in the earlier build.
# - Rows: every expenditure the viewer returns, as published.
# - Layout: the earlier build's 18 columns in its order (cand_name, recipient, address, address2, city, state, zip,
#   date, typeof_expense, amount, start_date, end_date, na_flag, dupe_flag, year, address_clean, city_clean,
#   zip_clean), then state_clean (new).
# - All rows kept. na_flag: date, amount, recipient or cand_name missing. dupe_flag: every copy of a row identical on
#   all source columns. year = year(date).
library(here)
here::i_am("state/ks/code/ks_expends.R")
source(here("state", "ks", "code", "ks_common.R"))
RENAME <- c(cand_name = "cand_name", recipient = "contributor", address = "address", address2 = "address2", city = "city",
            state = "state", zip = "zip", date = "date", typeof_expense = "typeof_tender", amount = "amount",
            start_date = "start_date", end_date = "end_date")
LAYOUT <- c(names(RENAME), "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "zip_clean", "state_clean")
out_dir <- dir_create(here("state", "ks", "expends", "data", "clean"))
build_ks(here("state", "ks", "data", "parsed", "ks_expenditure.csv"), RENAME, "amount", c("date", "start_date", "end_date"),
         "recipient", LAYOUT, "ks_expends", out_dir)
