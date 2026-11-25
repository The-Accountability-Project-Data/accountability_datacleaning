# New Hampshire campaign contributions (TAP dataset 401), November 2026: every receipt in the CFS "Download Data"
# Receipts files, filing years 2016-2026 (contributions, in-kind, unitemized, loans received, interest, returned
# receipts). See nh_common.R.
# Left out: receipts with no contributor name (unitemized) and receipts named
# "Under threshold - Name Withheld" (small contributions listed without the donor).
#   Rscript state/nh/code/nh_contribs.R   (from the accountability_datacleaning root)
source(here::here("state", "nh", "code", "nh_common.R"))
out_dir <- dir_create(here("state", "nh", "contribs", "data", "clean"))
RENAME <- c(filing_entity_id = "filing_entity_id", candidate_name = "candidate_name", committee_name = "committee_name",
            committee_subtype = "committee_subtype", transaction_type = "transaction_type",
            transaction_sub_type = "transaction_sub_type", election_period = "election_period",
            election_year = "election_year", receipt_date = "date_of_receipt", amount = "amount_of_receipt",
            contributor_type = "contributor_type", contributor_name = "contributor_name",
            contributor_address1 = "contributor_address_line_1", contributor_address2 = "contributor_address_line_2",
            contributor_city = "contributor_city", contributor_state = "contributor_state",
            contributor_zip = "contributor_zip_code", contributor_occupation = "contributor_occupation",
            contributor_employer = "contributor_employer",
            contributor_place_of_business = "contributor_principle_place_of_business", description = "description",
            timed_report = "timed_report", filing_year = "filing_year")
LAYOUT <- c(names(RENAME), "recipient_name", "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")
x <- read_nh(here("state", "nh", "data", "parsed", "nh_receipts.csv"), RENAME)
drop <- is.na(x$contributor_name) | str_squish(x$contributor_name) == "Under threshold - Name Withheld"
cat("left out:", sum(drop), "\n"); print(x[drop, .N, keyby = .(no_name = is.na(contributor_name), transaction_sub_type)])
x <- x[!drop]
x[, recipient_name := fcoalesce(committee_name, candidate_name)]   # the committee, or the candidate filing without one
build_nh(x, "receipt_date", "amount", "contributor_name", c("committee_name", "candidate_name"),
         c("contributor_address1", "contributor_address2", "contributor_city", "contributor_state", "contributor_zip"),
         LAYOUT, "nh_contribs", out_dir)
