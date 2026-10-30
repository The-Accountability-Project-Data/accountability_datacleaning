# Copied 2026-10-30 from the datacleaning_agents repo (datasets/263-nj-salaries/nj_salaries.R): the script that built the October 2026 file.
# Its paths follow that repo's layout; point them at your own raw and output folders before running it from here.
#
# Dataset 263, New Jersey salary data — rebuild 2026-10-14.
# Follows accountability_datacleaning/state/nj/salaries/docs/nj_salaries_diary.Rmd (2020): read the full
# data.nj.gov export (iqwc-r2w7 "YourMoney Agency Payroll"), "null" -> NA, AS_OF_DATE "June 30 2026" -> 2026-06-30,
# ORIGINAL_EMPLOYMENT_DTE "2/6/2006" -> 2006-02-06, pay columns numeric, add state = "NJ", write CSV.
# Same 33 columns, same order as the 2020 file (dataset 263's mapping is positional).
# Changes from the diary: na_if("null") on a whole data frame no longer works in dplyr >= 1.1 (it now takes a vector),
# so "null" is handled at read time (na = c("", "null")); paths are this repo's work dir instead of here("nj", ...);
# the data dictionary / plots are skipped (not needed for the file). No superseded/amended flag exists in the source.
# Hire dates for earlier years are copied back from the previous file (see the backfill below).
suppressPackageStartupMessages({library(readr); library(dplyr); library(fs)})

base <- path_expand("~/uc_berkeley/datacleaning_agents/work/263-nj-salaries")
raw <- path(base, "raw", "nj_payroll_2026-10-14.csv")
out_dir <- dir_create(path(base, "out"))

njp <- read_csv(raw, col_types = cols(.default = col_character()), na = c("", "null"), progress = FALSE)
message("read ", format(nrow(njp), big.mark = ","), " rows, ", ncol(njp), " columns")

num_cols <- c("SALARY_HOURLY_RATE", "REGULAR_PAY", "SUPPLEMENTAL_PAY", "ONE_TIME_PAYMENTS", "LEGISLATOR_OR_BACK_PAY",
              "OVERTIME_PAYMENTS", "CLOTHING_UNIFORM_PAYMENTS", "RETROACTIVE_PAY", "LUMP_SUM_PAY", "YTD_EARNINGS",
              "CASH_IN_LIEU_MAINTENANCE", "MASTER_YTD_REGULAR_PAY", "MASTER_YTD_OVERTIME_PAYMENTS",
              "MASTER_YTD_ALL_OTHER_PAYMENTS", "MASTER_YTD_EARNINGS")
njp <- njp %>%
  mutate(
    AS_OF_DATE = as.Date(AS_OF_DATE, format = "%B %d %Y"),
    ORIGINAL_EMPLOYMENT_DTE = as.Date(ORIGINAL_EMPLOYMENT_DTE, format = "%m/%d/%Y"),
    across(all_of(num_cols), as.numeric),
    CALENDAR_YEAR = as.integer(CALENDAR_YEAR),
    state = "NJ")
message("AS_OF_DATE unparsed: ", sum(is.na(njp$AS_OF_DATE)),
        " | ORIGINAL_EMPLOYMENT_DTE NA: ", sum(is.na(njp$ORIGINAL_EMPLOYMENT_DTE)))

# Hire-date backfill (user, 2026-10-14). NJ publishes ORIGINAL_EMPLOYMENT_DTE only for the latest year in the export,
# so each refresh blanks the previous latest year's dates. Copy them back from our previous file (csv/nj_salaries_clean.csv,
# built 2020, where 2019 was the latest year): MASTER rows only (the only rows that carry it), matched on
# CALENDAR_YEAR + PAYROLL_ID + RECORD_TYPE, and only where the new value is blank.
old <- read_csv(path(base, "old", "nj_salaries_clean.csv"), col_types = cols(.default = col_character()),
                col_select = c(CALENDAR_YEAR, PAYROLL_ID, RECORD_TYPE, ORIGINAL_EMPLOYMENT_DTE), progress = FALSE)
old_cols <- names(read_csv(path(base, "old", "nj_salaries_clean.csv"), n_max = 0, show_col_types = FALSE))
hire <- old %>%
  filter(RECORD_TYPE == "MASTER", !is.na(ORIGINAL_EMPLOYMENT_DTE)) %>%
  transmute(CALENDAR_YEAR = as.integer(CALENDAR_YEAR), PAYROLL_ID, RECORD_TYPE,
            old_hire = as.Date(ORIGINAL_EMPLOYMENT_DTE)) %>%
  distinct()
stopifnot(!anyDuplicated(hire[c("CALENDAR_YEAR", "PAYROLL_ID", "RECORD_TYPE")]))
n_before <- nrow(njp)
blank_before <- sum(is.na(njp$ORIGINAL_EMPLOYMENT_DTE))
njp <- njp %>%
  left_join(hire, by = c("CALENDAR_YEAR", "PAYROLL_ID", "RECORD_TYPE"), relationship = "many-to-one") %>%
  mutate(ORIGINAL_EMPLOYMENT_DTE = coalesce(ORIGINAL_EMPLOYMENT_DTE, old_hire)) %>%
  select(-old_hire)
stopifnot(nrow(njp) == n_before)
message("hire-date backfill: ", format(blank_before - sum(is.na(njp$ORIGINAL_EMPLOYMENT_DTE)), big.mark = ","),
        " rows filled from the previous file (of ", format(nrow(hire), big.mark = ","), " available)")
print(njp %>% filter(!is.na(ORIGINAL_EMPLOYMENT_DTE)) %>% count(CALENDAR_YEAR))

stopifnot(identical(names(njp), old_cols))

yrs <- range(njp$CALENDAR_YEAR)
out <- path(out_dir, sprintf("nj_salaries_%d-%d.csv", yrs[1], yrs[2]))
write_csv(njp, out, na = "")
message("wrote ", out, ": ", format(nrow(njp), big.mark = ","), " rows")
print(count(njp, CALENDAR_YEAR, CALENDAR_QUARTER, RECORD_TYPE) %>% tidyr::pivot_wider(names_from = RECORD_TYPE, values_from = n), n = 50)
