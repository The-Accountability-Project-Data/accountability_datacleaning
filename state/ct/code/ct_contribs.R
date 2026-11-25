# Connecticut campaign contributions -- rebuild 1999-2026, November 2026 (replaces ct_contribs_clean.csv and
# ct_contribs_20201006-20220201.csv). Rscript state/ct/code/ct_contribs.R <raw dir>, from the repo root.
# Output: state/ct/contribs/data/clean/ct_contribs_1999-2026.csv.
#
# - Source and reading: see ct_common.R. Receipts files only (Receipts* and Cifs_Receipts*).
# - Layout: the 64 columns of the earlier file, in the same order, with the same names: eCRIS columns renamed as
#   before (Contributor Name -> contributor, Committee Type -> fil_type, ...; "Election Year" of the 2009 PAC file ->
#   election_year_2), CIFS columns renamed as before (CONTRIB_DATE -> date, ...; contributor = first middle last).
#   Values as published (whitespace squished); "NO" is kept (the earlier build read it as missing).
# - source_type: CAND (candidate/exploratory files), PAC (party/PAC files), OLD (CIFS files). (The earlier file had
#   CAND and PAC swapped.)
# - All rows are kept. Amended reports are filed as separate reports (Report ID) that rarely repeat the rows of the
#   earlier report for the same period (2024 candidate file: 10 of 46,291 rows), so none are dropped as superseded.
# - date_clean from date (m/d/yyyy); year_clean = its year, missing outside 1998-2026. na_flag: contributor,
#   date_clean, amount or committee missing. dupe_flag: every copy of a row identical on all source columns.
# - address_clean, zip_clean, state_clean, city_clean (normalized; swapped with the ZIP code's city when an abbreviation
#   or one edit away; refined where the refined city/state/ZIP is valid).
library(here)
here::i_am("state/ct/code/ct_contribs.R")
source(here("state", "ct", "code", "ct_common.R"))
raw <- commandArgs(TRUE)[1]
out_dir <- dir_create(here("state", "ct", "contribs", "data", "clean"))

ECRIS <- c("Committee" = "committee", "Contributor Name" = "contributor", "District" = "district",
           "Office Sought" = "office", "Employer" = "employer", "Receipt Type" = "rec_type", "Committee Type" = "fil_type",
           "Transaction Date" = "date", "File To State" = "filed", "Amount" = "amount", "Receipt State" = "receipt",
           "Occupation" = "occupation", "ElectionYear" = "election_year", "Election Year" = "election_year_2",
           "Contractor Executive Branch" = "con_exec", "Contractor Legislative Branch" = "con_leg",
           "Contractor" = "contractor", "Lobbyist" = "lobbyist", "Data Source" = "source",
           "Refiled Electronically" = "refiled", "Street Address" = "address", "City" = "city", "State" = "state",
           "zip" = "zip", "Fundraising Event" = "event", "Report Name" = "report", "Committee ID" = "fil_id",
           "Section Letter" = "sec_letter", "Section Name" = "sec_name", "Period Start" = "period_start",
           "Period End" = "period_end", "Contributor First Name" = "first", "Contributor Middle Initial" = "middle",
           "Contributor Last Name" = "last", "Candidate First Name" = "candidate_first_name",
           "Candidate Middle Intial" = "candidate_middle_intial", "Candidate Last Name" = "candidate_last_name",
           "Report ID" = "report_id", "Form" = "form", "IsReimbursementClaimed" = "is_reimbursement_claimed",
           "Description" = "description", "Payment Method" = "method")
CIFS <- c("COMMITTEE NAME" = "committee", "REGISTRATION_TYPE" = "fil_type", "COMMITTEE_SUB_TYPE" = "fil_sub",
          "TRANS_SUBCATEGORYDE" = "trans_sub", "TRANSACTION_TYPE_DES" = "trans_type", "FILED_TO_STATE_DATE" = "filed",
          "TRANS_DISPLAY_NAME" = "trans_name", "IS_CONTRIBUTION" = "is_contrib", "SUBMITTED_DATE" = "submitted",
          "CONTRIB_COMID" = "fil_id", "COMMITTEES_COMMITTEENAME" = "comm_to", "CONTRIB_METHOD_CODE" = "method",
          "CONTRIB_DATE" = "date", "CONTRIB_AMOUNT" = "amount", "LOAN_AMOUNT" = "loan",
          "IN_KIND_CONTRIB_DESC" = "inkind_desc", "IN_KIND_EST_VALUE" = "inkind_est",
          "INTEREST_EARNED_AMOUNT" = "interest", "OCCUP_DESC" = "occupation", "OTHER_OCCUP_DESC" = "occup_desc",
          "FIRST_NAME" = "first", "MIDDLE_NAME" = "middle", "LAST_NAME" = "last", "CITY" = "city", "STATE" = "state",
          "ZIP_CODE" = "zip")
