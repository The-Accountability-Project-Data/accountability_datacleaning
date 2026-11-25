# Indiana campaign expenditures -- rebuild 1998-2026, November 2026 (replaces in_expends_clean.csv).
#   python3 state/in/code/reparse.py <unzipped yearly files> state/in, then Rscript state/in/code/in_expends.R,
#   from the repo root. The previous published file goes in state/in/expends/data/old/.
#
# Follows state/in/expends/docs/in_expends_diary.Rmd ("Update: November 2026"):
# - Source: the yearly expenditure files 2000-2026 (extract of 11/13/2026), retrieved 2026-11-15, all rows,
#   including those with Amended = 1 (no report or transaction ID to link an amendment to what it replaced). Plus the
#   rows of the previous in_expends_clean.csv dated 1998-1999, as published: the state no longer publishes those years.
# - Unchanged: column names (the source's, snake case) and order; "" and "NA" read as missing; na_flag on committee,
#   name, expenditure_date, amount; dupe_flag = duplicated() on every column (the second and later copies);
#   date_flag = before 1998 or after the build date, date_clean = the date where not flagged, year_clean =
#   year(date_clean); addresses with normal_address(); ZIPs with normal_zip(); states normalized ("I" read as IN)
#   to valid abbreviations; cities normalized, swapped with the ZIP code's city when an abbreviation or within two
#   edits, refined (key collision and n-gram merge) where the refined city/state/ZIP is valid; the diary's city
#   replacements.
# - Changed: the files are split on the delimiters instead of the diary's read (whose broken rows it filtered);
#   quotes inside fields are kept as published; the city swap keeps the normalized city when the ZIP code has no
#   match (the diary's condition blanked those cities).
library(here)
here::i_am("state/in/code/in_expends.R")
in_dataset <- "expends"
source(here("state", "in", "code", "in_common.R"))

ind <- read_parsed("in_expenditures.csv") %>%
  select(-source_file) %>%
  mutate(across(everything(), ~ if_else(.x %in% c("", "NA"), NA_character_, .x))) %>%
  clean_names("snake") %>%
  mutate(
    amount = as.double(amount),
    expenditure_date = as_date(ymd_hms(expenditure_date)),
    amended = amended == "1"
  )
stopifnot(!anyNA(ind$expenditure_date), !anyNA(ind$amended), all(str_detect(ind$file_number, "^\\d+$")))
cat("rows:", nrow(ind), " amended:", sum(ind$amended), "\n")

ind <- flag_na(ind, committee, name, expenditure_date, amount)
cat("na_flag:", sum(ind$na_flag), "\n")
ind <- mutate(ind, dupe_flag = duplicated(ind))
cat("dupe_flag:", sum(ind$dupe_flag), "\n")

ind <- ind %>%
  mutate(
    date_flag = year(expenditure_date) < 1998 | expenditure_date > today(),
    date_clean = if_else(date_flag, as.Date(NA), expenditure_date),
    year_clean = year(date_clean),
    address_clean = norm_addr(address),
    zip_clean = normal_zip(zip, na_rep = TRUE),
    state_clean = normal_state(str_replace(str_trim(state), "^I$", "IN"), abbreviate = TRUE, na_rep = TRUE,
                               valid = valid_state),
    city_norm = norm_city(str_replace(city, rx_break("Indianapol;is"), "INDIANAPOLIS"), invalid_city),
    city_swap = city_swap(city_norm, state_clean, zip_clean, max_dist = 2)
  )
cat("date_flag:", sum(ind$date_flag), "\n")

# refine on the full column, as the diary does; keep a refined city only where the city/state/ZIP is valid
city_map <- tibble(city_swap = unique(ind$city_swap)) %>%
  mutate(city_refine = n_gram_merge(key_collision_merge(city_swap), numgram = 1))
good <- ind %>%
  distinct(city_swap, state_clean, zip_clean) %>%
  inner_join(city_map, by = "city_swap", relationship = "many-to-one") %>%
  filter(city_refine != city_swap) %>%
  semi_join(zipcodes, by = c("city_refine" = "city", "state_clean" = "state", "zip_clean" = "zip"))
n0 <- nrow(ind)
ind <- ind %>%
  left_join(good, by = c("city_swap", "state_clean", "zip_clean"), relationship = "many-to-one") %>%
  mutate(
    city_clean = coalesce(city_refine, city_swap) %>%
      str_replace("^INDPLS$", "INDIANAPOLIS") %>%
      str_replace("^EC$", "EAST CHICAGO") %>%
      str_replace("^INDY$", "INDIANAPOLIS") %>%
      str_replace("^MERR$", "MERRILLVILLE")
  )
stopifnot(nrow(ind) == n0)
cat("cities refined:", sum(!is.na(ind$city_refine)), "\n")
print(progress_table(str_to_upper(ind$city), ind$city_norm, ind$city_swap, ind$city_clean,
                     compare = c(valid_city, extra_city)))
cat("city_clean NA where city filed:", sum(is.na(ind$city_clean) & !is.na(ind$city)), "\n")

print(count(ind, year_clean), n = 40)
write_with_old(ind, "in_expends_clean.csv", "in_expends_1998-2026.csv", "expenditure_date")
