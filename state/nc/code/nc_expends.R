# North Carolina campaign expenditures -- full rebuild from the NC SBoE transaction search, November 2026 (replaces
# nc_expends_clean.csv, nc_expends_2020-04-28.csv and nc_expends_2022-10-14.csv; the last also held receipts, as the
# 2022 search asked for both). From the repo root:
#   python3 state/nc/code/reparse.py <raw dir>; Rscript state/nc/code/nc_expends.R
# Output: state/nc/expends/data/clean/nc_expends_<first year>-2022.csv and nc_expends_2023-<this year>.csv.
#
# - Source and reading: see nc_common.R.
# - Rows: every expenditure (all 10 expenditure types), as published, EXCEPT unitemized expenditures: NC committees
#   may report non-media expenditures of $50 or less in aggregate, without the payee (G.S. 163-278.8), as rows named
#   "Aggregated Non-Media Expenditure" (308,144 rows, 15% of expenditures, about 0.2% of the dollars; mostly bank and
#   card fees). Those rows are left out: payee names matching "aggregate(d) (non-media)
#   (expenditure(s)|expense(s)|exp)", any case, spaced or hyphenated; misspelled ones and ones that also name a payee
#   ("DUKE ENERGY ... AGGREGATED NON MEDIA EXPENSE", 138 rows) are kept. payee_* = who was paid (Name, Street Line 1,
#   ...), comm_* = the paying committee (Committee Name, Committee SBoE ID, Committee Street 1, ...).
# - Layout: the earlier build's 36 columns in its order (payee_name ... declaration, supports, na_flag, dupe_flag,
#   year, payee_street_clean, comm_street_clean, payee_state_clean, comm_state_clean, payee_zip_clean, comm_zip_clean,
#   payee_city_clean, comm_city_clean). supports = declaration is "Support" (any case). date as YYYY-MM-DD, amount as a
#   number.
# - All rows kept. na_flag: date, amount, payee_name or comm_name missing. dupe_flag: every copy of a row identical on
#   all source columns. year = year(date).
library(here)
here::i_am("state/nc/code/nc_expends.R")
source(here("state", "nc", "code", "nc_common.R"))
NAMES <- c("payee_name", "payee_street1", "payee_street2", "payee_city", "payee_state", "payee_zip", "profession",
           "employer", "transction_type", "comm_name", "comm_id", "comm_street1", "comm_street2", "comm_city",
           "comm_state", "comm_zip", "report_name", "date", "account_code", "amount", "form_of_payment", "purpose",
           "referendum_name", "declaration")
LAYOUT <- c(NAMES, "supports", "na_flag", "dupe_flag", "year", "payee_street_clean", "comm_street_clean",
            "payee_state_clean", "comm_state_clean", "payee_zip_clean", "comm_zip_clean", "payee_city_clean",
            "comm_city_clean")
PARTIES <- list(
  list(src = c("payee_street1", "payee_street2", "payee_city", "payee_state", "payee_zip"),
       out = c("payee_street_clean", "payee_city_clean", "payee_state_clean", "payee_zip_clean")),
  list(src = c("comm_street1", "comm_street2", "comm_city", "comm_state", "comm_zip"),
       out = c("comm_street_clean", "comm_city_clean", "comm_state_clean", "comm_zip_clean")))
out_dir <- dir_create(here("state", "nc", "expends", "data", "clean"))
build_nc(here("state", "nc", "data", "parsed", "nc_expenditures.csv"), NAMES, c("payee_name", "comm_name"), PARTIES,
         LAYOUT, "nc_expends", out_dir,
         extra = function(x) x[, supports := !is.na(declaration) & toupper(trimws(declaration)) == "SUPPORT"],
         drop = function(x) !is.na(x$payee_name) &
           grepl("^\\s*aggregated?\\s+(non[- ]?media\\s*)?(expenditures?|expenses?|exp\\.?)?\\s*$", x$payee_name, ignore.case = TRUE))
