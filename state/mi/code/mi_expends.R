# Michigan campaign expenditures -- rebuild 1997-2026, November 2026 (replaces mi_expends_clean.csv).
#   Rscript state/mi/code/mi_expends.R from the repo root. Raw: state/mi/data/raw/Expenditure_<YYYY>/*.txt (the
#   unzipped MiTN all-transaction export, retrieved 2026-11-16). Output: state/mi/expends/data/clean/.
#
# Follows state/mi/expends/docs/mi_expends_diary.Rmd ("Update: November 2026"):
# - Source fields renamed to the old names: common_name_acronym -> common_name, payee_f_name -> f_name,
#   payee_l_name_or_org -> lname_or_org; can_or_ballot = candidate, or ballot_question where there is no candidate;
#   office = office_district. No longer in the source (kept, empty): gub_account_type, page_no, schedule_desc,
#   extra_desc, debt_payment, gotv_ink_ind.
# - All rows kept (statements filed more than once mostly add items rather than restate them).
# - na_flag: com_legal_name, lname_or_org or amount missing (no dupe flag, as before).
# - date_clean = exp_date, blank where the year is before 1995 or the date is after the retrieval date;
#   exp_year = year(date_clean).
# - The payee address is normalized: address_norm, zip_norm, state_norm (US states and Canadian provinces),
#   city_swap (normalized city, swapped with the ZIP code's city when an abbreviation or one edit away, otherwise
#   kept), city_refine (refined where the refined city/state/ZIP is valid). The vendor address is kept as filed.
# - Output: the columns of mi_expends_clean.csv, in its order, then payee_address, payee_city, payee_state,
#   payee_zip (the payee address as filed; new in this file), can_political_party, can_office_sought,
#   can_district_sought.
# - Filings no longer in the MiTN export: the rows of the earlier file whose doc_seq_no is not in the export at all
#   (19,587 rows; state/mi/code/carry_over.py, run first) are added as they were in that file, including date_clean,
#   exp_year and the normalized address columns; the new columns are empty; cfr_com_id is padded to the state's 7 digits. na_flag is computed on the combined rows.
library(here)
here::i_am("state/mi/code/mi_expends.R")
source(here("state", "mi", "code", "mi_common.R"))
out_dir <- dir_create(here("state", "mi", "expends", "data", "clean"))
RETRIEVED <- as.IDate("2026-11-16")
OLD <- c("doc_seq_no", "expenditure_type", "gub_account_type", "gub_elec_type", "page_no", "expense_id", "detail_id",
         "doc_stmnt_year", "doc_type_desc", "com_legal_name", "common_name", "cfr_com_id", "com_type", "schedule_desc",
         "exp_desc", "purpose", "extra_desc", "f_name", "lname_or_org", "amount", "state_loc", "supp_opp",
         "can_or_ballot", "office", "county", "debt_payment", "vend_name", "vend_addr", "vend_city", "vend_state",
         "vend_zip", "gotv_ink_ind", "fundraiser", "na_flag", "exp_year", "date_clean", "address_norm", "zip_norm",
         "state_norm", "city_swap", "city_refine")
NEW <- c("payee_address", "payee_city", "payee_state", "payee_zip", "can_political_party", "can_office_sought",
         "can_district_sought")

x <- rbindlist(lapply(1997:2026, function(y) {
  d <- read_mi("Expenditure", y); stopifnot(all(d$doc_stmnt_year == as.character(y))); d
}))
n0 <- nrow(x); cat("rows:", n0, "\n")
setnames(x, c("common_name_acronym", "payee_f_name", "payee_l_name_or_org"), c("common_name", "f_name", "lname_or_org"))
x[, can_or_ballot := fcoalesce(candidate, ballot_question)]
x[, office := office_district]
for (j in c("gub_account_type", "page_no", "schedule_desc", "extra_desc", "debt_payment", "gotv_ink_ind"))
  set(x, j = j, value = NA_character_)
x[, amount := parse_num(amount)]
x[, exp_date := parse_mdy(exp_date)]
x[, na_flag := is.na(com_legal_name) | is.na(lname_or_org) | is.na(amount)]
x[, date_clean := exp_date]
x[year(exp_date) < 1995 | exp_date > RETRIEVED, date_clean := NA]
cat("exp_date missing:", sum(is.na(x$exp_date)), " blanked in date_clean:", sum(is.na(x$date_clean)) - sum(is.na(x$exp_date)), "\n")
x[, exp_year := year(date_clean)]
x[, address_norm := norm_address(payee_address)]
x[, zip_norm := norm_zip(payee_zip)]
x[, state_norm := norm_state(payee_state)]
x[, city_norm := norm_city(payee_city)]
x[, city_swap := do_city_swap(city_norm, state_norm, zip_norm)]
good <- refine_map(x$city_swap, x$state_norm, x$zip_norm)
x[good, city_refine := i.city_refine, on = c("city_swap", "state_norm", "zip_norm")]
cat("cities refined:", sum(!is.na(x$city_refine)), "\n")
x[, city_refine := fcoalesce(city_refine, city_swap)]
x[city_refine == "ELANSING", city_refine := "EAST LANSING"]
stopifnot(nrow(x) == n0)
carry <- fread(here("state", "mi", "expends", "data", "carry", "carry_over.csv"), colClasses = "character",
               na.strings = "", encoding = "UTF-8")
carry[, source_file := NULL][, amount := parse_num(amount)][, date_clean := as.IDate(date_clean)]
carry[, cfr_com_id := str_pad(cfr_com_id, 7, pad = "0")]   # earlier files dropped the leading zeros
carry[, exp_year := as.integer(exp_year)]
cat("carried over:", nrow(carry), "\n")
x <- rbind(x, carry, fill = TRUE)
x[, na_flag := is.na(com_legal_name) | is.na(lname_or_org) | is.na(amount)]
cat("na_flag:", sum(x$na_flag), "\n")
print(x[, .N, by = exp_year][order(exp_year)], nrows = 60)
out <- path(out_dir, "mi_expends_1997-2026.csv")
fwrite(x[, c(OLD, NEW), with = FALSE], out, na = "", dateTimeAs = "ISO")
cat("wrote", out, nrow(x), "rows,", length(c(OLD, NEW)), "columns\n")
