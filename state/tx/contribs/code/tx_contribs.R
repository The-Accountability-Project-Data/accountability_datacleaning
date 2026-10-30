# Copied 2026-10-30 from the datacleaning_agents repo (ec2/tx/tx_contribs.R): the script that built the October 2026 file.
# It ran on the project's EC2 build box and reads/writes paths there (e.g. ~/tx/raw, ~/il/); point them at your
# own raw and output folders before running it from here.
#
# Texas campaign contributions (dataset 473): full rebuild from the TEC bulk zip, all years, split by year.
# Adapted from accountability_datacleaning state/tx/contribs/docs/tx_clean.R + tx_contribs_diary.Rmd (Kiernan
# Nicholls, 2021-23). Differences from 2023, at the user's request (2026-10-07/12):
#   * keeps ALL 37 source fields (2023 trimmed to 11 "for memory space" and never rejoined them). The 17 columns of
#     the current file (tx_contribs_clean.csv, DataFile 2001) come first, in the same order and with the same names,
#     so dataset 473's index mapping still applies; the 26 restored source fields follow.
#   * writes one file per contribution year (tx_contribs_<year>.csv); rows with no contribution date go to
#     tx_contribs_undated.csv.
# Same as 2023: snake_case names, Y/N flags -> TRUE/FALSE, na_flag (date, contributor name, amount, filer),
# dupe_flag (same report-received date, filer, contributor name/place, date and amount, ignoring the contribution id), contribution_yr, campfin ZIP/state normalization and city norm/swap/refine.
#
#   Rscript tx_contribs.R dupes   # pass 1: duplicate contribution ids across all files -> work/dupes.txt
#   Rscript tx_contribs.R clean   # pass 2: clean each file, append rows to clean/tx_contribs_<year>.csv
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(lubridate); library(janitor)
  library(campfin); library(refinr); library(fs); library(cli); library(scales); library(openssl)
})
mode <- commandArgs(trailingOnly = TRUE)[1]
raw_dir   <- path_expand("~/tx/raw")
work_dir  <- dir_create(path_expand("~/tx/work"))
clean_dir <- dir_create(path_expand("~/tx/clean"))
raw_csv <- sort(dir_ls(raw_dir, regexp = "contribs_\\d+\\.csv$"))
if (nzchar(Sys.getenv("TX_LIMIT"))) raw_csv <- head(raw_csv, as.integer(Sys.getenv("TX_LIMIT")))   # testing
cli_alert_info("{length(raw_csv)} contribution files")

read_tx <- function(f) {
  x <- read_delim(f, delim = ",", escape_backslash = FALSE, escape_double = FALSE, progress = FALSE,
    col_types = cols(.default = col_character(), reportInfoIdent = col_integer(), receivedDt = col_date("%Y%m%d"),
                     contributionInfoId = col_integer(), contributionDt = col_date("%Y%m%d"),
                     contributionAmount = col_double()))
  clean_names(x, case = "snake")
}

# the 2023 duplicate definition: identical on these fields within the same report-received date (the diary split
# the data by received_dt before calling duplicated()), ignoring contribution_info_id. So a contribution repeated in
# a later, amended report is NOT a duplicate.
dupe_fields <- c("received_dt", "filer_ident", "filer_name", "contribution_dt", "contribution_amount",
                 "contributor_name_organization", "contributor_name_last", "contributor_name_first",
                 "contributor_street_city", "contributor_street_state_cd", "contributor_street_postal_code")

if (identical(mode, "dupes")) {
  hash_file <- path(work_dir, "hashes.tsv")
  if (file_exists(hash_file)) file_delete(hash_file)
  for (f in raw_csv) {
    x <- read_tx(f)
    key <- do.call(paste, c(lapply(x[dupe_fields], function(v) coalesce(as.character(v), "")), sep = "\x1f"))
    write_tsv(tibble(h = substr(as.character(md5(key)), 1, 20), id = x$contribution_info_id), hash_file,
              append = file_exists(hash_file), col_names = FALSE)
    cli_alert_success("{basename(f)}: {comma(nrow(x))} rows hashed")
    rm(x, key); invisible(gc())
  }
  # ids whose hash occurs more than once (disk-based sort; low memory)
  cmd <- sprintf("LC_ALL=C sort -S 2G -T %s -t '\t' -k1,1 %s | awk -F'\t' '$1==p{if(!o)print pid; print $2; o=1; next}{p=$1; pid=$2; o=0}' > %s",
                 work_dir, hash_file, path(work_dir, "dupes.txt"))
  system(cmd)
  cli_alert_success("{comma(length(read_lines(path(work_dir, 'dupes.txt'))))} duplicate contribution ids")
  quit(save = "no")
}

