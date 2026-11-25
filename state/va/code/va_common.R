# Shared code for the Virginia campaign finance builds (va_contribs.R, va_expends.R). Set va_dataset ("contribs" or
# "expends") before sourcing.
#
# Input: the parsed files from reparse.py (run it first): data/parsed/va_report.csv plus the schedule files. They stack
# every monthly folder of https://apps.elections.virginia.gov/SBE_CSV/CF/ from 2012_03 (the first monthly folder) on.
# Each report appears in the folder of the month it was submitted.
#
# Amended reports: an amendment restates the whole report, so the original's transactions appear again under the
# amendment's ReportId. All versions of a report share ReportUID; AmendmentCount numbers them 0, 1, 2, ... We keep
# only the current version of each report (highest AmendmentCount, then latest SubmittedDate, then highest ReportId)
# and drop the transactions on superseded versions. Counts are printed and written to data/clean/.
suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(tidyr); library(purrr)
  library(lubridate); library(janitor); library(campfin); library(refinr); library(fs); library(glue); library(here)
})
base <- here("state", "va", va_dataset, "data")
parsed_dir <- path(base, "parsed")
out_dir <- dir_create(path(base, "clean"))

read_parsed <- function(file, ...) {
  x <- read_csv(path(parsed_dir, file), na = "", col_types = cols(.default = col_character(), ...),
                progress = FALSE)
  stopifnot(nrow(problems(x)) == 0)
  x
}

rpt_raw <- read_parsed("va_report.csv")
current_rpt <- rpt_raw %>%
  mutate(amend_n = as.integer(AmendmentCount), rid = as.integer(ReportId)) %>%
  arrange(ReportUID, amend_n, SubmittedDate, rid) %>%
  group_by(ReportUID) %>%
  slice_tail(n = 1) %>%
  ungroup() %>%
  pull(ReportId)
cat("reports:", nrow(rpt_raw), " current versions:", length(current_rpt),
    " superseded:", nrow(rpt_raw) - length(current_rpt), "\n")

# Drop transactions on superseded report versions; report and record the count.
drop_superseded <- function(x, label) {
  stopifnot(all(x$ReportId %in% rpt_raw$ReportId))
  keep <- x$ReportId %in% current_rpt
  cat(label, "rows:", nrow(x), " on superseded reports (dropped):", sum(!keep), "\n")
  write_lines(glue("{label}\t{nrow(x)}\t{sum(!keep)}"), path(out_dir, "superseded_dropped.tsv"), append = TRUE)
  x[keep, ]
}

# The transaction date is m/d/Y in Schedules A and D, "Y-m-d H:M:S" in Schedule B.
parse_txn_date <- function(d) {
  out <- if_else(str_detect(d, "^\\d{4}-"), as_date(ymd_hms(d, quiet = TRUE)), mdy(d, quiet = TRUE))
  stopifnot(sum(is.na(out) & !is.na(d)) == 0)
  out
}

# City swap step from the diaries: replace the normalized city with the ZIP code's city when it is an abbreviation
# of it or one edit away; otherwise keep the normalized city. (The diaries' condition was NA when the ZIP had no
# match, which blanked the clean city of 5-10% of rows in the earlier files.)
city_swap <- function(city_norm, state, zip_norm) {
  tibble(city_norm, state, zip_norm) %>%
    left_join(zipcodes, by = c("state" = "state", "zip_norm" = "zip")) %>%
    mutate(
      match_abb = is_abbrev(city_norm, city),
      match_dist = str_dist(city_norm, city),
      swap = if_else(!is.na(city) & !is.na(city_norm) & (match_abb | match_dist == 1), city, city_norm)
    ) %>%
    pull(swap)
}

# normal_address on each distinct combination of the address columns, united with spaces (the diaries' method),
# joined back to the rows. Returns the normalized address, one per row of x.
norm_addr <- function(x, cols) {
  key <- x[cols]
  u <- distinct(key) %>%
    unite("full", all_of(cols), sep = " ", remove = FALSE, na.rm = TRUE) %>%
    mutate(norm = normal_address(full, abbs = usps_street, na_rep = TRUE)) %>%
    select(-full)
  left_join(key, u, by = cols)$norm
}

# Write the output with exactly the old file's columns, in its order.
write_like_old <- function(x, old_file, new_file) {
  old_hdr <- names(read_csv(path(base, "old", old_file), n_max = 0, col_types = cols(.default = "c")))
  missing <- setdiff(old_hdr, names(x))
  if (length(missing)) stop("missing columns: ", paste(missing, collapse = ", "))
  extra <- setdiff(names(x), old_hdr)
  if (length(extra)) cat("not written (not in the old file):", paste(extra, collapse = ", "), "\n")
  x <- select(x, all_of(old_hdr))
  write_csv(x, path(out_dir, new_file), na = "")
  cat("wrote", new_file, nrow(x), "rows,", ncol(x), "columns\n")
  invisible(x)
}
