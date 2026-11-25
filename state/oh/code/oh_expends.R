# Ohio campaign expenditures -- rebuild, November 2026 (replaces oh_expends_clean.csv; new layout).
#   python3 state/oh/code/reparse.py <raw dir> expenditures state/oh/expends/data/parsed/oh_expends.csv, then
#   Rscript state/oh/code/oh_expends.R, from the repo root. Output: state/oh/expends/data/clean/.
#
# - Source: the Ohio Campaign Finance System (https://campaignfinance.ohiosos.gov), "All Candidate & Non-Candidate
#   Committee Files", Expenditure by year, downloaded November 2026. Format notes in reparse.py and oh_common.R.
# - New layout: the source columns (snake case of the headers), in the source order, then payee_name, na_flag,
#   dupe_flag, year, address_clean, city_clean, state_clean, zip_clean. Dates as YYYY-MM-DD, transaction_amount and
#   amount_applied_to_candidate_ballot_issue as numbers; ZIPs without the export's ="..." wrapper (reparse.py);
#   everything else as published.
# - All rows kept (current report versions only; see oh_common.R).
# - payee_name = payee entity name, or first + middle + last name.
# - na_flag: transaction_date, payee_name, transaction_amount or filing_entity_name missing. dupe_flag: every copy of a
#   row identical within its source file (year) on every column but transaction_id.
# - The export's "NA" placeholder for a missing address is treated as missing in the *_clean columns.
# - year = year(transaction_date). address_clean (address lines 1 + 2), zip_clean, state_clean (US states and Canadian
#   provinces), city_clean (normalized; swapped with the ZIP code's city when an abbreviation or one edit away,
#   otherwise kept; then refined where the refined city/state/ZIP is valid).
library(here)
here::i_am("state/oh/code/oh_expends.R")
source(here("state", "oh", "code", "oh_common.R"))
out_dir <- dir_create(here("state", "oh", "expends", "data", "clean"))
tmp_dir <- dir_create(here("state", "oh", "expends", "data", "tmp"))
DATES <- c("transaction_date", "timed_report_filed_date", "report_filed_date")
AMOUNTS <- c("transaction_amount", "amount_applied_to_candidate_ballot_issue")
ADD <- c("payee_name", "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")

all <- read_parsed("expends")
SRC <- setdiff(names(all), "source_file")
stopifnot(length(SRC) == 34, !anyNA(all$transaction_id))
cat("rows:", nrow(all), " repeated transaction_id:", sum(duplicated(all$transaction_id)), "\n")
files <- sort(unique(all$source_file))
if (nzchar(Sys.getenv("OH_YEARS"))) files <- files[str_extract(files, "\\d{4}") %in% strsplit(Sys.getenv("OH_YEARS"), ",")[[1]]]
DUPE_COLS <- setdiff(SRC, "transaction_id")
swaps <- list(); counts <- list()

# Pass 1: per source file (year): types, flags, normalization; keep city_swap for the refine step.
for (f in files) {
  x <- all[source_file == f]
  for (j in DATES) set(x, j = j, value = parse_mdy(x[[j]]))
  for (j in AMOUNTS) set(x, j = j, value = parse_dollars(x[[j]]))
  x[, payee_name := fcoalesce(payee_entity_name,
                              na_if_blank(trimws(gsub("\\s+", " ", paste(fcoalesce(payee_first_name, ""),
                                                                          fcoalesce(payee_middle_name, ""),
                                                                          fcoalesce(payee_last_name, ""))))))]
  x[, na_flag := is.na(transaction_date) | is.na(payee_name) | is.na(transaction_amount) | is.na(filing_entity_name)]
  x[, dupe_flag := duplicated(x, by = DUPE_COLS) | duplicated(x, by = DUPE_COLS, fromLast = TRUE)]
  x[, year := year(transaction_date)]
  addr <- na_if_blank(trimws(paste(fcoalesce(na_text(x$payee_address_line_1), ""),
                                   fcoalesce(na_text(x$payee_address_line_2), ""))))
  x[, address_clean := norm_address(addr)]
  x[, zip_clean := norm_zip(na_text(payee_address_zip_code))]
  x[, state_clean := norm_state(na_text(payee_address_state))]
  x[, city_norm := norm_city(na_text(payee_address_city))]
  x[, city_swap := do_city_swap(city_norm, state_clean, zip_clean)]
  swaps[[f]] <- x[, .(city_swap, state_clean, zip_clean)]
  counts[[f]] <- data.table(file = f, rows = nrow(x), na_flag = sum(x$na_flag), dupe_flag = sum(x$dupe_flag),
                            min_date = min(x$transaction_date, na.rm = TRUE), max_date = max(x$transaction_date, na.rm = TRUE))
  saveRDS(x, path(tmp_dir, paste0(f, ".rds")), compress = FALSE)
  cat(f, nrow(x), "rows; na_flag", sum(x$na_flag), "dupe_flag", sum(x$dupe_flag), "\n")
  rm(x); invisible(gc(verbose = FALSE))
}
rm(all); invisible(gc(verbose = FALSE))

# Refine over the whole column.
sw <- rbindlist(swaps); rm(swaps); invisible(gc(verbose = FALSE))
good <- refine_map(sw$city_swap, sw$state_clean, sw$zip_clean)
cat("refine: city/state/ZIP combinations changed:", nrow(good), "\n")
rm(sw); invisible(gc(verbose = FALSE))
setnames(good, c("state_norm", "zip_norm"), c("state_clean", "zip_clean"))

# Pass 2: apply the refine and write.
yrs <- range(as.integer(str_extract(files, "\\d{4}")))
out <- path(out_dir, sprintf("oh_expends_%d-%d.csv", yrs[1], yrs[2]))
if (file_exists(out)) file_delete(out)
for (f in files) {
  x <- readRDS(path(tmp_dir, paste0(f, ".rds")))
  n0 <- nrow(x)
  x[good, city_refine := i.city_refine, on = c("city_swap", "state_clean", "zip_clean")]
  x[, city_clean := fcoalesce(city_refine, city_swap)]
  stopifnot(nrow(x) == n0)
  fwrite(x[, c(SRC, ADD), with = FALSE], out, append = file_exists(out), na = "", dateTimeAs = "ISO")
  rm(x); invisible(gc(verbose = FALSE))
}
cnt <- rbindlist(counts)
print(cnt, nrows = 100)
cat("wrote", out, sum(cnt$rows), "rows,", length(c(SRC, ADD)), "columns\n")
dir_delete(tmp_dir)
