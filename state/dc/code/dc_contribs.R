# DC campaign contributions -- full rebuild from the DC Office of Campaign Finance e-filing search, November 2026
# (replaces dc_contribs_clean.csv and dc_contribs_20230517.csv, which came from DC's open data layer). From the repo
# root: python3 state/dc/code/reparse.py <raw dir>; Rscript state/dc/code/dc_contribs.R
# Output: state/dc/contribs/data/clean/dc_contribs_2003-2026.csv.
#
# - Source and reading: see dc_common.R.
# - Rows: every contribution, all filer types, as published (including about 1,500 $0.00 rows with no contributor,
#   from committees' empty reports).
# - Layout (new; the earlier build used the open data layer's columns): the 16 source columns in snake case
#   (committee_name, contributor_first_name, contributor_middle_name, contributor_last_name,
#   contributor_organization_name, contributor_street, contributor_city, contributor_state, contributor_zipcode,
#   contributor_type, contribution_type, employer_name, employer_address, occupation, receipt_date, amount), then
#   contributor_name ("first middle last", or the organization name), na_flag, dupe_flag, year, and address_clean,
#   city_clean, state_clean, zip_clean for the contributor.
# - All rows kept. na_flag: receipt_date, amount, contributor_name or committee_name missing. dupe_flag: every copy of
#   a row identical on all source columns. year = year(receipt_date).
library(here)
here::i_am("state/dc/code/dc_contribs.R")
source(here("state", "dc", "code", "dc_common.R"))
SRC <- c("Committee Name", "Contributor First Name", "Contributor Middle Name", "Contributor Last Name",
         "Contributor Organization Name", "Contributor Street", "Contributor City", "Contributor State",
         "Contributor ZipCode", "Contributor Type", "Contribution Type", "Employer Name", "Employer Address",
         "Occupation", "Receipt Date", "Amount")
NAMES <- c("committee_name", "contributor_first_name", "contributor_middle_name", "contributor_last_name",
           "contributor_organization_name", "contributor_street", "contributor_city", "contributor_state",
           "contributor_zipcode", "contributor_type", "contribution_type", "employer_name", "employer_address",
           "occupation", "receipt_date", "amount")
LAYOUT <- c(NAMES, "contributor_name", "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")
out_dir <- dir_create(here("state", "dc", "contribs", "data", "clean"))
build_dc(here("state", "dc", "data", "parsed", "dc_contributions.csv"), SRC, NAMES, "receipt_date", "year",
         "contributor_name", "committee_name",
         list(src = c("contributor_street", "contributor_city", "contributor_state", "contributor_zipcode"),
              out = c("address_clean", "city_clean", "state_clean", "zip_clean")),
         LAYOUT, "dc_contribs", out_dir,
         extra = function(x) x[, contributor_name := full_name(contributor_first_name, contributor_middle_name,
                                                               contributor_last_name, contributor_organization_name)])
