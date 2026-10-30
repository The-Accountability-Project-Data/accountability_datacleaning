# Copied 2026-10-30 from the datacleaning_agents repo (datasets/442-443-ne-campaign-finance/ne_contribs.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Dataset 442, Nebraska campaign contributions -- combined rebuild 2026-10-28 (NOT uploaded; would replace DataFile
# 1856 ne_contribs_19840101-20220329.csv). Run from the datacleaning_agents repo root:
#   Rscript datasets/442-443-ne-campaign-finance/ne_contribs.R
#
# One file for the whole range (user, 2026-10-28):
# - OLD ERA (legacy paper/keyed system, nadc_data.zip, filings received 1984-2021): the published 442 file
#   ne_contribs_19840101-20220329.csv (built by accountability_datacleaning/state/ne/contribs/docs/ne_contribs_diary.Rmd),
#   taken AS PUBLISHED -- values unchanged, only re-laid-out into the combined header (its 26 columns first, same
#   names and order, so the current 442 mapping keeps pointing at the same old-era data).
# - NEW ERA (NADC e-filing, FirstTuesday PublicSite yearly extracts 2021-2026 by FILING year, frozen at each year end):
#   rebuilt from all 12 current extracts following ne_contribs_diary_after_2021.Rmd (which built unpublished dataset
#   476): na_flag on (receipt date, filer name, amount, contributor last/org name), dupe_flag = flag_dupes over all
#   source columns, amount rounded to cents, year = calendar year of the receipt date, campfin address (address 1 +
#   2) / zip / city (normal_city -> zipcodes swap -> refine) normalization.
#   Changes from that diary: read as windows-1252 (it read UTF-8 and produced U+FFFD); a quote-aware-free reader
#   instead of its stray-quote regex (see read_nadc() in ne_common.R; values kept as published, CRLF inside a value
#   -> space); years 2021:2026; dates written as YYYY-MM-DD.
# - Shared columns: committee_id <- Org ID, committee_name <- Filer Name, committee_type <- Filer Type (old codes C/B/P/
#   T/I/R/S vs new words), date_received <- Filed Date, contribution_date <- Receipt Date, contribution_amount <- Receipt
#   Amount, contributor_name <- NEW derived "first middle last suffix" (old: the diary's "first middle last" or the
#   organization), contributor_address <- Address 1, contributor_city/state/zipcode <- City/State/Zip,
#   contribution_year, na_flag, dupe_flag, address_clean, city_clean, zip_clean. New-only fields follow, blank for the
#   old era; source_file says where each row came from.
# - 2021 overlap: old rows also present in the new system are DROPPED (new copy kept); rule in match_overlap()
#   (ne_common.R). Pairs written to out/ne_contribs_overlap_dropped.csv.
# Superseded records: the new system shows changes as "Offset due to update/delete of filed item" rows (negative
# amounts) next to the original; kept as published (same call as Alabama 126). Amended = Y kept. 0 rows dropped as
# superseded. The old system has no amendment marker.
here::i_am("datasets/442-443-ne-campaign-finance/ne_contribs.R")
source(here::here("datasets", "442-443-ne-campaign-finance", "ne_common.R"))

# ---- new era ----
rd <- read_all_years("ContributionLoan")
print(rd$log, width = 200)
nec <- rd$df
src <- setdiff(names(nec), "source_file")
nec <- nec %>%
  rename(receipt_id = `Receipt ID`, org_id = `Org ID`, filer_type = `Filer Type`, filer_name = `Filer Name`,
         candidate_name = `Candidate Name`, receipt_type = `Receipt Transaction/Contribution Type`,
         other_funds_type = `Other Funds Type`, receipt_date = `Receipt Date`, receipt_amount = `Receipt Amount`,
         description = Description, contributor_type = `Contributor or Transaction Source Type`,
         contributor_last_name = `Contributor or Source Name (Individual Last Name)`,
         contributor_first_name = `First Name`, contributor_middle_name = `Middle Name`, contributor_suffix = Suffix,
         address_1 = `Address 1`, address_2 = `Address 2`, city = City, state = State, zip = Zip,
         filed_date = `Filed Date`, amended = Amended, employer = Employer, occupation = Occupation)