stopifnot(identical(mode, "clean"))
dupes <- tibble(contribution_info_id = as.integer(read_lines(path(work_dir, "dupes.txt"))), dupe_flag = TRUE)
old_17 <- c("filer_ident", "filer_name", "contribution_info_id", "contribution_dt", "contribution_amount",
            "contributor_name_organization", "contributor_name_last", "contributor_name_first",
            "contributor_street_city", "contributor_street_state_cd", "contributor_street_postal_code",
            "na_flag", "dupe_flag", "contribution_yr", "city_clean", "state_clean", "zip_clean")
dir_walk(clean_dir, file_delete)
yes_no <- function(x) x == "Y"
summary_rows <- list()
for (f in raw_csv) {
  txc <- read_tx(f)
  n <- nrow(txc)
  txc <- mutate(txc, across(ends_with("_flag"), yes_no))
  # missing values
  txc <- txc %>%
    mutate(contributor_name_any = coalesce(contributor_name_organization, contributor_name_last,
                                           contributor_name_first)) %>%
    flag_na(contribution_dt, contributor_name_any, contribution_amount, filer_name) %>%
    select(-contributor_name_any)
  # duplicates
  txc <- left_join(txc, dupes, by = "contribution_info_id") %>% mutate(dupe_flag = !is.na(dupe_flag))
  # year
  txc <- mutate(txc, contribution_yr = year(contribution_dt))
  # ZIP, state
  txc <- mutate(txc, zip_norm = normal_zip(zip = contributor_street_postal_code, na_rep = TRUE))
  st_norm <- txc %>% distinct(contributor_street_state_cd) %>%
    mutate(state_norm = normal_state(state = contributor_street_state_cd, abbreviate = TRUE, na_rep = TRUE,
                                     valid = NULL))
  txc <- left_join(txc, st_norm, by = "contributor_street_state_cd")
  # city: normalize, swap with the ZIP's expected city, refine (only into valid city/state/ZIP combinations)
  norm_city <- txc %>% distinct(contributor_street_city, state_norm, zip_norm) %>%
    mutate(city_norm = normal_city(city = contributor_street_city, abbs = usps_city,
                                   states = c("TX", "DC", "TEXAS"), na = invalid_city, na_rep = TRUE)) %>%
    left_join(zipcodes, by = c("state_norm" = "state", "zip_norm" = "zip")) %>%
    rename(city_match = city) %>%
    mutate(match_abb = is_abbrev(city_norm, city_match), match_dist = str_dist(city_norm, city_match),
           city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)) %>%
    select(-city_match, -match_dist, -match_abb) %>% distinct()
  txc <- left_join(txc, norm_city, by = c("contributor_street_city", "state_norm", "zip_norm"))
  # refine over every row, as in 2023: the merges keep each cluster's most frequent spelling
  good_refine <- txc %>% select(state_norm, zip_norm, city_swap) %>%
    mutate(city_refine = city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)) %>%
    filter(city_refine != city_swap) %>%
    inner_join(zipcodes, by = c("city_refine" = "city", "state_norm" = "state", "zip_norm" = "zip")) %>%
    distinct(state_norm, zip_norm, city_swap, .keep_all = TRUE)
  txc <- txc %>% left_join(good_refine, by = c("state_norm", "zip_norm", "city_swap")) %>%
    mutate(city_refine = coalesce(city_refine, city_swap))
  # conclude: same names as 2023, the 17 old columns first, then the restored source fields
  txc <- txc %>% select(-city_norm, -city_swap) %>%
    rename(city_clean = city_refine, state_clean = state_norm, zip_clean = zip_norm)
  txc <- select(txc, all_of(old_17), everything())
  stopifnot(nrow(txc) == n)
  # append by year
  for (y in split(txc, coalesce(as.character(txc$contribution_yr), "undated"))) {
    yr <- coalesce(as.character(y$contribution_yr[1]), "undated")
    out <- path(clean_dir, sprintf("tx_contribs_%s.csv", yr))
    write_csv(y, out, na = "", append = file_exists(out), col_names = !file_exists(out))
  }
  summary_rows[[basename(f)]] <- tibble(file = basename(f), rows = n, na = sum(txc$na_flag), dupes = sum(txc$dupe_flag))
  cli_alert_success("{basename(f)}: {comma(n)} rows, {sum(txc$na_flag)} na, {sum(txc$dupe_flag)} dupes")
  rm(txc, norm_city, good_refine, st_norm); invisible(gc())
}
write_csv(bind_rows(summary_rows), path(work_dir, "clean_summary.csv"))
cli_alert_success("done: {comma(sum(bind_rows(summary_rows)$rows))} rows in {length(dir_ls(clean_dir))} year files")
