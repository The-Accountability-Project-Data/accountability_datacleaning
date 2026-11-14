# Washington campaign expenditures: update 2026-11-05. Two files with one header layout:
#   wa_expends_2004-2021.csv  the old wa_expends_clean.csv (Dec 2022 build) cut at expenditure_date
#                             2021-12-31, plus its undated rows; values unchanged, same 37 columns.
#   wa_expends_2022-2026.csv  data.wa.gov tijg-9zyp (WA PDC "Expenditures by Candidates and Political Committees"),
#                             retrieved 2026-11-05, rows with expenditure_date >= 2022-01-01, plus undated rows whose
#                             id is not in the old part; built with the diary's steps; the old 37 columns, then
#                             fund_id, payee, creditor, row_checksum.
#   Rscript state/wa/expends/code/wa_expends_2026.R   # from the repo root
# Inputs under `base` = state/wa/expends/data (set below): old/wa_expends_clean.csv and raw/rows.csv;
# output in data/clean/.
#
# Follows state/wa/expends/docs/wa_expends_diary.Rmd (Kiernan Nicholls, Yanqi Xu;
# run 2022-12-26): parse amount and election_year as numbers and expenditure_date as a date; flag_na(expenditure_date,
# recipient_name); flag_dupes(-id); expenditure_year = year(expenditure_date); date_flag = expenditure_year < 2007;
# campfin normal_address/normal_zip/normal_state(valid = NULL)/normal_city(states WA, DC), ZIP swap, refinr
# key-collision + n-gram refine -> address_clean, zip_clean, state_clean, city_clean.
#
# Changes from the diary (Nov 2026): reads the CSV export (rows.csv) instead of the SODA JSON; expenditure_date is
# MM/DD/YYYY (mdy); the CSV's recipient_location (POINT (lon lat), as published) goes in
# recipient_location.coordinates; the CSV's fund_id, payee, creditor, row_checksum are kept at the end; flag_dupes
# runs on the new part only and over every source column but id; address and city normalization run on distinct
# values; refine joins on city_swap/state/zip; dplyr >= 1.1 fixes; no plots.
# Superseded records: the source leaves out the original version of amended reports; nothing to drop.
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(lubridate)
  library(campfin); library(refinr); library(fs); library(here)
})
comma <- function(x) format(x, big.mark = ",")

base <- here("state", "wa", "expends", "data")  # holds old/, raw/ and clean/
old_csv <- path(base, "old", "wa_expends_clean.csv")
src_csv <- path(base, "raw", "rows.csv")
out_dir <- dir_create(path(base, "clean"))

# ---- old part: rows of the old file dated through 2021-12-31, plus undated rows, unchanged ----
old <- read_csv(old_csv, col_types = cols(.default = col_character()), na = character(), trim_ws = FALSE,
                progress = FALSE)
stopifnot(nrow(problems(old)) == 0, nrow(old) == 1028427, ncol(old) == 37)
old_cols <- names(old)
stopifnot(all(old$expenditure_date == "" | str_detect(old$expenditure_date, "^\\d{4}-\\d{2}-\\d{2}$")))
old_part <- filter(old, expenditure_date == "" | expenditure_date <= "2021-12-31")
message("old: ", comma(nrow(old)), " | old part: ", comma(nrow(old_part)),
        " (undated ", sum(old_part$expenditure_date == ""), ") | cut: ", comma(nrow(old) - nrow(old_part)))
write_csv(old_part, path(out_dir, "wa_expends_2004-2021.csv"), na = "")
old_part_ids <- old_part$id
old_late_ids <- old$id[!old$id %in% old_part_ids]
rm(old)

# ---- source ----
wa <- read_csv(src_csv, col_types = cols(.default = col_character()), na = "", trim_ws = FALSE, progress = FALSE)
stopifnot(nrow(problems(wa)) == 0, !anyDuplicated(wa$id))
src_cols <- names(wa)
message("source: ", comma(nrow(wa)), " rows, ", ncol(wa), " columns")

wa <- wa %>%
  mutate(
    amount_raw = amount,
    amount = parse_number(amount),
    election_year = parse_number(election_year),
    expenditure_date = mdy(expenditure_date)
  )
stopifnot(sum(is.na(wa$amount)) == sum(is.na(wa$amount_raw)))
wa <- select(wa, -amount_raw)

