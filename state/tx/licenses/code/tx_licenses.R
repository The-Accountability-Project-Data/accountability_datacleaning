# Copied 2026-10-30 from the datacleaning_agents repo (datasets/449-tx-licenses/tx_licenses.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Texas Licenses 2026 (new dataset; predecessor 449 "Texas licenses") — build 2026-10-28.
# Follows accountability_datacleaning/state/tx/licenses/docs/tx_licenses_diary.Rmd (Kiernan Nicholls, 2022) on the TDLR
# all-licenses file https://www.tdlr.texas.gov/dbproduction2/ltlicfile.csv (retrieved 2026-10-28, Last-Modified
# 2026-10-28 11:26:30 GMT; see datasets/449-tx-licenses/retrievals.jsonl).
#
# Output: exactly the 2022 file's 28 columns in the same order (449's mapping is the template).
# Changes from the diary (user decisions 2026-10-28 marked *):
#  - Read: the file now has a header row and 23 columns (the 19 in lrformat.txt + 4 TDLR flag columns), and 279
#    Boiler Inspector rows carry a 24th field after the 19th. Read 24 unnamed columns, skip the header, keep 1-19.
#    The 2022 workaround (a 20th "UNKOWN DATE" column + fix.csv) is gone; `unkown_date` is written blank.
#  - * The 4 flag columns (Same Address or not, Business/Mailing address that mentions BOX, Phone-same or not) dropped.
#  - * license_expiration_year is blank (NA) for the 01/01/1900 placeholder dates (652 Elevator Responsible Party
#    rows); the date itself is kept as published.
#  - * Rows with a blank LICENSE TYPE (barber shops etc.) kept as published.
#  - City refine: computed on the city vector and validated against zipcodes per row, instead of the diary's
#    left_join(txl, good_refine) on every column (which can duplicate rows); same rule, no join blow-up.
#  - across(x, na_if, "") -> across(x, ~na_if(.x, "")) (dplyr >= 1.1); paths are this repo's work dir; plots skipped.
# No superseded/amended flag exists in this source.
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr); library(stringr); library(lubridate)
  library(campfin); library(refinr); library(fs)
})

base <- path_expand("~/uc_berkeley/datacleaning_agents/work/449-tx-licenses")
raw_csv <- path(base, "raw", "2026-10-28", "ltlicfile.csv")
old_csv <- path(base, "old", "tx_licenses_2018-20220516.csv")
out_dir <- dir_create(path(base, "out"))

old_cols <- names(read_csv(old_csv, n_max = 0, show_col_types = FALSE))
stopifnot(length(old_cols) == 28)

src_names <- c("license_type", "license_number", "license_expiration_date", "county", "name",
               "mailing_address_line1", "mailing_address_line2", "mailing_address_city_state_zip", "phone_number",
               "business_name", "business_address_line1", "business_address_line2", "business_city_state_zip",
               "business_county_code", "business_county", "business_zip", "business_phone", "license_subtype",
               "continuing_education_flag")

hdr <- read_lines(raw_csv, n_max = 1)
message("source header: ", hdr)

txl <- read_delim(
  raw_csv, delim = ",", skip = 1,
  escape_backslash = FALSE, escape_double = FALSE,
  col_names = paste0("X", 1:24),
  col_types = cols(.default = col_character()),
  na = c("", "NA"), trim_ws = TRUE, progress = FALSE
)
# readr keeps the header's 23 columns and drops the 24th field of the 279 Boiler Inspector rows (reported as
# problems); their first 19 fields are aligned, so nothing we keep is affected.
probs <- problems(txl)
message("read ", format(nrow(txl), big.mark = ","), " rows, ", ncol(txl), " columns; parse problems: ", nrow(probs),
        " (", paste(unique(paste(probs$expected, "->", probs$actual)), collapse = "; "), ")")
stopifnot(all(probs$col == 24), all(probs$actual == "24 columns"))
txl <- txl %>% select(1:19) %>% setNames(src_names)
message("problem rows by license type: ",
        paste(names(table(txl$license_type[probs$row])), table(txl$license_type[probs$row]), collapse = ", "))

txl <- txl %>% mutate(
  license_expiration_date = as.Date(license_expiration_date, format = "%m/%d/%Y"),
  unkown_date = as.Date(NA)
)
message("unparsed expiration dates: ", sum(is.na(txl$license_expiration_date)))
stopifnot(all(txl$continuing_education_flag %in% c("Y", "N", NA)))

