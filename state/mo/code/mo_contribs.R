# Missouri campaign contributions -- rebuild 2011-2026, November 2026 (replaces mo_contribs_clean.csv and
# mo_contribs_clean_2020-2022.csv). Rscript state/mo/code/mo_contribs.R <raw dir>, from the repo root.
# Output: state/mo/contribs/data/clean/mo_contribs_2011-2026.csv.
#
# - Source and reading: see mo_common.R (Form CD1 Part A, 2011-2026).
# - Layout: the 25 columns of mo_contribs_clean_2020-2022.csv: the source headers in snake case (cd1_a_id, mecid,
#   committee_name, ..., contribution_type, report), then na_flag, dupe_flag, year, address_clean, zip_clean,
#   state_clean, city_clean. date as YYYY-MM-DD (the source adds " 12:00:00 AM"), amount as a number; everything else
#   as published.
# - All rows kept. na_flag: date, contributor (last_name, company and committee -- the
#   contributing committee -- all), amount, committee_name or address_1
#   missing (the earlier build flagged every row without last_name, i.e. every company). dupe_flag: every
#   copy of a row identical on all columns but cd1_a_id. year = year(date).
# - address_clean (address 1 + 2), zip_clean, state_clean, city_clean (normalized; swapped with the ZIP code's city
#   when an abbreviation or one edit away; refined where the refined city/state/ZIP is valid).
library(here)
here::i_am("state/mo/code/mo_contribs.R")
source(here("state", "mo", "code", "mo_common.R"))
raw <- commandArgs(TRUE)[1]
out_dir <- dir_create(here("state", "mo", "contribs", "data", "clean"))
SRC <- c("cd1_a_id", "mecid", "committee_name", "committee", "company", "first_name", "last_name", "address_1",
         "address_2", "city", "state", "zip", "employer", "occupation", "date", "amount", "contribution_type", "report")
LAYOUT <- c(SRC, "na_flag", "dupe_flag", "year", "address_clean", "zip_clean", "state_clean", "city_clean")

mo <- read_year_files(raw, "CD1A")
stopifnot(identical(names(mo), SRC), !anyDuplicated(mo$cd1_a_id))
cat("rows:", nrow(mo), "\n")
mo[, date := parse_mec_date(date)]
mo[, amount := parse_amount(amount)]
mo[, na_flag := is.na(date) | (is.na(last_name) & is.na(company) & is.na(committee)) | is.na(amount) | is.na(committee_name) | is.na(address_1)]
DUPE <- setdiff(SRC, "cd1_a_id")
mo[, dupe_flag := duplicated(mo, by = DUPE) | duplicated(mo, by = DUPE, fromLast = TRUE)]
mo[, year := year(date)]
mo[, address_clean := norm_address(na_blank(str_squish(paste(fcoalesce(address_1, ""), fcoalesce(address_2, "")))))]
mo[, zip_clean := norm_zip(zip)]
mo[, state_clean := norm_state(state)]
mo[, city_norm := norm_city(city)]
mo[, city_swap := do_city_swap(city_norm, state_clean, zip_clean)]
mo[, city_clean := do_refine(city_swap, state_clean, zip_clean)]
out <- path(out_dir, "mo_contribs_2011-2026.csv")
fwrite(mo[, ..LAYOUT], out, na = "", dateTimeAs = "ISO")
cat("na_flag", sum(mo$na_flag), " dupe_flag", sum(mo$dupe_flag), " date missing", sum(is.na(mo$date)), "\n")
print(mo[, .N, keyby = year], nrows = 60)
cat("wrote", out, nrow(mo), "rows,", length(LAYOUT), "columns\n")