SRC <- c("committee", "contributor", "district", "office", "employer", "rec_type", "fil_type", "date", "filed", "amount",
         "receipt", "occupation", "election_year", "con_exec", "con_leg", "contractor", "lobbyist", "source", "refiled",
         "address", "city", "state", "zip", "event", "report", "fil_id", "sec_letter", "sec_name", "period_start",
         "period_end", "first", "middle", "last", "candidate_first_name", "candidate_middle_intial",
         "candidate_last_name", "report_id", "form", "is_reimbursement_claimed", "description", "method",
         "election_year_2", "source_file")
OLD_ONLY <- c("fil_sub", "trans_sub", "trans_type", "trans_name", "is_contrib", "submitted", "comm_to", "loan",
              "inkind_desc", "inkind_est", "interest", "occup_desc")
LAYOUT <- c(SRC, "date_clean", OLD_ONLY, "source_type", "na_flag", "dupe_flag", "year_clean", "address_clean",
            "zip_clean", "state_clean", "city_clean")
stopifnot(length(LAYOUT) == 64)

files <- dir_ls(raw, regexp = "(?i)/(Receipts\\d{4}|Cifs_Receipts).*\\.(csv|xlsx)$")
cat(length(files), "files\n")
cifs_names <- NULL; parts <- list()
for (f in c(sort(files[!grepl("Cifs_Receipts_2006", files)]), files[grepl("Cifs_Receipts_2006", files)])) {
  b <- basename(f)
  if (grepl("^Cifs", b)) {
    x <- if (b == "Cifs_Receipts_2006.csv") read_source(f, header = FALSE, col_names = cifs_names) else read_source(f)
    if (is.null(cifs_names)) cifs_names <- copy(names(x))
    stopifnot(all(names(x) %in% names(CIFS)))
    setnames(x, CIFS[names(x)])
    x[, contributor := na_if(str_squish(paste(fcoalesce(first, ""), fcoalesce(middle, ""), fcoalesce(last, ""))), "")]
    type <- "OLD"
  } else {
    x <- read_source(f)
    miss <- setdiff(names(x), names(ECRIS)); if (length(miss)) stop(b, ": unknown columns ", paste(miss, collapse = ", "))
    setnames(x, ECRIS[names(x)])
    type <- if (grepl("Candidate", b)) "CAND" else "PAC"
  }
  x[, `:=`(source_file = b, source_type = type)]
  cat(b, nrow(x), "rows;", attr(x, "cp1252_lines"), "windows-1252 lines\n")
  parts[[b]] <- x
}
ct <- rbindlist(parts, use.names = TRUE, fill = TRUE); rm(parts); invisible(gc(verbose = FALSE))
for (j in setdiff(LAYOUT, names(ct))) set(ct, j = j, value = NA_character_)
cat("rows:", nrow(ct), "\n"); print(ct[, .N, by = source_type])

ct[, amount := parse_amount(amount)]
ct[, date_clean := parse_mdy(date)]
ct[, year_clean := year(date_clean)]
ct[year_clean < 1998 | year_clean > 2026, year_clean := NA_integer_]
ct[, na_flag := is.na(contributor) | is.na(date_clean) | is.na(amount) | is.na(committee)]
DUPE <- setdiff(c(SRC, OLD_ONLY), "source_file")
ct[, dupe_flag := duplicated(ct, by = DUPE) | duplicated(ct, by = DUPE, fromLast = TRUE)]
ct[, address_clean := norm_address(address)]
ct[, zip_clean := norm_zip(zip)]
ct[, state_clean := norm_state(state)]
ct[, city_norm := norm_city(city)]
ct[, city_swap := do_city_swap(city_norm, state_clean, zip_clean)]
ct[, city_clean := do_refine(city_swap, state_clean, zip_clean)]

out <- path(out_dir, "ct_contribs_1999-2026.csv")
fwrite(ct[, ..LAYOUT], out, na = "", dateTimeAs = "ISO")
cat("na_flag", sum(ct$na_flag), " dupe_flag", sum(ct$dupe_flag), " date missing", sum(is.na(ct$date_clean)), "\n")
print(ct[, .N, keyby = year_clean], nrows = 60)
cat("wrote", out, nrow(ct), "rows,", length(LAYOUT), "columns\n")
