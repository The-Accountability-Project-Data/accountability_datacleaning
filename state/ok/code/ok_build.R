# Oklahoma campaign contributions and expenditures -- rebuild 2014-2026, November 2026.
#   Rscript state/ok/code/ok_build.R <unzipped raw dir> contribs|expends, from the repo root.
# Output: state/ok/contribs/data/clean/ok_contribs_2014-2026.csv (replaces ok_contribs_2015-20210910.csv) or
#         state/ok/expends/data/clean/ok_expends_2014-2026.csv (replaces ok_expends_20140127-20220218.csv).
#
# - Source and reading: see ok_common.R.
# - Layout: the 29 columns of the earlier files: the 23 source headers in snake case, then na_flag, dupe_flag,
#   receipt_year / expenditure_year, address_clean, city_clean, zip_clean. Dates as YYYY-MM-DD, amounts as numbers;
#   everything else as published (amended stays Y/N; the earlier contributions file had TRUE/FALSE).
# - All rows kept. na_flag: date, last_name or amount missing, or both committee_name and candidate_name missing.
#   dupe_flag: every copy of a row identical on all columns but the receipt / expenditure ID. year from the date.
# - address_clean (address 1 + 2), zip_clean, city_clean (normalized; swapped with the ZIP code's city when an
#   abbreviation or one edit away; refined where the refined city/state/ZIP is valid).
library(here)
here::i_am("state/ok/code/ok_build.R")
source(here("state", "ok", "code", "ok_common.R"))
args <- commandArgs(TRUE); raw <- args[1]; kind <- args[2]
stopifnot(kind %in% c("contribs", "expends"))
pre <- if (kind == "contribs") "receipt" else "expenditure"
pat <- if (kind == "contribs") "ContributionLoanExtract" else "ExpenditureExtract"
out_dir <- dir_create(here("state", "ok", kind, "data", "clean"))

files <- sort(dir_ls(raw, regexp = paste0("/\\d{4}_", pat, "\\.csv$")))
ok <- rbindlist(lapply(files, read_extract), use.names = TRUE)
setnames(ok, snake(names(ok)))
SRC <- names(ok); stopifnot(length(SRC) == 23)
ID <- paste0(pre, "_id"); DATE <- paste0(pre, "_date"); AMT <- paste0(pre, "_amount"); YEAR <- paste0(pre, "_year")
LAYOUT <- c(SRC, "na_flag", "dupe_flag", YEAR, "address_clean", "city_clean", "zip_clean")
dup_ids <- ok[[ID]][!is.na(ok[[ID]]) & duplicated(ok[[ID]])]
cat("rows:", nrow(ok), " missing IDs:", sum(is.na(ok[[ID]])), " repeated IDs:", length(dup_ids), "\n")
if (length(dup_ids)) print(ok[get(ID) %in% dup_ids])
set(ok, j = DATE, value = parse_mdy(ok[[DATE]]))
set(ok, j = "filed_date", value = parse_mdy(ok$filed_date))
set(ok, j = AMT, value = parse_amount(ok[[AMT]]))
ok[, na_flag := is.na(get(DATE)) | is.na(last_name) | is.na(get(AMT)) | (is.na(committee_name) & is.na(candidate_name))]
DUPE <- setdiff(SRC, ID)
ok[, dupe_flag := duplicated(ok, by = DUPE) | duplicated(ok, by = DUPE, fromLast = TRUE)]
set(ok, j = YEAR, value = year(ok[[DATE]]))
ok[, address_clean := norm_address(fifelse(is.na(address_1) & is.na(address_2), NA_character_,
                                           str_squish(paste(fcoalesce(address_1, ""), fcoalesce(address_2, "")))))]
ok[, zip_clean := norm_zip(zip)]
ok[, state_norm := norm_state(state)]
ok[, city_norm := norm_city(city)]
ok[, city_swap := do_city_swap(city_norm, state_norm, zip_clean)]
ok[, city_clean := do_refine(city_swap, state_norm, zip_clean)]
yrs <- range(ok[[YEAR]][ok[[YEAR]] >= 2014 & ok[[YEAR]] <= 2026], na.rm = TRUE)
out <- path(out_dir, sprintf("ok_%s_2014-2026.csv", kind))
fwrite(ok[, ..LAYOUT], out, na = "", dateTimeAs = "ISO")
cat("na_flag", sum(ok$na_flag), " dupe_flag", sum(ok$dupe_flag), " amended Y", sum(ok$amended == "Y", na.rm = TRUE), "\n")
print(ok[, .N, keyby = c(YEAR)], nrows = 80)
cat("wrote", out, nrow(ok), "rows,", length(LAYOUT), "columns\n")
