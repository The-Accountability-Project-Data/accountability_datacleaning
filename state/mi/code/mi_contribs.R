# Michigan campaign contributions -- rebuild 1998-2026, November 2026 (replaces mi_contribs_clean.csv and
# mi_contribs_clean_2021-2022.csv with one file).
#   Rscript state/mi/code/mi_contribs.R from the repo root. Raw: state/mi/data/raw/Contribution_<YYYY>/*.txt (the
#   unzipped MiTN all-transaction export, retrieved 2026-11-16). Output: state/mi/contribs/data/clean/.
#
# Follows state/mi/contribs/docs/mi_contribs_diary.Rmd ("Update: November 2026"):
# - Source fields renamed to the old names: common_name_acronym -> common_name, contributor_f_name -> f_name,
#   contributor_l_name_or_org -> l_name_or_org, contributor_address/city/state/zip/occupation/employer ->
#   address/city/state/zip/occupation/employer. page_no is no longer in the source (kept, empty).
# - All rows kept. Statements filed more than once (same committee, year and statement type) mostly add items rather
#   than restate them, so no rows are dropped as superseded.
# - na_flag: received_date, l_name_or_org, amount or com_legal_name missing. dupe_flag: every copy of a row identical
#   within its statement year on every column but doc_seq_no, page_no, contribution_id, cont_detail_id.
# - received_year = year(received_date). address_clean, zip_clean, state_clean (US states and Canadian provinces),
#   city_clean (normalized; swapped with the ZIP code's city when an abbreviation or one edit away, otherwise kept;
#   then refined where the refined city/state/ZIP is valid).
# - Output: the columns of mi_contribs_clean_2021-2022.csv, in its order, then fundraiser, can_political_party,
#   can_office_sought, can_district_sought (new in the source).
# - Filings no longer in the MiTN export: the rows of the earlier files whose doc_seq_no is not in the export at all
#   (613,689 rows; state/mi/code/carry_over.py, run first) are added as they were in those files, including their
#   clean columns; the four new columns are empty; their cfr_com_id is padded to the state's 7 digits. na_flag and dupe_flag are computed on the combined rows; dupe_flag
#   compares the source columns of the earlier layout (not the four new ones).
library(here)
here::i_am("state/mi/code/mi_contribs.R")
source(here("state", "mi", "code", "mi_common.R"))
out_dir <- dir_create(here("state", "mi", "contribs", "data", "clean"))
tmp_dir <- dir_create(here("state", "mi", "contribs", "data", "tmp"))
OLD <- c("doc_seq_no", "page_no", "contribution_id", "cont_detail_id", "doc_stmnt_year", "doc_type_desc",
         "com_legal_name", "common_name", "cfr_com_id", "com_type", "can_first_name", "can_last_name", "contribtype",
         "f_name", "l_name_or_org", "address", "city", "state", "zip", "occupation", "employer", "received_date",
         "amount", "aggregate", "extra_desc", "na_flag", "dupe_flag", "received_year", "address_clean", "city_clean",
         "state_clean", "zip_clean")
NEW <- c("fundraiser", "can_political_party", "can_office_sought", "can_district_sought")
ID_COLS <- c("doc_seq_no", "page_no", "contribution_id", "cont_detail_id")
carry <- fread(here("state", "mi", "contribs", "data", "carry", "carry_over.csv"), colClasses = "character",
               na.strings = "", encoding = "UTF-8")
carry[, source_file := NULL]
carry[, cfr_com_id := str_pad(cfr_com_id, 7, pad = "0")]   # earlier files dropped the leading zeros
carry[, received_date := as.IDate(received_date)][, amount := parse_num(amount)][, aggregate := parse_num(aggregate)]
carry[, received_year := as.integer(received_year)]
carry[, c("na_flag", "dupe_flag") := NULL]
cat("carried over:", nrow(carry), "\n")
DUPE_COLS <- setdiff(OLD, c(ID_COLS, "na_flag", "dupe_flag", "received_year", "address_clean", "city_clean",
                            "state_clean", "zip_clean"))
