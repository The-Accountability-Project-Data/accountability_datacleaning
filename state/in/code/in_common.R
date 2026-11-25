# Shared code for the Indiana campaign finance builds (in_contribs.R, in_expends.R). Set in_dataset ("contribs" or
# "expends") before sourcing.
#
# Input: data/parsed/ from reparse.py (run it first), which stacks the yearly files
# https://campaignfinance.in.gov/PublicSite/Docs/BulkDataDownloads/<YEAR>_{Contribution,Expenditure}Data.csv.zip,
# 2000-2026, and the previous published file(s) in data/old/ (for the 1998-1999 rows, which the state no longer
# publishes, and the column order).
suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(tidyr); library(purrr)
  library(lubridate); library(janitor); library(campfin); library(refinr); library(fs); library(here)
})
base <- here("state", "in", in_dataset, "data")
out_dir <- dir_create(path(base, "clean"))

read_parsed <- function(file) {
  x <- read_csv(path(base, "parsed", file), na = character(), col_types = cols(.default = col_character()),
                progress = FALSE)
  stopifnot(nrow(problems(x)) == 0)
  x
}

# normal_address on each distinct value, joined back to the rows
norm_addr <- function(x) {
  u <- unique(x)
  normal_address(u, abbs = usps_street, na_rep = TRUE)[match(x, u)]
}

# normal_city on each distinct value, joined back to the rows
norm_city <- function(x, na) {
  u <- unique(x)
  normal_city(u, abbs = usps_city, states = c("IN", "DC", "INDIANA"), na = na, na_rep = TRUE)[match(x, u)]
}

# Swap the normalized city with the ZIP code's city when the condition holds; otherwise (including when the ZIP has
# no match) keep the normalized city. The diaries' conditions were NA when the ZIP had no match, which blanked the
# clean city of those rows.
city_swap <- function(city_norm, state, zip, max_dist) {
  m <- tibble(city_norm, state, zip) %>%
    left_join(zipcodes, by = c("state" = "state", "zip" = "zip"), relationship = "many-to-many")
  stopifnot(nrow(m) == length(city_norm))  # zipcodes is unique on (state, zip)
  m %>%
    mutate(
      match_abb = is_abbrev(city_norm, city),
      match_dist = str_dist(city_norm, city),
      swap = if_else(!is.na(city) & !is.na(city_norm) & (match_abb | match_dist <= max_dist), city, city_norm)
    ) %>%
    pull(swap)
}

# Write the new rows with the old file's columns, in its order, then append the old file's rows dated 1998-1999
# exactly as they were published.
write_with_old <- function(x, old_file, new_file, date_col) {
  old <- read_csv(path(base, "old", old_file), na = character(), col_types = cols(.default = col_character()),
                  progress = FALSE)
  stopifnot(nrow(problems(old)) == 0)
  hdr <- names(old)
  missing <- setdiff(hdr, names(x))
  if (length(missing)) stop("missing columns: ", paste(missing, collapse = ", "))
  old_9899 <- filter(old, str_sub(.data[[date_col]], 1, 4) %in% c("1998", "1999"))
  cat("old rows dated 1998-1999 kept:", nrow(old_9899), "\n")
  print(count(old_9899, y = str_sub(.data[[date_col]], 1, 4)))
  out <- path(out_dir, new_file)
  write_csv(select(x, all_of(hdr)), out, na = "")
  write_csv(old_9899, out, na = "", append = TRUE)
  cat("wrote", new_file, nrow(x) + nrow(old_9899), "rows,", length(hdr), "columns\n")
  invisible(old_9899)
}
