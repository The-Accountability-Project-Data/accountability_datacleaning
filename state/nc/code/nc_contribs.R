# North Carolina campaign contributions -- full rebuild from the NC SBoE transaction search, November 2026 (replaces
# nc_contribs_clean.csv and nc_contribs_clean20200721-20221015.csv). From the repo root:
#   python3 state/nc/code/reparse.py <raw dir>; Rscript state/nc/code/nc_contribs.R
# Output: state/nc/contribs/data/clean/nc_contribs_<first year>-2022.csv and nc_contribs_2023-<this year>.csv.
#
# - Source and reading: see nc_common.R.
# - Rows: every receipt (all 18 receipt types), as published, EXCEPT unitemized contributions: NC committees need not
#   name individuals who give $50 or less in an election (G.S. 163-278.11) and report that money as rows named
#   "Aggregated Individual Contribution" (no donor, almost never an address; 6.5M rows, 47.7% of all receipts, about
#   4% of the dollars). Those rows are left out: every name matching "aggregate(d)
#   (individual) contribution(s) (various)", any case. con_* = the contributor (Name, Street Line 1, ...), rec_* =
#   the receiving committee (Committee Name, Committee SBoE ID, Committee Street 1, ...).
# - Layout: the earlier builds' 34 columns in their order (con_name ... declaration, na_flag, dupe_flag, year,
#   con_addr_clean, rec_addr_clean, con_zip_clean, rec_zip_clean, con_state_clean, rec_state_clean, rec_city_clean,
#   con_city_clean), then account_code (published, not in the earlier builds). date as YYYY-MM-DD, amount as a number.
# - All rows kept. na_flag: date, amount, con_name or rec_name missing. dupe_flag: every copy of a row identical on
#   all source columns. year = year(date).
library(here)
here::i_am("state/nc/code/nc_contribs.R")
source(here("state", "nc", "code", "nc_common.R"))
NAMES <- c("con_name", "con_addr1", "con_addr2", "con_city", "con_state", "con_zip", "con_job", "con_emp", "con_type",
           "rec_name", "rec_id", "rec_addr1", "rec_addr2", "rec_city", "rec_state", "rec_zip", "report", "date",
           "account_code", "amount", "method", "purpose", "candidate", "declaration")
LAYOUT <- c(setdiff(NAMES, "account_code"), "na_flag", "dupe_flag", "year", "con_addr_clean", "rec_addr_clean",
            "con_zip_clean", "rec_zip_clean", "con_state_clean", "rec_state_clean", "rec_city_clean", "con_city_clean",
            "account_code")
PARTIES <- list(
  list(src = c("con_addr1", "con_addr2", "con_city", "con_state", "con_zip"),
       out = c("con_addr_clean", "con_city_clean", "con_state_clean", "con_zip_clean")),
  list(src = c("rec_addr1", "rec_addr2", "rec_city", "rec_state", "rec_zip"),
       out = c("rec_addr_clean", "rec_city_clean", "rec_state_clean", "rec_zip_clean")))
out_dir <- dir_create(here("state", "nc", "contribs", "data", "clean"))
build_nc(here("state", "nc", "data", "parsed", "nc_receipts.csv"), NAMES, c("con_name", "rec_name"), PARTIES, LAYOUT,
         "nc_contribs", out_dir,
         drop = function(x) !is.na(x$con_name) &
           grepl("^\\s*aggregated?\\s+(individual\\s+)?contributions?(\\s+various)?\\s*$", x$con_name, ignore.case = TRUE))