# rows left out: dated through 2021 and not in the old file's kept part
left_out <- wa %>% filter(!is.na(expenditure_date), expenditure_date <= as_date("2021-12-31"), !id %in% old_part_ids)
message("left out (dated <= 2021, not in the old part): ", comma(nrow(left_out)))
print(count(left_out, year = year(expenditure_date)), n = Inf)
write_csv(count(left_out, expenditure_year = year(expenditure_date)), path(out_dir, "left_out_by_year.csv"))
rm(left_out)

# old-part rows the source no longer has, by election year
gone <- old_part %>% filter(!id %in% wa$id) %>% count(election_year)
message("old-part rows not in the source: ", comma(sum(gone$n)))
write_csv(gone, path(out_dir, "old_part_not_in_source_by_election_year.csv"))
rm(old_part)

wa <- wa %>% filter(expenditure_date >= as_date("2022-01-01") | (is.na(expenditure_date) & !id %in% old_part_ids))
stopifnot(!any(wa$id %in% old_part_ids))
message("new part: ", comma(nrow(wa)), " rows (undated ", sum(is.na(wa$expenditure_date)), "); ids also in the ",
        "old file's cut rows: ", sum(wa$id %in% old_late_ids))

# ---- diary steps ----
wa <- flag_na(wa, expenditure_date, recipient_name)
wa <- flag_dupes(wa, -id)
message("na_flag: ", sum(wa$na_flag), " | dupe_flag: ", sum(wa$dupe_flag))

wa <- wa %>% mutate(
  expenditure_year = year(expenditure_date),
  date_flag = expenditure_year < 2007
)

addr_norm <- wa %>%
  distinct(recipient_address) %>%
  mutate(address_norm = normal_address(address = recipient_address, abbs = usps_street, na_rep = TRUE))
wa <- left_join(wa, addr_norm, by = "recipient_address")

wa <- wa %>% mutate(
  zip_norm = normal_zip(zip = recipient_zip, na_rep = TRUE),
  state_norm = normal_state(state = recipient_state, abbreviate = TRUE, na_rep = TRUE, valid = NULL)
)

norm_city <- wa %>%
  distinct(recipient_city, state_norm, zip_norm) %>%
  mutate(city_norm = normal_city(city = recipient_city, abbs = usps_city, states = c("WA", "DC"),
                                 na = invalid_city, na_rep = TRUE)) %>%
  left_join(y = zipcodes, by = c("state_norm" = "state", "zip_norm" = "zip")) %>%
  rename(city_match = city) %>%
  mutate(
    match_abb = is_abbrev(city_norm, city_match),
    match_dist = str_dist(city_norm, city_match),
    city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)
  ) %>%
  select(-city_match, -match_dist, -match_abb)
stopifnot(!anyDuplicated(select(norm_city, recipient_city, state_norm, zip_norm)))
wa <- left_join(wa, norm_city, by = c("recipient_city", "state_norm", "zip_norm"))

good_refine <- wa %>%
  select(city_swap, state_norm, zip_norm) %>%
  mutate(city_refine = city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)) %>%
  filter(city_refine != city_swap) %>%
  distinct() %>%
  inner_join(zipcodes, by = c("city_refine" = "city", "state_norm" = "state", "zip_norm" = "zip"))
stopifnot(!anyDuplicated(select(good_refine, city_swap, state_norm, zip_norm)))
message("city refines: ", nrow(good_refine), " distinct city/state/zip combinations")
wa <- wa %>%
  left_join(good_refine, by = c("city_swap", "state_norm", "zip_norm")) %>%
  mutate(city_refine = coalesce(city_refine, city_swap))

# ---- write ----
wa <- wa %>%
  rename(
    recipient_location.coordinates = recipient_location,
    address_clean = address_norm,
    zip_clean = zip_norm,
    state_clean = state_norm,
    city_clean = city_refine
  ) %>%
  select(all_of(old_cols), fund_id, payee, creditor, row_checksum)
stopifnot(identical(names(wa)[1:37], old_cols), ncol(wa) == 41)
print(table(wa$expenditure_year, useNA = "ifany"))
out <- path(out_dir, "wa_expends_2022-2026.csv")
write_csv(wa, out, na = "")
message("wrote ", out, ": ", comma(nrow(wa)), " rows, ", format(file_size(out)))
