# Copied 2026-10-30 from the datacleaning_agents repo (datasets/364-126-al-campaign-finance/al_contribs.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Dataset 364, Alabama campaign contributions -- rebuild 2026-10-28 (replaces DataFile 1207, al_contribs_clean.csv).
# Run from the repo root:  Rscript datasets/364-126-al-campaign-finance/al_contribs.R
#
# Follows accountability_datacleaning/state/al/contribs/docs/al_contribs_diary.Rmd (Kiernan Nicholls 2020,
# Aarushi Sahejpal 2023): stack the yearly Cash Contributions, In-Kind Contributions and Other Receipts files,
# strip the type prefixes from the column names (SourceType -> ContributorType), source_file, amended Y -> TRUE,
# drop the loan endorser columns, parse amount/date/filed_date, recipient = coalesce(committee_name, candidate_name),
# flag_na (date, last_name, amount, recipient; unflagged for Non-Itemized types), flag_dupes(-id) (unflagged for
# Non-Itemized), year = calendar year of the transaction date, campfin address/zip/state/city normalization
# (normal_city, zipcodes swap, refinr refine) -> *_clean. Output: the same 29 columns, same order, as the 2023 file.
#
# Changes from the diary (Oct 2026), because Alabama moved to a new system (Tyler "AL Campaign Finance System"):
# - Source: page.request.do?page=getTransactionData&id=<id> per file, ids from the JSON download list (fetched by
#   fetch_al.py; see sources.json). Every year 2013-2026 is regenerated nightly, so the whole history is rebuilt;
#   all record IDs were renumbered, so the old file can't be appended to.
# - Files are now named <year>_<Type>Extract1.csv; source_file keeps the old form ("CashContributionsExtract.csv_2013").
# - First column renamed OrgID -> CommitteeId; renamed back to org_id here.
# - Files are unquoted and the state strips commas from values ("LIGHTFOOT  FRANKLIN & WHITE  LLC"), but a few
#   address values contain raw line breaks that split a record across lines. Lines are re-joined (with a space) until
#   the record has exactly the header's field count; any record that can't be re-joined stops the build.
# - Read with quote = "" (no field is quoted, so a value like WILLIAM C. "BILL" THOMPSON is read as published). This
#   replaces the diary's stray-quote regex, which only existed to stop readr treating those quotes as field quoting;
#   the 2023 file also kept them as double quotes.
# - Encoding: every 2026-10-28 source file is valid UTF-8 (tools/verify_encoding.py --guess), read as UTF-8.
# - The new Cash export repeats every in-kind contribution (same ID/committee/date/amount as the In-Kind file);
#   those 44,156 cash-file copies are dropped (DROP_CASH_FILE_INKIND_COPIES) so in-kind gifts aren't counted twice.
# - dplyr >= 1.1: across(amended, `==`, "Y") -> amended == "Y"; the refine join is by explicit keys.
# - Plots, kable tables and the S3 upload are skipped.
# Superseded records: the new system exports each report's current state. Amended = "Y" marks a record that was
# filed on, or changed by, an amended report -- it is the current version, not a superseded one (no earlier-filed
# twin exists for it; see datasets/364-126-al-campaign-finance.md). So no rows are dropped as superseded: 0 dropped.
# The old system's "Offset due to deletion/update of filed item" contribution rows no longer appear.
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(purrr); library(tidyr); library(lubridate)
  library(janitor); library(campfin); library(refinr); library(fs); library(here)
})
here::i_am("datasets/364-126-al-campaign-finance/al_contribs.R")
comma <- function(x) format(x, big.mark = ",")

base <- here("work", "364-al-contribs")
raw_dir <- path(base, "raw", "2026-10-28", "csv")
out_dir <- dir_create(path(base, "out"))
old_cols <- names(read_csv(path(base, "old", "al_contribs_clean.csv"), n_max = 0, show_col_types = FALSE))
types <- c("CashContributions", "InKindContributions", "OtherReceipts")
raw_csv <- unlist(map(types, ~ sort(dir_ls(raw_dir, regexp = glue::glue("/\\d{{4}}_{.x}Extract1\\.csv$")))))
stopifnot(length(raw_csv) == 3 * length(2013:2026))

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
write_csv(repair_log, path(out_dir, "al_contribs_line_repairs.csv"))
message("line-break repairs: ", sum(repair_log$repaired), " records from ", sum(repair_log$bad_lines), " lines")
alc <- map(reads, "df")
rm(reads)
# old-style source_file: "2013_CashContributionsExtract1.csv" -> "CashContributionsExtract.csv_2013"
names(alc) <- basename(raw_csv) %>%
  str_replace("Extract1\\.csv$", "Extract.csv") %>%
  str_replace("(^\\d{4})_(.*)", "\\2_\\1")

alc <- map_df(
  .x = alc,
  .f = rename_with,
  .id = "source_file",
  .fn = function(x) {
    str_remove(x, "^Receipt") %>%
      str_remove("^Contribution") %>%
      str_remove("InKindContribution") %>%
      str_replace("^SourceType$", "ContributorType")
  }
)

