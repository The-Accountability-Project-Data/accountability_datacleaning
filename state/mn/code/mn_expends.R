# Copied 2026-10-30 from the datacleaning_agents repo (datasets/369-417-mn-campaign-finance/mn_expends.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Dataset 417, Minnesota campaign expenditures -- rebuild 2015-2026, 2026-10-28 (NOT uploaded; would replace DataFile
# 740, whose rows came from csv/mn_expends_clean_new.csv). Run from the datacleaning_agents repo root:
#   Rscript datasets/369-417-mn-campaign-finance/mn_expends.R
#
# Follows accountability_datacleaning state/mn/expends/docs/mn_expends_diary.Rmd ("Update: October 2026"):
# - Source: CFB "Expenditures, including contributions made, by all entities - 2015 to present"
#   (https://cfb.mn.gov/reports-and-data/self-help/data-downloads/campaign-finance/?download=-1890073264), retrieved
#   2026-10-28 (retrievals.jsonl), UTF-8, full history regenerated from the board's database at each download.
# - Changes from the 2022-12 run:
#   * the download NO LONGER HAS `Vendor address 1` / `Vendor address 2`. User decision 2026-10-28: do not backfill
#     from the old file; keep `vendor_address_1/2` in the header, blank. So `address_clean` (normal_address of the two)
#     is blank on every row. Vendor city/state/zip are still published and normalised as before.
#   * Date is ISO (was m/d/Y); reader read_cfb() in mn_common.R (RFC quoting -- the diary's escape_double = FALSE
#     turned "" into two quotes, e.g. """"Healthcare Headlines"""" -- plus the export's backslash-quotes, kept).
# - Unchanged: clean_names, amount rounded to cents, year = calendar year of the date (the diary already recomputed
#   it), na_flag (date, committee_name, amount, vendor_name), dupe_flag (all columns), normal_zip / normal_state /
#   normal_city + swap + refine, `_clean` columns. in_kind stays "Yes"/"No" as published.
# - Output: same 26 columns, same order as the old file (csv/mn_expends_clean_new.csv).
# Superseded records: no amendment flag; the board's database keeps only current versions, 0 rows dropped.
here::i_am("datasets/369-417-mn-campaign-finance/mn_expends.R")
source(here::here("datasets", "369-417-mn-campaign-finance", "mn_common.R"))
suppressPackageStartupMessages({ library(refinr); library(tidyr) })
raw_csv <- path(raw_dir, "download_-1890073264_expends_all.csv")

mne <- read_cfb(raw_csv, expected_records = 402530, col_types = cols(
  .default = col_character(),
  `Amount` = col_double(),
  `Unpaid amount` = col_double(),
  `Date` = col_date("%Y-%m-%d"),
  `Year` = col_integer()
))
mne <- clean_names(mne, case = "snake")
stopifnot(!anyNA(mne$date))

# address columns are no longer published: keep them, blank, in the old position
mne <- mne %>%
  mutate(vendor_address_1 = NA_character_, vendor_address_2 = NA_character_, .after = vendor_name)

key_vars <- c("date", "committee_name", "amount", "vendor_name")
mne <- flag_na(mne, all_of(key_vars))
mne <- flag_dupes(mne, everything())
cat("na_flag:", sum(mne$na_flag), " dupe_flag:", sum(mne$dupe_flag), "\n")

mne$amount <- round(mne$amount, digits = 2)

# year = calendar year of the expenditure date (the diary's rule; the source Year is the report year)
chg <- mne %>% filter(year != year(date))
cat("rows where the source Year != year(date) (the old diary also used year(date)):", nrow(chg), "\n")
print(count(chg, source_year = year, year = year(date)), n = 50)
mne <- mutate(mne, year = as.integer(year(date)))

