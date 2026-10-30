# Copied 2026-10-30 from the datacleaning_agents repo (datasets/370-plum-book/us_plum_book_2024.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Dataset 370, United States Plum Book -- 2024 edition, built 2026-10-28 as a SECOND DataFile for 370 (user approved).
# Follows accountability_datacleaning/national/plum_book/docs/us_plum_book.Rmd (2021, 2020 edition only):
# stack the 4 xlsx in GPO-PLUMBOOK-2024.zip xls/ as text, clean_names, title-case agcy_name/org_name, parse expires,
# flag_na / flag_dupes, date = publication date (2024-11-12, mods.xml dateIssued), year = 2024, split location.
# Output has exactly the 20 columns, in order, of the 2020 file csv/us_plum_book.csv.
# Changes from the diary (2024 xlsx differ from 2020):
#  - every cell is space-padded (empty cells are runs of spaces): str_squish + "" -> NA on all columns;
#  - 2,968 all-blank rows (padding, mostly at the end of -9.xlsx) and 179 agency heading rows (agency + ID only,
#    no title and no incumbent) are dropped (user, 2026-10-28);
#  - expires is text, "2024-10-10T00:00:00.000" or "7/29/2026", not an Excel serial: parse both forms;
#  - `country` expanded from the source's 4-letter truncations (Belg -> Belgium, ...); `location` kept as published;
#  - tenure (bare numbers, no unit; 2020 had "5 Years"/"36 Months") and level_grade_or_pay (no dollar amounts in 2024)
#    are kept as published -- units can't be inferred;
#  - paths are this repo's work dir instead of here("us", "plum_book", ...); plots skipped.
# No superseded/amended flag in this source.
suppressPackageStartupMessages({
  library(readxl); library(dplyr); library(readr); library(stringr); library(tidyr)
  library(purrr); library(lubridate); library(janitor); library(campfin); library(fs)
})

base <- path_expand("~/uc_berkeley/datacleaning_agents/work/370-plum-book")
xls_dir <- path(base, "x2024", "GPO-PLUMBOOK-2024", "xls")   # unzipped from raw/2026-10-28/GPO-PLUMBOOK-2024.zip
if (!dir_exists(xls_dir)) {
  unzip(path(base, "raw", "2026-10-28", "GPO-PLUMBOOK-2024.zip"), exdir = path(base, "x2024"))
}
raw_xls <- dir_ls(xls_dir, glob = "*.xlsx")
names(raw_xls) <- basename(raw_xls)
out_path <- path(dir_create(path(base, "out")), "us_plum_book_2024.csv")

pb <- map_dfr(raw_xls, read_xlsx, .id = "src_file", col_types = "text")
message("read ", nrow(pb), " sheet rows, ", ncol(pb), " columns")

pb <- pb %>%
  clean_names(case = "snake") %>%
  relocate(src_file, .after = last_col()) %>%
  mutate(across(-src_file, ~na_if(str_squish(.), "")))

n_blank <- sum(is.na(pb$agcy_name) & is.na(pb$title) & is.na(pb$name_of_incumbent) & is.na(pb$location))
n_head <- sum(!is.na(pb$agcy_name) & is.na(pb$title) & is.na(pb$name_of_incumbent))
pb <- filter(pb, !is.na(title) | !is.na(name_of_incumbent))
message("dropped ", n_blank, " blank rows and ", n_head, " agency heading rows; kept ", nrow(pb))

parse_expires <- function(x) {
  iso <- as.Date(str_sub(x, 1, 10), format = "%Y-%m-%d")
  us <- as.Date(x, format = "%m/%d/%Y")
  coalesce(iso, us)
}
pb <- pb %>%
  mutate(across(c(agcy_name, org_name), str_to_title)) %>%
  mutate(expires_raw = expires, expires = parse_expires(expires))
bad <- filter(pb, !is.na(expires_raw) & is.na(expires))
message("expires unparsed: ", nrow(bad), if (nrow(bad)) paste0(" e.g. ", paste(head(unique(bad$expires_raw)), collapse = " | ")) else "")
pb <- select(pb, -expires_raw)

key_vars <- c("agcy_name", "title", "name_of_incumbent")
pb <- flag_na(pb, all_of(key_vars))
pb <- flag_dupes(pb, -id_number)
message("na_flag ", sum(pb$na_flag), ", dupe_flag ", sum(pb$dupe_flag))

pb <- pb %>% mutate(date = ymd("2024-11-12"), year = year(date))

pb <- pb %>%
  separate(col = location, into = c("city", "state"), sep = ",\\s", extra = "merge", fill = "right", remove = FALSE) %>%
  relocate(city, state, .after = last_col()) %>%
  mutate(
    country = na_if(str_remove(state, "^[:upper:]{2}$"), ""),
    country = if_else(is.na(country) & !is.na(state), "United States", country),
    state = na_if(str_extract(state, "^[:upper:]{2}$"), "")
  )
# 2024 source truncates the country in `location` to 4 letters ("Brussels, Belg"); `location` is kept as published,
# `country` is expanded so it matches the 2020 file's full names.
country_4 <- c(Belg = "Belgium", Germ = "Germany", Puer = "Puerto Rico", Ital = "Italy", Swit = "Switzerland",
               Japa = "Japan", Unit = "United Kingdom", Virg = "Virgin Islands", Aust = "Austria")
pb <- mutate(pb, country = coalesce(unname(country_4[country]), country))
message("country values: ", paste(sort(unique(na.omit(pb$country))), collapse = ", "))

old_cols <- c("agcy_name", "org_name", "org_name_level", "id_number", "location", "title", "name_of_incumbent",
              "type_of_appt", "pay_plan", "level_grade_or_pay", "tenure", "expires", "src_file", "na_flag",
              "dupe_flag", "date", "year", "city", "state", "country")
stopifnot(identical(names(pb), old_cols))
write_csv(pb, out_path, na = "")
message("wrote ", out_path, ": ", nrow(pb), " rows, ", ncol(pb), " columns, ", file_size(out_path))