years <- if (nzchar(Sys.getenv("MI_YEARS"))) eval(parse(text = Sys.getenv("MI_YEARS"))) else 1998:2026  # MI_YEARS for a test run
swaps <- list(); counts <- list()

# Pass 1: per statement year, read, flag, normalize; keep city_swap for the refine step.
for (y in years) {
  x <- read_mi("Contribution", y)
  setnames(x, c("common_name_acronym", "contributor_f_name", "contributor_l_name_or_org", "contributor_address",
                "contributor_city", "contributor_state", "contributor_zip", "contributor_occupation",
                "contributor_employer"),
           c("common_name", "f_name", "l_name_or_org", "address", "city", "state", "zip", "occupation", "employer"))
  x[, page_no := NA_character_]
  stopifnot(all(x$doc_stmnt_year == as.character(y)))
  x[, received_date := parse_mdy(received_date)]
  x[, amount := parse_num(amount)][, aggregate := parse_num(aggregate)]
  x[, received_year := year(received_date)]
  x[, address_clean := norm_address(address)]
  x[, zip_clean := norm_zip(zip)]
  x[, state_clean := norm_state(state)]
  x[, city_norm := norm_city(city)]
  x[, city_swap := do_city_swap(city_norm, state_clean, zip_clean)]
  swaps[[as.character(y)]] <- x[, .(city_swap, state_clean, zip_clean)]
  x[, carried := FALSE]
  cy <- carry[doc_stmnt_year == as.character(y)]
  if (nrow(cy)) x <- rbind(x, cy[, carried := TRUE], fill = TRUE)
  x[, na_flag := is.na(received_date) | is.na(l_name_or_org) | is.na(amount) | is.na(com_legal_name)]
  x[, dupe_flag := duplicated(x, by = DUPE_COLS) | duplicated(x, by = DUPE_COLS, fromLast = TRUE)]
  counts[[as.character(y)]] <- data.table(year = y, rows = nrow(x), carried = sum(x$carried), na_flag = sum(x$na_flag),
                                          dupe_flag = sum(x$dupe_flag))
  saveRDS(x, path(tmp_dir, paste0(y, ".rds")), compress = FALSE)
  cat(y, nrow(x), "rows (", sum(x$carried), "carried over ); na_flag", sum(x$na_flag), "dupe_flag", sum(x$dupe_flag), "\n")
  rm(x); invisible(gc(verbose = FALSE))
}

# Refine over the whole column.
sw <- rbindlist(swaps); rm(swaps); invisible(gc(verbose = FALSE))
good <- refine_map(sw$city_swap, sw$state_clean, sw$zip_clean)
cat("refine: city/state/ZIP combinations changed:", nrow(good), "\n")
rm(sw); invisible(gc(verbose = FALSE))
setnames(good, c("state_norm", "zip_norm"), c("state_clean", "zip_clean"))

# Pass 2: apply the refine, write in the old column order plus the new columns.
out <- path(out_dir, "mi_contribs_1998-2026.csv")
if (file_exists(out)) file_delete(out)
for (y in years) {
  x <- readRDS(path(tmp_dir, paste0(y, ".rds")))
  n0 <- nrow(x)
  x[good, city_refine := i.city_refine, on = c("city_swap", "state_clean", "zip_clean")]
  x[carried == FALSE, city_clean := fcoalesce(city_refine, city_swap)]   # carried rows keep their earlier city_clean
  stopifnot(nrow(x) == n0)
  fwrite(x[, c(OLD, NEW), with = FALSE], out, append = file_exists(out), na = "", dateTimeAs = "ISO")
  rm(x); invisible(gc(verbose = FALSE))
}
print(rbindlist(counts))
cat("wrote", out, sum(rbindlist(counts)$rows), "rows,", length(c(OLD, NEW)), "columns\n")
dir_delete(tmp_dir)
