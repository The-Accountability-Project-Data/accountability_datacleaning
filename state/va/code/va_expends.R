# Virginia campaign expenditures -- rebuild 2012-2026, November 2026 (replaces va_expends_clean.csv).
#   Rscript state/va/code/va_expends.R from the repo root. Put the monthly folders (data/raw/<YYYY_MM>/Report.csv,
#   ScheduleD.csv) in state/va/expends/data/raw/ and the previous published file in data/old/; run
#   python3 state/va/code/reparse.py state/va/expends first. Output: state/va/expends/data/clean/.
#
# Follows state/va/expends/docs/va_expends_diary.Rmd ("Update: November 2026"):
# - Source: https://apps.elections.virginia.gov/SBE_CSV/CF/, Schedule D of every monthly folder 2012_03 to 2026_11,
#   retrieved 2026-11-14/15, joined to Report on ReportId. A full re-download: the state regenerates every month's
#   files daily.
# - Changes from the 2023 run: all of 2012 on is built from the download (the 2023 file kept only a few thousand
#   rows a year before 2019); transactions on superseded (amended) reports are dropped (see va_common.R); quotes
#   inside fields are kept as published; the files are read as windows-1252.
#   The city swap keeps the normalized city when the ZIP code has no match (the diary's condition blanked those
#   cities: 5-10% of rows in the earlier contributions files).
# - Unchanged: column names, including com_city_raw for the payee's city as filed and com_city for the committee's;
#   committee fields from Report (candidate, committee name, office, address); dupe_count/dupe_flag on every column
#   but schedule_d_id; transaction_year = year(transaction_date); addresses with normal_address(); ZIPs and states
#   normalized; payee cities swapped with the ZIP code's city when within two edits, then refined where the result
#   is a valid city/state/ZIP; committee cities swapped when an abbreviation or one edit away.
# - Output: the columns of va_expends_clean.csv, in its order.
# Superseded records (2026-11-15 run): 38,738 superseded report versions; dropped 515,596 Schedule D rows.
# Output 1,343,388 rows.
library(here)
here::i_am("state/va/code/va_expends.R")
va_dataset <- "expends"
source(here("state", "va", "code", "va_common.R"))
file_delete(path(out_dir, "superseded_dropped.tsv")[file_exists(path(out_dir, "superseded_dropped.tsv"))])
write_lines("schedule\trows\tsuperseded_dropped", path(out_dir, "superseded_dropped.tsv"))

va <- drop_superseded(read_parsed("va_scheduled.csv"), "ScheduleD") %>%
  clean_names() %>%
  select(-source_file) %>%
  mutate(
    is_individual = is_individual == "True",
    transaction_date = parse_txn_date(transaction_date),
    amount = as.numeric(amount)
  )
n0 <- nrow(va)

va_meta <- rpt_raw %>%
  filter(ReportId %in% current_rpt) %>%
  clean_names() %>%
  select(report_id, candidate_name, committee_name, office_sought, city, address_line1, address_line2, address_line3,
         state_code, zip_code) %>%
  rename_with(~ paste0("com_", .), city:zip_code)
va <- left_join(va, va_meta, by = "report_id", relationship = "many-to-one")
stopifnot(nrow(va) == n0)
va <- mutate(va, across(where(is.character), ~ na_if(.x, "")))

# dupe_count / dupe_flag: rows identical on every column but schedule_d_id
dupes <- va %>%
  select(-schedule_d_id) %>%
  get_dupes() %>%
  distinct() %>%
  mutate(dupe_flag = TRUE)
va <- va %>%
  left_join(dupes, by = setdiff(names(va), "schedule_d_id"), relationship = "many-to-one") %>%
  mutate(dupe_flag = !is.na(dupe_flag))
stopifnot(nrow(va) == n0)
cat("dupe_flag:", sum(va$dupe_flag), "\n")

va <- va %>%
  mutate(
    transaction_year = year(transaction_date),
    address_clean = norm_addr(va, c("address_line1", "address_line2")),
    com_address_clean = norm_addr(va, c("com_address_line1", "com_address_line2", "com_address_line3")),
    zip_clean = normal_zip(zip_code, na_rep = TRUE),
    com_zip_clean = normal_zip(com_zip_code, na_rep = TRUE),
    state_clean = normal_state(state_code, abbreviate = TRUE, na_rep = TRUE, valid = NULL),
    com_state_clean = normal_state(com_state_code, abbreviate = TRUE, na_rep = TRUE, valid = NULL),
    city_norm = normal_city(city, abbs = usps_city, states = c("VA", "VIRGINIA", "MA", "DC", "TX"),
                            na = invalid_city, na_rep = TRUE),
    com_city_norm = normal_city(com_city, abbs = usps_city, states = c("VA", "VIRGINIA", "MA", "DC", "TX"),
                                na = invalid_city, na_rep = TRUE),
    com_city_clean = city_swap(com_city_norm, com_state_clean, com_zip_clean)
  )

# payee city: swap with the ZIP code's city when within two edits
va <- va %>%
  left_join(zipcodes, by = c("state_clean" = "state", "zip_clean" = "zip"), suffix = c("", "_match")) %>%
  mutate(
    match_dist = str_dist(city_norm, city_match),
    city_swap = if_else(!is.na(match_dist) & match_dist <= 2, city_match, city_norm)
  )
stopifnot(nrow(va) == n0)

city_map <- tibble(city_swap = va$city_swap) %>%
  mutate(city_refine = n_gram_merge(key_collision_merge(city_swap), numgram = 1)) %>%
  distinct()
good <- va %>%
  distinct(city_swap, state_clean, zip_clean) %>%
  inner_join(city_map, by = "city_swap", relationship = "many-to-many") %>%
  filter(city_refine != city_swap) %>%
  semi_join(zipcodes, by = c("city_refine" = "city", "state_clean" = "state", "zip_clean" = "zip"))
va <- va %>%
  left_join(good, by = c("city_swap", "state_clean", "zip_clean")) %>%
  mutate(city_clean = coalesce(city_refine, city_swap)) %>%
  rename(com_city_raw = city)
stopifnot(nrow(va) == n0)

many_city <- c(valid_city, extra_city)
print(progress_table(str_to_upper(va$com_city_raw), va$city_norm, va$city_swap, va$city_clean, compare = many_city))
print(count(va, transaction_year), n = 40)
write_like_old(va, "va_expends_clean.csv", "va_expends_2012-2026.csv")
