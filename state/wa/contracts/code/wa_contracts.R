# Washington Contracts: rebuild 2026-10-14. Inputs in `w` = state/wa/contracts/data (set below): raw/raw_n8q6-4twj.csv and
# old/old_wa_contracts.csv (the current file, for its column names); output in data/clean/.
#   Rscript state/wa/contracts/code/wa_contracts.R   # from the repo root
# Follows state/wa/contracts/docs/wa_contracts_diary.Rmd:
#   read the full data.wa.gov export n8q6-4twj (raw_n8q6-4twj.csv, downloaded 2026-10-14) with clean names;
#   vet_owned / small_business / diverse_options (columns 12-14) -> logical (== "Y"); omwbe kept as the code;
#   na_flag on customer_name + vendor_name; dupe_flag on every column; amount = sum of the four quarterly sales.
# Changes from the diary: reads the local download (not the URL); NA omwbe -> "N" as the diary did for the old file
# (none expected); writes one file with the year range in its name. Column order = the current
# csv/wa_contracts.csv.
suppressPackageStartupMessages({library(readr); library(dplyr); library(campfin); library(janitor); library(fs); library(here)})
w <- here("state", "wa", "contracts", "data")

wac <- read_csv(path(w, "raw", "raw_n8q6-4twj.csv"), name_repair = make_clean_names, progress = FALSE,
                col_types = cols(.default = col_character(), calendar_year = col_integer(),
                                 q1_sales_reported = col_double(), q2_sales_reported = col_double(),
                                 q3_sales_reported = col_double(), q4_sales_reported = col_double()))
message("read ", nrow(wac), " rows, ", ncol(wac), " columns")
print(count(wac, vet_owned)); print(count(wac, omwbe))
wac <- mutate(wac, across(12:14, ~ .x == "Y"))
wac$omwbe[is.na(wac$omwbe)] <- "N"
wac <- flag_na(wac, customer_name, vendor_name)
message("na_flag: ", sum(wac$na_flag))
wac <- flag_dupes(wac, everything())
message("dupe_flag: ", sum(wac$dupe_flag))
wac <- mutate(wac, amount = q1_sales_reported + q2_sales_reported + q3_sales_reported + q4_sales_reported)
message("amount NA: ", sum(is.na(wac$amount)))

old_cols <- names(read_csv(path(w, "old", "old_wa_contracts.csv"), n_max = 0, show_col_types = FALSE))
stopifnot(identical(names(wac), old_cols))
yrs <- range(wac$calendar_year, na.rm = TRUE)
out <- path(dir_create(path(w, "clean")), sprintf("wa_contracts_%d-%d.csv", yrs[1], yrs[2]))
write_csv(wac, out, na = "")
message("wrote ", out, ": ", nrow(wac), " rows")
print(count(wac, calendar_year))
