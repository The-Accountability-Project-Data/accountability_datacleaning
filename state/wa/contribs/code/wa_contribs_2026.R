# Washington campaign contributions: update 2026-11-05, replacing wa_contribs_20040101-20210922.csv and
# wa_contribs_clean.csv (built 2022-12-25).
#   Rscript state/wa/contribs/code/wa_contribs_2026.R   # from the repo root
# Inputs under `base` = state/wa/contribs/data (set below): raw/soda/ (the source CSVs) and
# old/wa_contribs_clean.csv.
#
# Builds two files in data/clean/:
#   wa_contribs_2004-2021.csv  OLD PART: wa_contribs_clean.csv (built 2022-12-25) rows with
#                              receipt_date <= 2021-12-31 or no receipt_date, minus the rows from reports the state
#                              has since amended (below). Values as in the old file; the same 42 columns in the same order.
#   wa_contribs_2022-2026.csv  NEW PART: the current source (data.wa.gov kv7h-kjye, 24 per-election-year SODA CSVs
#                              fetched 2026-11-05) rows with receipt_date >= 2022-01-01, plus the
#                              undated source rows whose id is not in the old part. Cleaned with the steps of
#                              state/wa/contribs/docs/wa_contribs_diary.Rmd (Kiernan
#                              Nicholls): flag_na (receipt_date, contributor_name, amount, filer_name), dupe_flag (rows
#                              identical except id), receipt_year = year(receipt_date), normal_zip / normal_state /
#                              normal_city + zipcodes swap + refinr refine -> city_clean, state_clean, zip_clean.
#                              Columns: the old file's 42 in the same order, then fund_id and row_checksum.
#
# Changes from the diary (Nov 2026):
# - Source: the full rows.tsv export failed twice on 2026-11-05 (HTTP 500 body after 5,410,562 rows; broken
#   connection), so the 24 SODA CSVs (resource/kv7h-kjye.csv, one per election_year) are read instead.
# - receipt_date is ISO datetime in the SODA CSV ("2024-08-22T00:00:00.000"); the date part is kept.
# - All source columns are read as text, so values stay as published: amount keeps the source's form ("5000.00";
#   the old file, read as a number, has "5000"). na = "" only (no "NA" strings turned blank), trim_ws = FALSE.
# - Duplicates are flagged within the new part (rows identical in every column but id; receipt_date is one of the
#   columns, so this equals the diary's per-date check). The duplicate-id file is WA's
#   (data/clean/dupe_ids_2022-2026.txt), not the diary's here("il", "contribs", ...).
# - The refine join uses explicit keys (city_swap, state_norm, zip_norm) instead of by = names(.).
# - Plots and tables are skipped.
#
# Superseded (amended) records: the source drops a report's records when it is amended (no flag). OLD-PART rows are
# dropped as superseded when ALL of: id not in the current source; election_year not 1-2008 (the source has dropped
# most 2007-2008 records); amount not blank or 0; report_number not among the current source's report numbers.
# 3,079 rows expected. Their ids are written to data/clean/dropped_amended_ids.csv.
# Left out: the source rows dated <= 2021-12-31 that are not in the old file (12,651), and the 55,078 rows only in
# wa_contribs_20040101-20210922.csv (superseded), which is not read.
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(purrr); library(lubridate)
  library(campfin); library(refinr); library(fs); library(here)
})
base <- here("state", "wa", "contribs", "data")  # holds raw/, old/ and clean/
soda_dir <- path(base, "raw", "soda")
old_csv <- path(base, "old", "wa_contribs_clean.csv")
out_dir <- dir_create(path(base, "clean"))
old_out <- path(out_dir, "wa_contribs_2004-2021.csv")
new_out <- path(out_dir, "wa_contribs_2022-2026.csv")
CUT_OLD <- "2021-12-31"
CUT_NEW <- "2022-01-01"
EXPECT <- list(drop = 3079L, old = 5477754L - 3079L, new_dated = 1549228L, new_undated = 14391L)
say <- function(...) cat(format(Sys.time(), "%H:%M:%S"), sprintf(...), "\n")
chk <- function(name, got, want) {
  say("%s: %s (expected %s)%s", name, format(got, big.mark = ","), format(want, big.mark = ","),
      if (got == want) "" else "  <-- DIFFERS")
}

