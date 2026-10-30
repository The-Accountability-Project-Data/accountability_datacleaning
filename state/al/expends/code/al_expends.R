# Copied 2026-10-30 from the datacleaning_agents repo (datasets/364-126-al-campaign-finance/al_expends.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Dataset 126, Alabama campaign expenditures -- rebuild 2026-10-28 (replaces DataFile 686, al_expends_clean.csv).
# Run from the repo root:  Rscript datasets/364-126-al-campaign-finance/al_expends.R
#
# Follows accountability_datacleaning/state/al/expends/docs/al_expends_diary.Rmd (Kiernan Nicholls 2020,
# Aarushi Sahejpal 2023): stack the yearly Expenditures files, strip the "Expenditure" prefix from the column names,
# amended Y -> TRUE, source_file = the CSV's name, parse amount/date/filed_date, committee =
# coalesce(committee_name, candidate_name), flag_na (date, last_name, amount, committee; unflagged for Non-Itemized),
# flag_dupes(-id) (unflagged for Non-Itemized), year = calendar year of the transaction date, campfin
# address/zip/state/city normalization -> *_clean. Output: the same 29 columns, same order, as the 2023 file.
#
# Changes from the diary (Oct 2026): the same as al_contribs.R -- new source (getTransactionData&id=<id>, ids from
# the JSON list, fetched by fetch_al.py), whole 2013-2026 history rebuilt (IDs renumbered), files now named
# <year>_ExpendituresExtract1.csv (source_file keeps the old "2013_ExpendituresExtract.csv" form), CommitteeId ->
# org_id, records split by raw line breaks re-joined (mostly multi-line Explanation values; every one re-joins to
# exactly 20 fields or the build stops), read with quote = "" (files are unquoted; replaces the stray-quote regex),
# UTF-8 (verified), dplyr >= 1.1 fixes, no plots/upload.
# Superseded records: Amended = "Y" marks a record filed on, or changed by, an amended report -- the current
# version, not a superseded one -- so 0 rows are dropped as superseded. The old system's "Offset due to
# deletion/update of filed item" rows (negative amounts, text in Explanation) are STILL in the 2013-2025 files
# (8,416 rows; none in 2026). They are kept as published, as in the 2023 file (7,365 there); see the notes file.
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(purrr); library(tidyr); library(lubridate)
  library(janitor); library(campfin); library(refinr); library(fs); library(here)
})
here::i_am("datasets/364-126-al-campaign-finance/al_expends.R")
comma <- function(x) format(x, big.mark = ",")

base <- here("work", "364-al-contribs")
raw_dir <- path(base, "raw", "2026-10-28", "csv")
out_dir <- dir_create(path(base, "out"))
old_cols <- names(read_csv(path(base, "old", "al_expends_clean.csv"), n_max = 0, show_col_types = FALSE))
raw_csv <- sort(dir_ls(raw_dir, regexp = "/\\d{4}_ExpendituresExtract1\\.csv$"))
stopifnot(length(raw_csv) == length(2013:2026))

# re-join records split by raw line breaks inside a field; returns the clean lines and a repair log
rejoin_lines <- function(f) {
  x <- str_split(read_file(f), "\n")[[1]]
  x <- str_remove(x, "\r$")
  if (x[length(x)] == "") x <- x[-length(x)]
  n_sep <- str_count(x[1], ",")
  k <- str_count(x, ",")
  out <- vector("list", length(x))
  i <- 1; j <- 0; bad_lines <- 0; repaired <- 0
  while (i <= length(x)) {
    if (k[i] == n_sep) {
      j <- j + 1; out[[j]] <- x[i]; i <- i + 1; next
    }
    buf <- x[i]; kk <- k[i]; start <- i
    while (kk < n_sep && i < length(x)) {
      i <- i + 1; buf <- paste(buf, x[i]); kk <- kk + k[i]
    }
    if (kk != n_sep) stop(sprintf("%s: can't re-join lines %d-%d (%d fields)", basename(f), start, i, kk + 1))
    bad_lines <- bad_lines + (i - start + 1); repaired <- repaired + 1
    j <- j + 1; out[[j]] <- buf; i <- i + 1
  }
  lines <- unlist(out[seq_len(j)])
  stopifnot(all(str_count(lines, ",") == n_sep))
  list(lines = lines, log = tibble(file = basename(f), fields = n_sep + 1, raw_lines = length(x) - 1,
                                   records = j - 1, bad_lines = bad_lines, repaired = repaired))
}

read_al <- function(f) {
  rj <- rejoin_lines(f)
  df <- read_delim(I(paste0(paste(rj$lines, collapse = "\n"), "\n")), delim = ",", quote = "", na = c("", " "),
                   escape_backslash = FALSE, escape_double = FALSE, trim_ws = FALSE,
                   col_types = cols(.default = col_character()), progress = FALSE)
  stopifnot(nrow(problems(df)) == 0, nrow(df) == rj$log$records)
  list(df = df, log = rj$log)
}