# ---- address (blank: no street address published) ----
addr_norm <- mne %>%
  distinct(vendor_address_1, vendor_address_2) %>%
  mutate(across(.cols = c(vendor_address_1, vendor_address_2), .fns = list(xnorm = ~ normal_address(.x, abbs = usps_street, na_rep = TRUE)))) %>%
  unite(col = address_norm, ends_with("_xnorm"), sep = " ", remove = TRUE, na.rm = TRUE) %>%
  mutate(across(address_norm, ~ na_if(.x, "")))
mne <- left_join(mne, addr_norm, by = c("vendor_address_1", "vendor_address_2"))
stopifnot(all(is.na(mne$address_norm)))

# ---- ZIP / state ----
mne <- mne %>%
  mutate(zip_norm = normal_zip(zip = vendor_zip, na_rep = TRUE),
         state_norm = normal_state(state = vendor_state, abbreviate = TRUE, na_rep = TRUE))
print(progress_table(mne$vendor_zip, mne$zip_norm, compare = valid_zip))
print(progress_table(mne$vendor_state, mne$state_norm, compare = valid_state))

# ---- city ----
norm_city <- mne %>%
  distinct(vendor_city, state_norm, zip_norm) %>%
  mutate(city_norm = normal_city(city = vendor_city, abbs = usps_city, states = c("MN", "DC", "MINNESOTA"),
                                 na = invalid_city, na_rep = TRUE))
norm_city <- norm_city %>%
  left_join(y = zipcodes, by = c("state_norm" = "state", "zip_norm" = "zip")) %>%
  rename(city_match = city) %>%
  mutate(match_abb = is_abbrev(city_norm, city_match),
         match_dist = str_dist(city_norm, city_match),
         city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)) %>%
  select(-city_match, -match_dist, -match_abb)
n0 <- nrow(mne)
mne <- left_join(mne, norm_city, by = c("vendor_city", "state_norm", "zip_norm"))
stopifnot(nrow(mne) == n0)

good_refine <- mne %>%
  mutate(city_refine = city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)) %>%
  filter(city_refine != city_swap) %>%
  inner_join(y = zipcodes, by = c("city_refine" = "city", "state_norm" = "state", "zip_norm" = "zip"))
cat("refined city rows:", nrow(good_refine), "\n")
# The diary joined good_refine back on ALL columns, which duplicates every fully-duplicated row that was refined
# (it is how the 2022-12 run turned 260,873 records into 260,875). Join on the city keys of distinct refinements.
good_refine <- distinct(good_refine, vendor_city, state_norm, zip_norm, city_swap, city_refine)
stopifnot(!anyDuplicated(good_refine[c("vendor_city", "state_norm", "zip_norm", "city_swap")]))
mne <- mne %>%
  left_join(good_refine, by = c("vendor_city", "state_norm", "zip_norm", "city_swap")) %>%
  mutate(city_refine = coalesce(city_refine, city_swap))
stopifnot(nrow(mne) == n0)
many_city <- c(valid_city, extra_city)
print(progress_table(str_to_upper(mne$vendor_city), mne$city_norm, mne$city_swap, mne$city_refine,
                     compare = many_city))

mne <- mne %>%
  select(-city_norm, -city_swap, city_clean = city_refine) %>%
  rename_all(~ str_replace(., "_norm", "_clean")) %>%
  rename_all(~ str_remove(., "_raw")) %>%
  relocate(address_clean, city_clean, state_clean, .before = zip_clean)

old_hdr <- names(read_csv(path(base, "old", "mn_expends_clean_new.csv"), n_max = 0, col_types = cols(.default = "c")))
cat("header identical to old:", identical(names(mne), old_hdr), "\n")
if (!identical(names(mne), old_hdr)) { print(names(mne)); print(old_hdr) }
stopifnot(identical(names(mne), old_hdr))
cat("dates", format(min(mne$date)), "..", format(max(mne$date)), "\n")
print(count(mne, year), n = 50)

clean_csv <- path(out_dir, "mn_expends_2015-2026.csv")
write_csv(mne, clean_csv, na = "")
cat("wrote", clean_csv, file_size(clean_csv), "\n")
