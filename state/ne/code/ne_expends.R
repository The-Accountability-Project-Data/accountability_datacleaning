# Copied 2026-10-30 from the datacleaning_agents repo (datasets/442-443-ne-campaign-finance/ne_expends.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Dataset 443, Nebraska campaign expenditures -- combined rebuild 2026-10-28 (NOT uploaded; would replace DataFile
# 1857 ne_expends_19970101-20220401.csv). Run from the datacleaning_agents repo root:
#   Rscript datasets/442-443-ne-campaign-finance/ne_expends.R
#
# Same design as ne_contribs.R (read its header):
# - OLD ERA: the published 443 file ne_expends_19970101-20220401.csv (ne_expends_diary.Rmd: legacy forms B1D, B2B,
#   B4B1 joined to A1), values unchanged, its 21 columns first in the same order.
# - NEW ERA: all 6 yearly ExpenditureExtract files 2021-2026, following ne_expends_diary_after_2021.Rmd (built
#   unpublished dataset 479): na_flag on (expenditure date, filer name, amount, payee last/org name), dupe_flag over
#   all source columns, amount rounded to cents, year from the expenditure date, campfin address/zip/city
#   normalization; state not cleaned (the diary: "needs not be cleaned") -> state_clean = State as published.
#   Same reader changes as contributions (windows-1252, no stray-quote regex, CRLF in a value -> space, ISO dates).
# - Shared columns: committee_id <- Org ID, committee_name <- Filer Name, committee_type <- Filer Type,
#   date_received <- Filed Date, payee_name <- NEW derived "first middle last suffix", payee_address <- Address 1,
#   expenditure_purpose <- Description, expenditure_date, expenditure_amount, na_flag, dupe_flag, expenditure_year,
#   zip_clean, state_clean. is_in_kind and payee_id are old-era only (the old diary derived is_in_kind; the new
#   system gives the type in transaction_type). address_clean / city_clean are new-era only (the old diary did not
#   make them; the old payee address is one free-text field).
# - Duplicate Expenditure IDs within a file are legitimate (one row per candidate supported), kept.
# - 2021 overlap: old rows also in the new system are DROPPED (new copy kept); rule in match_overlap() (ne_common.R).
# Superseded records: offset rows ("Offset due to update/delete of filed item") kept as published; Amended = Y kept;
# 0 rows dropped as superseded.
here::i_am("datasets/442-443-ne-campaign-finance/ne_expends.R")
source(here::here("datasets", "442-443-ne-campaign-finance", "ne_common.R"))

# ---- new era ----
rd <- read_all_years("Expenditure")
print(rd$log, width = 200)
nee <- rd$df %>%
  rename(expenditure_id = `Expenditure ID`, org_id = `Org ID`, filer_type = `Filer Type`, filer_name = `Filer Name`,
         candidate_name = `Candidate Name`, transaction_type = `Expenditure Transaction Type`,
         sub_type = `Expenditure Sub Type`, exp_date = `Expenditure Date`, exp_amount = `Expenditure Amount`,
         description = Description, payee_type = `Payee or Recipient or In-Kind Contributor Type`,
         payee_last_name = `Payee or Recipient or In-Kind Contributor Name`, payee_first_name = `First Name`,
         payee_middle_name = `Middle Name`, payee_suffix = Suffix, address_1 = `Address 1`, address_2 = `Address 2`,
         city = City, state = State, zip = Zip, filed_date = `Filed Date`, support_or_oppose = `Support Or Oppose`,
         candidate_or_ballot_issue = `Candidate Name or Ballot Issue`,
         jurisdiction_office_district = `Jurisdiction - Office - District or Ballot Description`, amended = Amended,
         employer = Employer, occupation = Occupation, principal_place_of_business = `Principal Place of Business`)
src <- setdiff(names(nee), "source_file")
nee <- nee %>% mutate(across(c(exp_date, filed_date), ~ mdy(.x, quiet = TRUE)))
stopifnot(sum(is.na(nee$exp_date)) == 0)
nee <- flag_na(nee, all_of(c("exp_date", "filer_name", "exp_amount", "payee_last_name")))
nee$dupe_flag <- duplicated(nee[src]) | duplicated(nee[src], fromLast = TRUE)
nee <- nee %>%
  mutate(exp_amount = round(as.numeric(exp_amount), 2),
         year = year(exp_date),
         address_clean = normal_address(na_if(str_squish(paste(coalesce(address_1, ""), coalesce(address_2, ""))), ""),
                                        abbs = usps_street, na_rep = TRUE),
         zip_clean = normal_zip(zip, na_rep = TRUE))
