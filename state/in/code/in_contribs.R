# Indiana campaign contributions -- rebuild 1998-2026, November 2026 (replaces in_contribs_clean.csv and
# in_contribs_clean_2020-2022.csv with one file).
#   python3 state/in/code/reparse.py <unzipped yearly files> state/in, then Rscript state/in/code/in_contribs.R,
#   from the repo root. The previous published files go in state/in/contribs/data/old/.
#
# Follows state/in/contribs/docs/in_contribs_diary.Rmd ("Update: November 2026"):
# - Source: the yearly contribution files 2000-2026 (extract of 11/13/2026), retrieved 2026-11-15, all rows,
#   including those with Amended = 1 (the files have no report or transaction ID to link an amendment to what it
#   replaced). Plus the rows of the previous in_contribs_clean.csv dated 1998-1999, as published: the state no longer
#   publishes those years.
# - Unchanged: column names and order; file = FileNumber, candiate = CandidateName, fil_type = CommitteeType,
#   fil_name = Received_By, con_type = ContributorType, method = Type, date = ContributionDate; "", "n/a", "NA" and
#   "N/A" read as missing; na_flag on committee, name, amount, date; dupe_flag on every column (all copies flagged);
#   year = year(date), limited to 1998-2026; addresses with normal_address(); ZIPs with normal_zip(); states
#   normalized and swapped with the ZIP code's state when one edit away; cities normalized and swapped with the ZIP
#   code's city when an abbreviation or within two edits; the diary's city replacements.
# - Changed: quotes inside fields are kept as published (the diary turned them into apostrophes); the city swap keeps
#   the normalized city when the ZIP code has no match (the diary's condition blanked those cities).
library(here)
here::i_am("state/in/code/in_contribs.R")
in_dataset <- "contribs"
source(here("state", "in", "code", "in_common.R"))

inc <- read_parsed("in_contributions.csv") %>%
  select(-source_file) %>%
  mutate(across(everything(), ~ if_else(.x %in% c("", "n/a", "NA", "N/A"), NA_character_, .x))) %>%
  clean_names("snake") %>%
  rename(file = file_number, candiate = candidate_name, fil_type = committee_type, fil_name = received_by,
         con_type = contributor_type, date = contribution_date, method = type) %>%
  mutate(
    file = as.integer(file),
    amount = as.double(amount),
    date = as_date(ymd_hms(date)),
    amended = amended == "1"
  )
stopifnot(!anyNA(inc$file), !anyNA(inc$date), !anyNA(inc$amended))
cat("rows:", nrow(inc), " amended:", sum(inc$amended), "\n")

inc <- flag_na(inc, committee, name, amount, date)
cat("na_flag:", sum(inc$na_flag), "\n")
inc <- flag_dupes(inc, everything())
cat("dupe_flag:", sum(inc$dupe_flag), "\n")
inc <- mutate(inc, year = pmin(pmax(year(date), 1998), 2026))

inc <- inc %>%
  mutate(
    address_clean = norm_addr(address),
    zip_clean = normal_zip(zip, na_rep = TRUE),
    state_clean = normal_state(state, abbreviate = TRUE, na_rep = TRUE, valid = NULL)
  )
# state swap: the ZIP code's state when one edit away
zip_state <- select(zipcodes, zip, state_match = state)
inc <- inc %>%
  left_join(zip_state, by = c("zip_clean" = "zip"), relationship = "many-to-one") %>%
  mutate(state_clean = if_else(!is.na(state_match) & str_dist(state, state_match) %in% 1, state_match,
                               state_clean)) %>%
  select(-state_match)

invalid <- c(invalid_city, "CITY OMITTED ON REPORT", "OMITTED ON REPORT", "OMITTED FROM REPORT")
inc <- inc %>%
  mutate(
    city_norm = norm_city(city, invalid),
    city_swap = city_swap(city_norm, state_clean, zip_clean, max_dist = 2),
    city_clean = city_swap %>%
      str_replace("^INDY$", "INDIANAPOLIS") %>%
      str_replace("^INDPLS$", "INDIANAPOLIS") %>%
      str_replace("^ABBOTT PARKS$", "ABBOTT PARK") %>%
      str_replace("^OVERLAND PARKS$", "OVERLAND PARK") %>%
      str_remove("\\sIN$")
  )
many_city <- c(valid_city, extra_city)
print(progress_table(str_to_upper(inc$city), inc$city_norm, inc$city_clean, compare = many_city))
cat("city_clean NA where city filed:", sum(is.na(inc$city_clean) & !is.na(inc$city)), "\n")

print(count(inc, year), n = 40)
write_with_old(inc, "in_contribs_clean.csv", "in_contribs_1998-2026.csv", "date")