# flags, as the diary
key_vars <- c("license_type", "license_expiration_date", "name", "business_name")
txl <- flag_na(txl, all_of(key_vars))
txl <- flag_dupes(txl, -license_number)
message("na_flag: ", sum(txl$na_flag), " | dupe_flag: ", sum(txl$dupe_flag))

# year = expiration year; blank for the 1900-01-01 placeholder (user, 2026-10-28)
txl <- txl %>% mutate(
  license_expiration_year = if_else(license_expiration_date == as.Date("1900-01-01"),
                                    NA_integer_, as.integer(year(license_expiration_date)))
)
message("placeholder 1900 rows blanked: ", sum(txl$license_expiration_date == as.Date("1900-01-01"), na.rm = TRUE))

# city/state/zip split, as the diary (source business_zip replaced by the split zip)
txl <- txl %>%
  select(-business_zip) %>%
  extract(col = business_city_state_zip, into = c("business_city", "business_state", "business_zip"),
          regex = "(.*)\\s(\\w{2})\\s(.*)$", remove = FALSE)
bad_split <- which(!is.na(txl$business_city_state_zip) & is.na(txl$business_city))
txl$business_city[bad_split] <- word(txl$business_city_state_zip[bad_split], 1)
message("bad city/state/zip splits (city = first word): ", length(bad_split))

# address
addr_norm <- txl %>%
  distinct(business_address_line1, business_address_line2) %>%
  mutate(
    address_norm1 = normal_address(business_address_line1, abbs = usps_street, na_rep = TRUE),
    address_norm2 = normal_address(business_address_line2, abbs = usps_street, na_rep = TRUE, abb_end = FALSE)
  ) %>%
  unite(col = address_norm, starts_with("address_norm"), sep = " ", remove = TRUE, na.rm = TRUE) %>%
  mutate(across(address_norm, ~na_if(.x, "")))
txl <- left_join(txl, addr_norm, by = c("business_address_line1", "business_address_line2"))

# zip
txl <- mutate(txl, zip_norm = normal_zip(business_zip, na_rep = TRUE))

# city: normal + swap, as the diary
norm_city <- txl %>%
  distinct(business_city, business_state, zip_norm) %>%
  mutate(city_norm = normal_city(business_city, abbs = usps_city, states = c("TX", "DC", "TEXAS"),
                                 na = invalid_city, na_rep = TRUE)) %>%
  rename(city_raw = business_city) %>%
  left_join(zipcodes, by = c("business_state" = "state", "zip_norm" = "zip")) %>%
  rename(city_match = city) %>%
  mutate(
    match_abb = is_abbrev(city_norm, city_match),
    match_dist = str_dist(city_norm, city_match),
    city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)
  ) %>%
  select(-city_match, -match_dist, -match_abb)
stopifnot(!anyDuplicated(norm_city[c("city_raw", "business_state", "zip_norm")]))
n0 <- nrow(txl)
txl <- left_join(txl, norm_city, by = c("business_city" = "city_raw", "business_state", "zip_norm"))
stopifnot(nrow(txl) == n0)

# city: refine, kept only when the refined city/state/zip is a valid combination (same rule as the diary)
refined <- txl$city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)
valid_key <- paste(zipcodes$city, zipcodes$state, zipcodes$zip)
ok <- !is.na(refined) & !is.na(txl$city_swap) & refined != txl$city_swap &
  paste(refined, txl$business_state, txl$zip_norm) %in% valid_key
txl$city_refine <- if_else(ok, refined, txl$city_swap)
message("cities refined: ", sum(ok))

txl <- txl %>%
  select(-city_norm, -city_swap, city_clean = city_refine) %>%
  rename(address_clean = address_norm, zip_clean = zip_norm)

# exact old layout
stopifnot(setequal(names(txl), old_cols))
txl <- txl[old_cols]

yrs <- range(txl$license_expiration_year[txl$license_expiration_year < 2099], na.rm = TRUE)
out_csv <- path(out_dir, sprintf("tx_licenses_%d-%d.csv", yrs[1], yrs[2]))
write_csv(txl, out_csv, na = "")
message("wrote ", out_csv, ": ", format(nrow(txl), big.mark = ","), " rows, ", ncol(txl), " columns, ",
        format(file_size(out_csv)))
