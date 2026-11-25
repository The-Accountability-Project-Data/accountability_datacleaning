# Missouri campaign expenditures -- rebuild 2011-2026, November 2026 (replaces mo_expends_clean.csv).
#   Rscript state/mo/code/mo_expends.R <raw dir>, from the repo root.
# Output: state/mo/expends/data/clean/mo_expends_2011-2026.csv.
#
# - Source and reading: see mo_common.R (Form CD3 Part B, itemized expenditures over $100, 2011-2026).
# - Layout: the 28 columns of the earlier file, same names and order: the source headers in snake case (cd3_b_id,
#   mecid, committee_name, first_name, last_name, company, address_1, address_2, state, zip, date, purpose, amount,
#   expenditure_type, report; city as city_raw), plus adress_full (address 1 + 2, joined with a space; the earlier
#   file joined them with "_"), individual (last name, else first name), payee_name (individual, else company),
#   na_flag, dupe_flag, date_flag, date_clean, year_clean, address_norm, zip_norm, state_norm, city_final.
#   date as YYYY-MM-DD, amount as a number; everything else as published.
# - All rows kept. na_flag: payee_name, committee_name, date or amount missing. dupe_flag: every copy of a row
#   identical on all source columns but cd3_b_id. date_flag: date before 2010 or after 2026-11-17; date_clean is date
#   without the flagged dates; year_clean = year(date_clean).
# - address_norm, zip_norm, state_norm, city_final (normalized; swapped with the ZIP code's city when an abbreviation
#   or one edit away; refined where the refined city/state/ZIP is valid).
library(here)
here::i_am("state/mo/code/mo_expends.R")
source(here("state", "mo", "code", "mo_common.R"))
raw <- commandArgs(TRUE)[1]
out_dir <- dir_create(here("state", "mo", "expends", "data", "clean"))
SRC <- c("cd3_b_id", "mecid", "committee_name", "first_name", "last_name", "company", "address_1", "address_2", "city",
         "state", "zip", "date", "purpose", "amount", "expenditure_type", "report")
LAYOUT <- c("cd3_b_id", "mecid", "committee_name", "first_name", "last_name", "company", "adress_full", "address_1",
            "address_2", "city_raw", "state", "zip", "date", "purpose", "amount", "expenditure_type", "report",
            "individual", "payee_name", "na_flag", "dupe_flag", "date_flag", "date_clean", "year_clean", "address_norm",
            "zip_norm", "state_norm", "city_final")
stopifnot(length(LAYOUT) == 28)

mo <- read_year_files(raw, "CD3B")
stopifnot(identical(names(mo), SRC), !anyDuplicated(mo$cd3_b_id))
cat("rows:", nrow(mo), "\n")
mo[, date := parse_mec_date(date)]
mo[, amount := parse_amount(amount)]
mo[, individual := fcoalesce(last_name, first_name)]
mo[, payee_name := fcoalesce(individual, company)]
mo[, na_flag := is.na(payee_name) | is.na(committee_name) | is.na(date) | is.na(amount)]
DUPE <- setdiff(SRC, "cd3_b_id")
mo[, dupe_flag := duplicated(mo, by = DUPE) | duplicated(mo, by = DUPE, fromLast = TRUE)]
mo[, date_flag := !is.na(date) & (year(date) < 2010 | date > as.IDate("2026-11-17"))]
mo[, date_clean := fifelse(date_flag, as.IDate(NA), date)]
mo[, year_clean := year(date_clean)]
mo[, adress_full := na_blank(str_squish(paste(fcoalesce(address_1, ""), fcoalesce(address_2, ""))))]
mo[, address_norm := norm_address(adress_full)]
mo[, zip_norm := norm_zip(zip)]
mo[, state_norm := norm_state(state)]
mo[, city_raw := city]
mo[, city_norm := norm_city(city)]
mo[, city_swap := do_city_swap(city_norm, state_norm, zip_norm)]
mo[, city_final := do_refine(city_swap, state_norm, zip_norm)]
out <- path(out_dir, "mo_expends_2011-2026.csv")
fwrite(mo[, ..LAYOUT], out, na = "", dateTimeAs = "ISO")
cat("na_flag", sum(mo$na_flag), " dupe_flag", sum(mo$dupe_flag), " date_flag", sum(mo$date_flag), "\n")
print(mo[, .N, keyby = year_clean], nrows = 60)
cat("wrote", out, nrow(mo), "rows,", length(LAYOUT), "columns\n")