# ---- source ---------------------------------------------------------------------------------------------------
soda_files <- dir_ls(soda_dir, glob = "*/ey_*.csv")
stopifnot(length(soda_files) == 24)
wac <- map_dfr(soda_files, function(f) {
  read_csv(f, col_types = cols(.default = col_character()), na = "", trim_ws = FALSE, progress = FALSE)
})
say("source rows %s, columns %d", format(nrow(wac), big.mark = ","), ncol(wac))
stopifnot(nrow(wac) == 6414812L, !anyDuplicated(wac$id))
bad_dt <- !is.na(wac$receipt_date) & !str_detect(wac$receipt_date, "^\\d{4}-\\d{2}-\\d{2}T00:00:00\\.000$")
say("receipt_date values not like YYYY-MM-DDT00:00:00.000: %d", sum(bad_dt))
stopifnot(sum(bad_dt) == 0)
wac <- mutate(wac, receipt_date = str_sub(receipt_date, 1, 10))
src_ids <- wac$id
src_reports <- unique(wac$report_number)

# ---- old part -------------------------------------------------------------------------------------------------
old <- read_csv(old_csv, col_types = cols(.default = col_character()), na = "", trim_ws = FALSE, progress = FALSE)
old_cols <- names(old)
stopifnot(length(old_cols) == 42, nrow(old) == 5952878L)
old <- filter(old, is.na(receipt_date) | receipt_date <= CUT_OLD)
say("old-file rows dated <= %s or undated: %s (undated %s)", CUT_OLD, format(nrow(old), big.mark = ","),
    format(sum(is.na(old$receipt_date)), big.mark = ","))
ey <- suppressWarnings(as.integer(old$election_year))
amt <- suppressWarnings(as.numeric(old$amount))
superseded <- !(old$id %in% src_ids) &
  !(!is.na(ey) & ey > 0 & ey <= 2008) &
  !(is.na(amt) | amt == 0) &
  !(old$report_number %in% src_reports)
chk("old rows dropped (report since amended)", sum(superseded), EXPECT$drop)
old %>%
  filter(superseded) %>%
  select(id, report_number, election_year, receipt_date, amount, filer_id, filer_name) %>%
  write_csv(path(out_dir, "dropped_amended_ids.csv"), na = "")
say("dropped rows by election year: %s",
    paste(names(table(old$election_year[superseded])), table(old$election_year[superseded]), sep = "=", collapse = " "))
say("dropped rows amount sum: %.2f", sum(amt[superseded]))
old <- old[!superseded, ]
rm(ey, amt, superseded)
chk("old part rows", nrow(old), EXPECT$old)
gone <- !(old$id %in% src_ids)
ey <- suppressWarnings(as.integer(old$election_year))
say("old part rows no longer in the source: %s (election year 2007-2008: %s; other: %s)",
    format(sum(gone), big.mark = ","), format(sum(gone & ey %in% 2007:2008), big.mark = ","),
    format(sum(gone & !(ey %in% 2007:2008)), big.mark = ","))
rm(gone, ey)
write_csv(old, old_out, na = "")
say("wrote %s", old_out)
old_ids <- old$id
rm(old); invisible(gc())

# ---- new part: select rows ------------------------------------------------------------------------------------
new_dated <- !is.na(wac$receipt_date) & wac$receipt_date >= CUT_NEW
new_undated <- is.na(wac$receipt_date) & !(wac$id %in% old_ids)
chk("new part rows dated >= 2022-01-01", sum(new_dated), EXPECT$new_dated)
chk("new part undated rows not in old part", sum(new_undated), EXPECT$new_undated)
left_out <- !is.na(wac$receipt_date) & wac$receipt_date <= CUT_OLD & !(wac$id %in% old_ids)
say("left out: source rows dated <= %s not in the old part: %s", CUT_OLD, format(sum(left_out), big.mark = ","))
lo <- table(str_sub(wac$receipt_date[left_out], 1, 4))
say("  by receipt year: %s", paste(names(lo), lo, sep = "=", collapse = " "))
wac <- wac[new_dated | new_undated, ]
rm(new_dated, new_undated, left_out, src_ids, src_reports); invisible(gc())
stopifnot(!any(wac$id %in% old_ids))
wac <- mutate(wac, receipt_date = as_date(receipt_date))

