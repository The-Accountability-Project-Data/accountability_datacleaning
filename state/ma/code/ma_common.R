# Shared code for the Massachusetts campaign finance builds (ma_contribs.R, ma_expends.R).
#
# Input: data/parsed/ma_items.csv and ma_reports.csv from reparse.py (run it first). They stack the OCPF yearly files
# https://ocpf2.blob.core.windows.net/downloads/data2/ocpf-<YYYY>-reports.zip, 2002-2026. OCPF's readme: the files hold
# the latest version of each report; data from reports that have been amended is excluded. So no amendment step.
# Record type and tender type names come from the readme.
suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(tidyr); library(purrr)
  library(lubridate); library(janitor); library(campfin); library(refinr); library(fs); library(glue); library(here)
})
ma_dir <- here("state", "ma", "data")

read_parsed <- function(file) {
  x <- read_csv(path(ma_dir, "parsed", file), na = "", col_types = cols(.default = col_character()),
                progress = FALSE)
  stopifnot(nrow(problems(x)) == 0)
  x
}

# Item record types (readme "ITEM RECORD TYPES") and tender types ("TENDER TYPES")
readme <- read_lines(path(ma_dir, "raw", "2026", "readme.txt"))
section <- function(start, end) {
  i <- which(str_detect(readme, start))[1]; j <- which(str_detect(readme, end))[1]
  readme[(i + 1):(j - 1)] %>% str_trim() %>% keep(~ str_detect(.x, "^\\d+\\t"))
}
rec_types <- tibble(x = section("^ID\\tRecord_Type", "^TENDER TYPES")) %>%
  separate(x, c("record_type_id", "type_name"), sep = "\\t+", extra = "merge") %>%
  mutate(type_name = str_trim(type_name))
tender_types <- tibble(x = section("^TENDER TYPES", "^Report Data Fields")) %>%
  separate(x, c("tender_id", "tender_name"), sep = "\\t+", extra = "merge") %>%
  mutate(tender_name = str_trim(str_remove(tender_name, "\\s*\\(Deprecated.*\\)$")))
stopifnot(!anyDuplicated(rec_types$record_type_id), nrow(tender_types) == 7)

items_raw <- read_parsed("ma_items.csv")
reports <- read_parsed("ma_reports.csv")
stopifnot(!anyDuplicated(items_raw$Item_ID), !anyDuplicated(reports$Report_ID),
          all(items_raw$Report_ID %in% reports$Report_ID))
cat("items:", nrow(items_raw), " reports:", nrow(reports), "\n")

# Items of the given record types; date as m/d/Y, amount numeric.
select_items <- function(types) {
  x <- filter(items_raw, Record_Type_ID %in% types)
  d <- mdy(x$Date, quiet = TRUE)
  stopifnot(sum(is.na(d) & !is.na(x$Date)) == 0)
  x$Date <- d
  x$Amount <- as.numeric(x$Amount)
  print(count(x, Record_Type_ID), n = 50)
  x
}

# Street addresses: normal_address() on each distinct value; the 2023 diary's " TH" fix.
norm_addr <- function(a) {
  u <- tibble(a = unique(a)) %>%
    mutate(n = normal_address(a, abbs = usps_street, na_rep = TRUE),
           n = str_remove(n, "(?<=\\d)\\s(?=TH\\b)"))
  u$n[match(a, u$a)]
}

# City: normal_city(), swapped with the ZIP code's city when an abbreviation of it or one edit away, then refined
# (key collision + n-gram) where the refined city/state/ZIP is a valid combination. Keyed on distinct
# city/state/ZIP. Returns the clean city, one per row.
clean_city <- function(city, state_clean, zip_clean) {
  usps <- add_row(usps_city, abb = "SO", full = "SOUTH")
  key <- tibble(city, state_clean, zip_clean)
  u <- distinct(key) %>%
    mutate(city_norm = normal_city(city, abbs = usps, states = c("MA", "DC", "MASSACHUSETTS"),
                                   na = invalid_city, na_rep = TRUE)) %>%
    left_join(zipcodes, by = c("state_clean" = "state", "zip_clean" = "zip"), suffix = c("", "_match"),
              relationship = "many-to-one") %>%
    mutate(match_abb = is_abbrev(city_norm, city_match),
           match_dist = str_dist(city_norm, city_match),
           city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm))
  refine <- tibble(city_swap = unique(u$city_swap)) %>%
    mutate(city_refine = n_gram_merge(key_collision_merge(city_swap), numgram = 1))
  u <- u %>%
    left_join(refine, by = "city_swap") %>%
    left_join(mutate(zipcodes, ok = TRUE), by = c("city_refine" = "city", "state_clean" = "state", "zip_clean" = "zip"),
              relationship = "many-to-one") %>%
    mutate(city_clean = if_else(!is.na(ok) & city_refine != city_swap, city_refine, city_swap))
  many_city <- c(valid_city, extra_city)
  print(progress_table(str_to_upper(u$city), u$city_norm, u$city_swap, u$city_clean, compare = many_city))
  left_join(key, select(u, city, state_clean, zip_clean, city_clean),
            by = c("city", "state_clean", "zip_clean"))$city_clean
}

add_geo <- function(x) {
  x %>% mutate(
    address_clean = norm_addr(address),
    zip_clean = normal_zip(zip, na_rep = TRUE),
    state_clean = normal_state(state, abbreviate = TRUE, na_rep = TRUE, valid = NULL),
    city_clean = clean_city(city, state_clean, zip_clean)
  )
}

write_out <- function(x, cols, dataset, file) {
  stopifnot(setequal(intersect(cols, names(x)), cols))
  out <- path(dir_create(here("state", "ma", dataset, "data", "clean")), file)
  write_csv(select(x, all_of(cols)), out, na = "")
  cat("wrote", out, nrow(x), "rows,", length(cols), "columns\n")
}