alc <- alc %>%
  relocate(source_file, .after = last_col()) %>%
  clean_names("snake") %>%
  rename(org_id = committee_id) %>%
  select(-starts_with("endorse"))
amended_raw <- count(alc, source_file, amended)
alc <- alc %>%
  mutate(amended = amended == "Y") %>%
  type_convert(col_types = cols(amount = col_double(), date = col_date_mdy(), filed_date = col_date_mdy()))

# New in 2026: the Cash Contributions export ALSO contains every in-kind contribution ("In-Kind (Itemized)" /
# "In-Kind (Non-Itemized)"), with the same ID, committee, date and amount as its row in the In-Kind file (which also
# has nature_of). The old system's cash files had none. Keep one copy (the In-Kind file's) so in-kind gifts are not
# counted twice; stop if any cash-file in-kind row has no identical In-Kind-file twin. Set to FALSE to keep both.
DROP_CASH_FILE_INKIND_COPIES <- TRUE
cash_ik <- str_starts(alc$source_file, "Cash") & str_starts(alc$type, "In-Kind")
ik_keys <- alc %>% filter(str_starts(source_file, "InKind")) %>% distinct(id, org_id, date, amount)
twins <- alc[cash_ik, ] %>% semi_join(ik_keys, by = c("id", "org_id", "date", "amount"))
stopifnot(nrow(twins) == sum(cash_ik))
message("cash-file copies of in-kind rows: ", comma(sum(cash_ik)), " (all have an identical In-Kind-file row); ",
        if (DROP_CASH_FILE_INKIND_COPIES) "dropped" else "kept")
if (DROP_CASH_FILE_INKIND_COPIES) alc <- alc[!cash_ik, ]
message("rows: ", comma(nrow(alc)), " | amount NA: ", sum(is.na(alc$amount)), " | date NA: ", sum(is.na(alc$date)),
        " | amended TRUE: ", sum(alc$amended, na.rm = TRUE))

# missing and duplicates (diary)
alc <- mutate(alc, recipient = coalesce(committee_name, candidate_name))
key_vars <- c("date", "last_name", "amount", "recipient")
alc <- flag_na(alc, all_of(key_vars))
alc$na_flag[str_which(alc$type, "Non-Itemized")] <- FALSE
alc <- flag_dupes(alc, -id)
alc$dupe_flag[str_which(alc$type, "Non-Itemized")] <- FALSE
message("na_flag: ", sum(alc$na_flag), " | dupe_flag: ", sum(alc$dupe_flag))

alc <- mutate(alc, year = year(date))

# address
addr_norm <- alc %>%
  distinct(address1) %>%
  mutate(address_norm = normal_address(address = address1, abbs = usps_street, na_rep = TRUE))
alc <- left_join(alc, addr_norm, by = "address1")

# zip, state
alc <- alc %>%
  mutate(
    zip_norm = normal_zip(zip = zip, na_rep = TRUE),
    state_norm = normal_state(state = state, abbreviate = TRUE, na_rep = TRUE, valid = valid_state)
  )

# city: normal, swap, refine
norm_city <- alc %>%
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
alc <- left_join(alc, norm_city, by = c("city" = "city_raw", "state_norm", "zip_norm"))

# refinr clusters the whole column (so the most common spelling wins, as in the diary); keep only refined values
# that make a valid city/state/zip, then join back by the same keys the diary's natural join would match on
good_refine <- alc %>%
  select(city_swap, state_norm, zip_norm) %>%
  mutate(city_refine = city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)) %>%
  filter(city_refine != city_swap) %>%
  distinct() %>%
  inner_join(zipcodes, by = c("city_refine" = "city", "state_norm" = "state", "zip_norm" = "zip"))
stopifnot(!anyDuplicated(select(good_refine, city_swap, state_norm, zip_norm)))
message("city refines: ", nrow(good_refine), " distinct city/state/zip combinations")
alc <- alc %>%
  left_join(good_refine, by = c("city_swap", "state_norm", "zip_norm")) %>%
  mutate(city_refine = coalesce(city_refine, city_swap))

alc <- alc %>%
  select(-city_norm, -city_swap, city_clean = city_refine) %>%
  rename_all(~ str_replace(., "_norm", "_clean")) %>%
  rename_all(~ str_remove(., "_raw")) %>%
  relocate(state_clean, zip_clean, .after = city_clean)
stopifnot(identical(names(alc), old_cols))

yrs <- table(alc$year, useNA = "ifany")
print(yrs)
out <- path(out_dir, "al_contribs_2013-2026.csv")
write_csv(alc, out, na = "")
message("wrote ", out, ": ", comma(nrow(alc)), " rows, ", format(file_size(out)))
write_csv(amended_raw, path(out_dir, "al_contribs_amended_by_file.csv"))