reads <- map(raw_csv, read_al)
repair_log <- map_dfr(reads, "log")
write_csv(repair_log, path(out_dir, "al_expends_line_repairs.csv"))
message("line-break repairs: ", sum(repair_log$repaired), " records from ", sum(repair_log$bad_lines), " lines")
ale <- map(reads, "df")
rm(reads)
# old-style source_file: "2013_ExpendituresExtract1.csv" -> "2013_ExpendituresExtract.csv"
names(ale) <- str_replace(basename(raw_csv), "Extract1\\.csv$", "Extract.csv")
ale <- bind_rows(ale, .id = "source_file") %>%
  rename_with(.fn = str_remove, .cols = everything(), "^Expenditure") %>%
  relocate(source_file, .after = last_col()) %>%
  clean_names("snake") %>%
  rename(org_id = committee_id)
amended_raw <- count(ale, source_file, amended)
ale <- ale %>%
  mutate(amended = amended == "Y") %>%
  type_convert(col_types = cols(amount = col_double(), date = col_date_mdy(), filed_date = col_date_mdy()))
message("rows: ", comma(nrow(ale)), " | amount NA: ", sum(is.na(ale$amount)), " | date NA: ", sum(is.na(ale$date)),
        " | amended TRUE: ", sum(ale$amended, na.rm = TRUE))

# missing and duplicates (diary)
ale <- mutate(ale, committee = coalesce(committee_name, candidate_name))
key_vars <- c("date", "last_name", "amount", "committee")
ale <- flag_na(ale, all_of(key_vars))
ale$na_flag[str_which(ale$type, "Non-Itemized")] <- FALSE
ale <- flag_dupes(ale, -id)
ale$dupe_flag[str_which(ale$type, "Non-Itemized")] <- FALSE
message("na_flag: ", sum(ale$na_flag), " | dupe_flag: ", sum(ale$dupe_flag))

ale <- mutate(ale, year = year(date))

# address
addr_norm <- ale %>%
  distinct(address1) %>%
  mutate(address_norm = normal_address(address = address1, abbs = usps_street, na_rep = TRUE))
ale <- left_join(ale, addr_norm, by = "address1")

# zip, state
ale <- ale %>%
  mutate(
    zip_norm = normal_zip(zip = zip, na_rep = TRUE),
    state_norm = normal_state(state = state, abbreviate = TRUE, na_rep = TRUE, valid = valid_state)
  )

# city: normal, swap, refine
norm_city <- ale %>%
  distinct(city, state_norm, zip_norm) %>%
  mutate(city_norm = normal_city(city = city, abbs = usps_city, states = c("AL", "DC", "ALABAMA"),
                                 na = invalid_city, na_rep = TRUE))
norm_city <- norm_city %>%
  rename(city_raw = city) %>%
  left_join(y = zipcodes, by = c("state_norm" = "state", "zip_norm" = "zip")) %>%
  rename(city_match = city) %>%
  mutate(
    match_abb = is_abbrev(city_norm, city_match),
    match_dist = str_dist(city_norm, city_match),
    city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)
  ) %>%
  select(-city_match, -match_dist, -match_abb)
stopifnot(!anyDuplicated(select(norm_city, city_raw, state_norm, zip_norm)))
ale <- left_join(ale, norm_city, by = c("city" = "city_raw", "state_norm", "zip_norm"))

# refinr clusters the whole column (so the most common spelling wins, as in the diary); keep only refined values
# that make a valid city/state/zip, then join back by the same keys the diary's natural join would match on
good_refine <- ale %>%
  select(city_swap, state_norm, zip_norm) %>%
  mutate(city_refine = city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)) %>%
  filter(city_refine != city_swap) %>%
  distinct() %>%
  inner_join(zipcodes, by = c("city_refine" = "city", "state_norm" = "state", "zip_norm" = "zip"))
stopifnot(!anyDuplicated(select(good_refine, city_swap, state_norm, zip_norm)))
message("city refines: ", nrow(good_refine), " distinct city/state/zip combinations")
ale <- ale %>%
  left_join(good_refine, by = c("city_swap", "state_norm", "zip_norm")) %>%
  mutate(city_refine = coalesce(city_refine, city_swap))

ale <- ale %>%
  select(-city_norm, -city_swap, city_clean = city_refine) %>%
  rename_all(~ str_replace(., "_norm", "_clean")) %>%
  rename_all(~ str_remove(., "_raw")) %>%
  relocate(state_clean, zip_clean, .after = city_clean)
stopifnot(identical(names(ale), old_cols))

yrs <- table(ale$year, useNA = "ifany")
print(yrs)
out <- path(out_dir, "al_expends_2013-2026.csv")
write_csv(ale, out, na = "")
message("wrote ", out, ": ", comma(nrow(ale)), " rows, ", format(file_size(out)))
write_csv(amended_raw, path(out_dir, "al_expends_amended_by_file.csv"))
