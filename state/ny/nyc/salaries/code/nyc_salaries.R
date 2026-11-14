# New York City Citywide Payroll Data -- rebuild 2026-10-28.
# Follows state/ny/nyc/salaries/docs/nyc_salaries_diary.Rmd (2020): read the full
# export of NYC OPA "Citywide Payroll Data (Fiscal Year)" (k397-673e, now on data.cityofnewyork.us), clean_names(),
# add state = "NY" and city = "NEW YORK CITY", parse agency_start_date (MM/DD/YYYY), total_gross_pay =
# regular_gross_paid + total_ot_paid + total_other_pay, flag_na(first_name, last_name, title_description),
# flag_dupes(everything()), write CSV. Same 22 columns, same order as the 2020 file.
# Changes from the diary: source host moved (data.ny.gov -> data.cityofnewyork.us); explicit column types instead of
# guessing; write_csv(file =) (readr >= 2); campfin's flag_na/flag_dupes are re-implemented inline with the same
# semantics (na_flag = any of the three is NA; dupe_flag = row identical to another over all columns, both copies
# flagged) so the build needs only readr/dplyr/janitor; dictionary and plots skipped. No superseded/amended flag exists in the source.
#   Rscript state/ny/nyc/salaries/code/nyc_salaries.R from the repo root; put the export (*rows.csv) in
#   state/ny/nyc/salaries/data/raw/ and the 2020 nyc_salaries_clean.csv in state/ny/nyc/salaries/data/old/.
#   Output goes to state/ny/nyc/salaries/data/clean/.
suppressPackageStartupMessages({library(readr); library(dplyr); library(fs); library(janitor); library(here)})

here::i_am("state/ny/nyc/salaries/code/nyc_salaries.R")
base <- here("state", "ny", "nyc", "salaries", "data")
raw <- dir_ls(path(base, "raw"), recurse = TRUE, glob = "*rows.csv")
stopifnot(length(raw) == 1)
out_dir <- dir_create(path(base, "clean"))
old_cols <- names(read_csv(path(base, "old", "nyc_salaries_clean.csv"), n_max = 0, show_col_types = FALSE))

nyp <- read_csv(raw, col_types = cols(.default = col_character()), progress = FALSE) %>% clean_names()
message("read ", raw, ": ", format(nrow(nyp), big.mark = ","), " rows, ", ncol(nyp), " columns")
stopifnot(identical(names(nyp), old_cols[1:17]))

num_cols <- c("fiscal_year", "payroll_number", "base_salary", "regular_hours", "regular_gross_paid", "ot_hours",
              "total_ot_paid", "total_other_pay")
nyp <- nyp %>%
  mutate(
    across(all_of(num_cols), parse_double),
    state = "NY",
    city = "NEW YORK CITY",
    agency_start_date = as.Date(agency_start_date, format = "%m/%d/%Y"),
    total_gross_pay = regular_gross_paid + total_ot_paid + total_other_pay,
    na_flag = is.na(first_name) | is.na(last_name) | is.na(title_description))
message("number parse problems: ", nrow(problems(nyp)))
dup <- duplicated(nyp) | duplicated(nyp, fromLast = TRUE)
nyp$dupe_flag <- dup
message("agency_start_date NA: ", sum(is.na(nyp$agency_start_date)),
        " | na_flag: ", sum(nyp$na_flag), " | dupe_flag: ", sum(nyp$dupe_flag))

stopifnot(identical(names(nyp), old_cols))
yrs <- range(nyp$fiscal_year)
out <- path(out_dir, sprintf("nyc_salaries_%d-%d.csv", yrs[1], yrs[2]))
write_csv(nyp, out, na = "")
message("wrote ", out, ": ", format(nrow(nyp), big.mark = ","), " rows")
print(count(nyp, fiscal_year), n = 50)