nee <- clean_city(nee, "city", "state", "zip_clean")
nee <- nee %>% mutate(payee_name = full_name(payee_first_name, payee_middle_name, payee_last_name, payee_suffix))
cat("new era rows", comma(nrow(nee)), "| na_flag", sum(nee$na_flag), "| dupe_flag", sum(nee$dupe_flag),
    "| dates", format(min(nee$exp_date)), "..", format(max(nee$exp_date)), "\n")

num_chr <- function(x) ifelse(is.na(x), NA_character_, sub("\\.$", "", sub("0+$", "", sprintf("%.2f", x))))
new_rows <- nee %>% transmute(
  committee_id = org_id, committee_name = filer_name, committee_type = filer_type,
  date_received = as.character(filed_date), payee_name, payee_address = address_1, expenditure_purpose = description,
  expenditure_date = as.character(exp_date), expenditure_amount = num_chr(exp_amount),
  na_flag = as.character(na_flag), dupe_flag = as.character(dupe_flag), expenditure_year = as.character(year),
  zip_clean, state_clean = state,
  expenditure_id, candidate_name, transaction_type, sub_type, payee_type, payee_last_name, payee_first_name,
  payee_middle_name, payee_suffix, payee_address_2 = address_2, payee_city = city, payee_state = state,
  payee_zip = zip, support_or_oppose, candidate_or_ballot_issue, jurisdiction_office_district, amended, employer,
  occupation, principal_place_of_business, address_clean, city_clean, source_file)

# ---- old era ----
old <- read_old(path(old_dir, "ne_expends_19970101-20220401.csv"))
old_cols <- names(old)
stopifnot(nrow(old) == 141082, length(old_cols) == 21)

ov <- match_overlap(old, new_rows, "expenditure_date", "expenditure_amount", "payee_name",
                    "expenditure_date", "expenditure_amount", "payee_last_name", "expenditure_id")
cat("2021 overlap: dropping", nrow(ov), "old rows; by new file:\n"); print(count(ov, n_file))
write_csv(ov %>% transmute(old_row = .oi, new_row = .ni, date = d, amount = a, new_file = n_file,
                           new_expenditure_id = n_id, new_committee = n_committee, new_last_name = n_last,
                           old_committee = o_committee, old_name = o_name, old_form = o_form),
          path(out_dir, "ne_expends_overlap_dropped.csv"), na = "")
old_2021 <- sum(old$expenditure_year == "2021", na.rm = TRUE)
cat("old rows dated 2021:", old_2021, "| dropped of those:", sum(str_sub(ov$d, 1, 4) == "2021"),
    "| kept (not found in new system):", old_2021 - sum(str_sub(ov$d, 1, 4) == "2021"), "\n")

old_rows <- (if (nrow(ov)) old[-ov$.oi, ] else old) %>% mutate(source_file = "nadc_data.zip")

# ---- combine ----
extra <- c("expenditure_id", "candidate_name", "transaction_type", "sub_type", "payee_type", "payee_last_name",
           "payee_first_name", "payee_middle_name", "payee_suffix", "payee_address_2", "payee_city", "payee_state",
           "payee_zip", "support_or_oppose", "candidate_or_ballot_issue", "jurisdiction_office_district", "amended",
           "employer", "occupation", "principal_place_of_business", "address_clean", "city_clean", "source_file")
cols <- c(old_cols, extra)
stopifnot(all(names(new_rows) %in% cols))
out <- bind_rows(old_rows, new_rows)[cols]
stopifnot(nrow(out) == nrow(old) - nrow(ov) + nrow(nee))
f <- write_out(out, "ne_expends_1999-2026.csv")
cat("wrote", f, comma(nrow(out)), "rows,", length(cols), "columns,", comma(file_size(f)), "bytes\n")
write_csv(rd$log, path(out_dir, "ne_expends_read_log.csv"))
