# Copied 2026-10-30 from the datacleaning_agents repo (datasets/464-chicago-contracts/chicago_contracts.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Dataset 464, Chicago Contracts — rebuild 2026-10-14 (user: work through Socrata group 1; NOT uploaded).
# Follows accountability_datacleaning/state/il/chicago/contracts/docs/chicago_contracts_diary.Rmd (2023), with changes:
#  - source: data.cityofchicago.org rsxa-ify5 "Contracts" full export (TAP's recorded downloadURL xzkq-xp2w is the
#    city's salaries dataset; the diary itself already used rsxa-ify5). The export can fail mid-stream (2026-10-14: a
#    500 "Internal error" JSON appended after 164,720 rows), so the record count is checked against the API count.
#  - read as standard CSV (doubled quotes are escapes). The diary's escape_double = FALSE kept them doubled: in the
#    2023 file 3" GOULD PUMPS reads 3"" GOULD PUMPS.
#  - campfin 1.0.11; same steps otherwise: clean_names, na_flag (approval_date, department, award_amount,
#    vendor_name), dupe_flag (all columns), award_amount rounded to cents, approval_year = year(approval_date),
#    dept_city/dept_state = CHICAGO/IL, zip_norm = normal_zip(zip).
# Revisions: each row is one contract revision (revision_number 0 = award, then modifications) with its own approval
#  date and the amount of that modification (negative = scope removed, per the portal). They add up; none is
#  superseded, and the source has no superseded/amended flag, so all rows are kept.
# Output: work/464-chicago-contracts/clean/il-chicago_contracts_<first>-<last approval date>.csv, same 25 columns in
#  the same order as the 2023 file (the mapping is positional).
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(lubridate); library(fs); library(janitor); library(campfin)
})
work <- path_expand("~/uc_berkeley/datacleaning_agents/work/464-chicago-contracts")
raw_csv <- path(work, "raw", "rows.csv")
api_count <- 186219   # https://data.cityofchicago.org/resource/rsxa-ify5.json?$select=count(*) on 2026-10-14

chic <- read_csv(raw_csv, locale = locale(date_format = "%m/%d/%Y"), na = "", progress = FALSE,
                 col_types = cols(.default = col_character(), `Start Date` = col_date(), `End Date` = col_date(),
                                  `Approval Date` = col_date(), `Award Amount` = col_double()))
stopifnot(nrow(problems(chic)) == 0, nrow(chic) == api_count)
chic <- clean_names(chic, case = "snake")
message("read ", nrow(chic), " rows x ", ncol(chic), " columns")

key_vars <- c("approval_date", "department", "award_amount", "vendor_name")
chic <- flag_na(chic, all_of(key_vars))
chic <- flag_dupes(chic, everything())
chic$award_amount <- round(chic$award_amount, digits = 2)
chic <- mutate(chic, approval_year = year(approval_date), dept_city = "CHICAGO", dept_state = "IL",
               zip_norm = normal_zip(zip = zip, na_rep = TRUE))
message("na_flag ", sum(chic$na_flag), " | dupe_flag ", sum(chic$dupe_flag),
        " | approval dates ", min(chic$approval_date, na.rm = TRUE), " .. ", max(chic$approval_date, na.rm = TRUE),
        " | future ", sum(chic$approval_date > today(), na.rm = TRUE))
print(progress_table(chic$zip, chic$zip_norm, compare = valid_zip))

old_cols <- c("purchase_order_description", "purchase_order_contract_number", "revision_number", "specification_number",
              "contract_type", "start_date", "end_date", "approval_date", "department", "vendor_name", "vendor_id",
              "address_1", "address_2", "city", "state", "zip", "award_amount", "procurement_type", "contract_pdf",
              "na_flag", "dupe_flag", "approval_year", "dept_city", "dept_state", "zip_norm")
stopifnot(identical(names(chic), old_cols))
ts <- paste(str_remove_all(min(chic$approval_date, na.rm = TRUE), "-"),
            str_remove_all(max(chic$approval_date, na.rm = TRUE), "-"), sep = "-")
out <- path(dir_create(path(work, "clean")), str_glue("il-chicago_contracts_{ts}.csv"))
write_csv(chic, out, na = "")
message("wrote ", out, " (", format(file_size(out)), ")")
