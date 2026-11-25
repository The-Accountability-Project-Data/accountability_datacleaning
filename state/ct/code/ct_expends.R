# Connecticut campaign expenditures -- rebuild 2008-2026, November 2026 (replaces ct_expends_clean.csv).
#   Rscript state/ct/code/ct_expends.R <raw dir>, from the repo root.
# Output: state/ct/expends/data/clean/ct_expends_2008-2026.csv.
#
# - Source and reading: see ct_common.R. Disbursements files only.
# - Layout: the 39 columns of the earlier file, in the same order, with the same names (source headers in snake case;
#   the candidate files' second Description column -> description_1; file = the source file name without extension,
#   in capitals). Values as published (whitespace squished); the earlier build had changed every value to capitals and
#   blanked "NO", "VOID", "VOIDED" and "-".
# - amended = status is "Amendment"; efiled = data_source is "eFILE" (any case). All rows are kept: amended reports are
#   separate reports that rarely repeat the rows of the earlier report (2024 candidate file: 8 of 3,813 rows).
# - date_clean from payment_date (m/d/yyyy); year_clean = its year, missing outside 1998-2026. na_flag: payee, amount,
#   date_clean or committee missing.
# - address_clean, state_clean, city_norm (normalized), city_clean (= city_norm; the source has no ZIP code, so there
#   is no swap or refine).
library(here)
here::i_am("state/ct/code/ct_expends.R")
source(here("state", "ct", "code", "ct_common.R"))
raw <- commandArgs(TRUE)[1]
out_dir <- dir_create(here("state", "ct", "expends", "data", "clean"))

SRC <- c("committee", "committee_type", "payee", "purpose_of_expenditure", "description", "payment_method",
         "payment_date", "amount", "file_to_state", "period_start", "period_end", "election_year", "status",
         "data_source", "refiled_electronically", "street_address", "city", "state", "fundraising_event", "report_name",
         "committee_id", "section_letter", "section_name", "report_id", "candidate_first_name",
         "candidate_middle_intial", "candidate_last_name", "form", "description_1")
LAYOUT <- c("file", SRC, "amended", "efiled", "date_clean", "year_clean", "na_flag", "address_clean", "state_clean",
            "city_norm", "city_clean")
stopifnot(length(LAYOUT) == 39)
snake <- function(h) gsub("_+", "_", gsub("[^a-z0-9]+", "_", tolower(trimws(h))))

files <- sort(dir_ls(raw, regexp = "(?i)/Disbursements\\d{4}.*\\.(csv|xlsx)$"))
cat(length(files), "files\n")
parts <- list()
for (f in files) {
  b <- basename(f)
  x <- read_source(f)
  h <- snake(names(x)); d <- which(h == "description"); if (length(d) > 1) h[d[-1]] <- "description_1"
  setnames(x, h)
  miss <- setdiff(names(x), SRC); if (length(miss)) stop(b, ": unknown columns ", paste(miss, collapse = ", "))
  set(x, j = "file", value = toupper(path_ext_remove(b)))
  cat(b, nrow(x), "rows;", attr(x, "cp1252_lines"), "windows-1252 lines\n")
  parts[[b]] <- x
}
ct <- rbindlist(parts, use.names = TRUE, fill = TRUE); rm(parts); invisible(gc(verbose = FALSE))
for (j in setdiff(LAYOUT, names(ct))) set(ct, j = j, value = NA_character_)
cat("rows:", nrow(ct), "\n")

ct[, amount := parse_amount(amount)]
ct[, amended := !is.na(status) & tolower(status) == "amendment"]
ct[, efiled := !is.na(data_source) & tolower(data_source) == "efile"]
ct[, date_clean := parse_mdy(payment_date)]
ct[, year_clean := year(date_clean)]
ct[year_clean < 1998 | year_clean > 2026, year_clean := NA_integer_]
ct[, na_flag := is.na(payee) | is.na(amount) | is.na(date_clean) | is.na(committee)]
ct[, address_clean := norm_address(street_address)]
ct[, state_clean := norm_state(state)]
ct[, city_norm := norm_city(city)]
ct[, city_clean := city_norm]

out <- path(out_dir, "ct_expends_2008-2026.csv")
fwrite(ct[, ..LAYOUT], out, na = "", dateTimeAs = "ISO")
print(ct[, .N, by = .(status)]); print(ct[, .N, by = .(data_source)])
cat("na_flag", sum(ct$na_flag), " date missing", sum(is.na(ct$date_clean)), " amended", sum(ct$amended), "\n")
print(ct[, .N, keyby = year_clean], nrows = 60)
cat("wrote", out, nrow(ct), "rows,", length(LAYOUT), "columns\n")
