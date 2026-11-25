# Vermont campaign contributions (TAP dataset 405), November 2026: the "Contributions and Loans" files (filing years
# 2014-2025) and filing year 2026 from the public search. See vt_common.R.
# - One row per transaction_id: the download repeats a transaction once for each version of the contributor's name or
#   address (identical otherwise): pick_one() in vt_common.R keeps the copy matching the name's latest address, else
#   the first (arbitrary).
# - Left out (as for New Hampshire): contributions with no contributor name and those named "Under Threshold - Name
#   Withheld".
#   Rscript state/vt/code/vt_contribs.R   (from the accountability_datacleaning root)
source(here::here("state", "vt", "code", "vt_common.R"))
out_dir <- dir_create(here("state", "vt", "contribs", "data", "clean"))
RENAME <- c(filing_entity_id = "filing_entity_id", filing_entity_name = "filing_entity_name",
            committee_name = "committee_name", registration_type = "registration_type",
            transaction_id = "transaction_id", transaction_type = "transaction_type",
            transaction_subtype = "transaction_subtype", goods_or_service_donated = "goods_donated_service_donated",
            contributor_type = "contributor_type", contributor_last_name = "contributor_last_name",
            contributor_first_name = "contributor_first_name", contributor_address1 = "contributor_address_line_1",
            contributor_address2 = "contributor_address_line_2", contributor_city = "contributor_address_city",
            contributor_state = "contributor_address_state", contributor_zip = "contributor_address_zip_code",
            transaction_date = "transaction_date", amount = "transaction_amount", election_type = "election_type",
            election_year = "election_year", transaction_comments = "transaction_comments", amended = "amended",
            timed_report_name = "timed_report_name", timed_report_filed_date = "timed_report_filed_date",
            report_name = "report_name", report_filed_date = "report_filed_date", filing_year = "filing_year",
            source = "source")
LAYOUT <- c(names(RENAME), "contributor_name", "recipient_name", "na_flag", "dupe_flag", "year",
            "address_clean", "city_clean", "state_clean", "zip_clean")
x <- read_vt(here("state", "vt", "data", "parsed", "vt_receipts.csv"), RENAME)
x <- pick_one(x, c("contributor_last_name", "contributor_first_name"), c("contributor_address1", "contributor_city", "contributor_zip"), "transaction_date")
drop <- is.na(x$contributor_last_name) | str_squish(x$contributor_last_name) == "Under Threshold - Name Withheld"
cat("left out (no name / withheld):", sum(is.na(x$contributor_last_name)), "/", sum(drop) - sum(is.na(x$contributor_last_name)), "\n")
print(x[drop, .N, keyby = .(source, transaction_subtype)])
x <- x[!drop]
x[, contributor_name := fifelse(is.na(contributor_first_name) | contributor_first_name == contributor_last_name,
                                contributor_last_name, paste0(contributor_last_name, ", ", contributor_first_name))]
x[, recipient_name := fcoalesce(committee_name, filing_entity_name)]
print(x[, .N, keyby = .(source, filing_year)])
build_vt(x, "transaction_date", "amount", "contributor_name", "recipient_name",
         c("contributor_address1", "contributor_address2", "contributor_city", "contributor_state", "contributor_zip"),
         LAYOUT, "vt_contribs", out_dir)