# ---- new part: diary steps ------------------------------------------------------------------------------------
key_vars <- c("receipt_date", "contributor_name", "amount", "filer_name")
wac <- flag_na(wac, all_of(key_vars))
say("na_flag %s", format(sum(wac$na_flag), big.mark = ","))

dupe_file <- path(out_dir, "dupe_ids_2022-2026.txt")
d_all <- select(wac, -id)
dupe_vec <- duplicated(d_all, fromLast = FALSE) | duplicated(d_all, fromLast = TRUE)
rm(d_all)
write_lines(wac$id[dupe_vec], dupe_file)
wac <- mutate(wac, dupe_flag = dupe_vec)
rm(dupe_vec)
say("dupe_flag %s", format(sum(wac$dupe_flag), big.mark = ","))

wac <- mutate(wac, receipt_year = year(receipt_date))

wac <- wac %>%
  mutate(
    zip_norm = normal_zip(
      zip = contributor_zip %>%
        str_remove_all("-\\d{4}$"),
      na_rep = TRUE
    )
  )

wac <- wac %>%
  mutate(
    state_norm = normal_state(
      state = contributor_state,
      abbreviate = TRUE,
      na_rep = TRUE,
      valid = valid_state
    )
  )

norm_city <- wac %>%
  distinct(contributor_city, state_norm, zip_norm) %>%
  mutate(
    city_norm = normal_city(
      city = contributor_city,
      abbs = usps_city,
      states = c("WA", "DC", "WASHINGTON"),
      na = invalid_city,
      na_rep = TRUE
    )
  )

norm_city <- norm_city %>%
  left_join(
    y = zipcodes,
    by = c(
      "state_norm" = "state",
      "zip_norm" = "zip"
    )
  ) %>%
  rename(city_match = city) %>%
  mutate(
    match_abb = is_abbrev(city_norm, city_match),
    match_dist = str_dist(city_norm, city_match),
    city_swap = if_else(
      condition = !is.na(match_dist) & (match_abb | match_dist == 1),
      true = city_match,
      false = city_norm
    )
  ) %>%
  select(
    -city_match,
    -match_dist,
    -match_abb
  )

n0 <- nrow(wac)
wac <- left_join(
  x = wac,
  y = norm_city,
  by = c(
    "contributor_city",
    "state_norm",
    "zip_norm"
  )
)
stopifnot(nrow(wac) == n0)

good_refine <- wac %>%
  select(city_swap, state_norm, zip_norm) %>%
  mutate(
    city_refine = city_swap %>%
      key_collision_merge() %>%
      n_gram_merge(numgram = 1)
  ) %>%
  filter(city_refine != city_swap) %>%
  distinct() %>%
  inner_join(
    y = zipcodes,
    by = c(
      "city_refine" = "city",
      "state_norm" = "state",
      "zip_norm" = "zip"
    )
  )
say("refined city/state/zip combinations %d", nrow(good_refine))

wac <- wac %>%
  left_join(good_refine, by = c("city_swap", "state_norm", "zip_norm")) %>%
  mutate(city_refine = coalesce(city_refine, city_swap))
stopifnot(nrow(wac) == n0)

wac <- wac %>%
  select(
    -city_norm,
    -city_swap,
    city_clean = city_refine
  ) %>%
  rename_all(~str_replace(., "_norm", "_clean")) %>%
  rename_all(~str_remove(., "_raw")) %>%
  relocate(city_clean, state_clean, .before = zip_clean)

# ---- export ---------------------------------------------------------------------------------------------------
stopifnot(setequal(names(wac), c(old_cols, "fund_id", "row_checksum")))
wac <- select(wac, all_of(old_cols), fund_id, row_checksum)
chk("new part rows", nrow(wac), EXPECT$new_dated + EXPECT$new_undated)
say("new part receipt dates %s to %s; undated %s", min(wac$receipt_date, na.rm = TRUE),
    max(wac$receipt_date, na.rm = TRUE), format(sum(is.na(wac$receipt_date)), big.mark = ","))
write_csv(wac, new_out, na = "")
say("wrote %s", new_out)