src <- setdiff(names(nec), "source_file")
nec <- nec %>% mutate(across(c(receipt_date, filed_date), ~ mdy(.x, quiet = TRUE)))
stopifnot(sum(is.na(nec$receipt_date)) == 0)
nec <- flag_na(nec, all_of(c("receipt_date", "filer_name", "receipt_amount", "contributor_last_name")))
dupes <- duplicated(nec[src]) | duplicated(nec[src], fromLast = TRUE)
nec$dupe_flag <- dupes
nec <- nec %>%
  mutate(receipt_amount = round(as.numeric(receipt_amount), 2),
         year = year(receipt_date),
         address_clean = normal_address(na_if(str_squish(paste(coalesce(address_1, ""), coalesce(address_2, ""))), ""),
                                        abbs = usps_street, na_rep = TRUE),
         zip_clean = normal_zip(zip, na_rep = TRUE))
nec <- clean_city(nec, "city", "state", "zip_clean")
nec <- nec %>% mutate(contributor_name = full_name(contributor_first_name, contributor_middle_name,
                                                   contributor_last_name, contributor_suffix))
cat("new era rows", comma(nrow(nec)), "| na_flag", sum(nec$na_flag), "| dupe_flag", sum(nec$dupe_flag),
    "| dates", format(min(nec$receipt_date)), "..", format(max(nec$receipt_date)), "\n")

num_chr <- function(x) ifelse(is.na(x), NA_character_, sub("\\.$", "", sub("0+$", "", sprintf("%.2f", x))))
new_rows <- nec %>% transmute(
  committee_id = org_id, committee_name = filer_name, committee_type = filer_type,
  date_received = as.character(filed_date), contribution_date = as.character(receipt_date),
  contributor_name, contributor_address = address_1, contributor_city = city, contributor_state = state,
  contributor_zipcode = zip, contribution_amount = num_chr(receipt_amount),
  na_flag = as.character(na_flag), dupe_flag = as.character(dupe_flag), contribution_year = as.character(year),
  address_clean, city_clean, zip_clean,
  receipt_id, candidate_name, receipt_type, other_funds_type, description, contributor_type,
  contributor_last_name, contributor_first_name, contributor_middle_name, contributor_suffix,
  contributor_address_2 = address_2, amended, employer, occupation, source_file)

# ---- old era ----
old <- read_old(path(old_dir, "ne_contribs_19840101-20220329.csv"))
old_cols <- names(old)
stopifnot(nrow(old) == 239918, length(old_cols) == 26)

ov <- match_overlap(old, new_rows, "contribution_date", "contribution_amount", "contributor_name",
                    "contribution_date", "contribution_amount", "contributor_last_name", "receipt_id")
cat("2021 overlap: dropping", nrow(ov), "old rows; by new file:\n"); print(count(ov, n_file))
cat("  of which committee name also identical:", sum(ov$same_committee_name), "\n")
write_csv(ov %>% transmute(old_row = .oi, new_row = .ni, date = d, amount = a, new_file = n_file,
                           new_receipt_id = n_id, new_committee = n_committee, new_last_name = n_last,
                           old_committee = o_committee, old_name = o_name, old_form = o_form, same_committee_name),
          path(out_dir, "ne_contribs_overlap_dropped.csv"), na = "")
old_2021 <- sum(old$contribution_year == "2021", na.rm = TRUE)
cat("old rows dated 2021:", old_2021, "| dropped of those:", sum(str_sub(ov$d, 1, 4) == "2021"),
    "| kept (not found in new system):", old_2021 - sum(str_sub(ov$d, 1, 4) == "2021"), "\n")

old_rows <- (if (nrow(ov)) old[-ov$.oi, ] else old) %>% mutate(source_file = "nadc_data.zip")

# ---- combine ----
extra <- c("receipt_id", "candidate_name", "receipt_type", "other_funds_type", "description", "contributor_type",
           "contributor_last_name", "contributor_first_name", "contributor_middle_name", "contributor_suffix",
           "contributor_address_2", "amended", "employer", "occupation", "source_file")
cols <- c(old_cols, extra)
stopifnot(all(names(new_rows) %in% cols))
out <- bind_rows(old_rows, new_rows)[cols]
stopifnot(nrow(out) == nrow(old) - nrow(ov) + nrow(nec))
f <- write_out(out, "ne_contribs_1985-2026.csv")
cat("wrote", f, comma(nrow(out)), "rows,", length(cols), "columns,", comma(file_size(f)), "bytes\n")
write_csv(rd$log, path(out_dir, "ne_contribs_read_log.csv"))
