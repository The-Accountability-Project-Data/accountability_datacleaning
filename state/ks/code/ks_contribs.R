# Kansas campaign contributions -- full rebuild from the Kansas Secretary of State campaign finance viewer, November
# 2026 (replaces ks_contribs_20080109-20211231.csv). From the repo root:
#   python3 state/ks/code/reparse.py <raw dir>; Rscript state/ks/code/ks_contribs.R
# Output: state/ks/contribs/data/clean/ks_contribs_<first year>-<last year>.csv.
#
# - Source and reading: see ks_common.R.
# - Rows: every contribution the viewer returns, as published.
# - Layout: the earlier build's 21 columns in its order (cand_name, contributor, address, address2, city, state, zip,
#   occupation, industry, date, typeof_tender, amount, in_kind_amount, in_kind_description, start_date, end_date,
#   dupe_flag, year, address_clean, city_clean, zip_clean), then na_flag and state_clean (new).
# - All rows kept. na_flag: date, contributor or cand_name missing, or both amount and in_kind_amount missing
#   (in-kind contributions have only in_kind_amount). dupe_flag: every copy of a row identical
#   on all source columns. year = year(date).
library(here)
here::i_am("state/ks/code/ks_contribs.R")
source(here("state", "ks", "code", "ks_common.R"))
RENAME <- c(cand_name = "cand_name", contributor = "contributor", address = "address", address2 = "address2", city = "city",
            state = "state", zip = "zip", occupation = "occupation", industry = "industry", date = "date",
            typeof_tender = "typeof_tender", amount = "amount", in_kind_amount = "in_kind_amount",
            in_kind_description = "in_kind_description", start_date = "start_date", end_date = "end_date")
LAYOUT <- c(names(RENAME), "dupe_flag", "year", "address_clean", "city_clean", "zip_clean", "na_flag", "state_clean")
out_dir <- dir_create(here("state", "ks", "contribs", "data", "clean"))
build_ks(here("state", "ks", "data", "parsed", "ks_contribution.csv"), RENAME, c("amount", "in_kind_amount"),
         c("date", "start_date", "end_date"), "contributor", LAYOUT, "ks_contribs", out_dir)
