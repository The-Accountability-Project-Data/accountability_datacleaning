# Vermont campaign expenditures (TAP dataset 185), November 2026: the "Expenditures" files (filing years 2014-2025)
# and the expenditures in the public search that are not in them (filed in 2026). See vt_common.R.
# - One row per transaction_id: the download repeats a transaction once for each version of the payee's name or
#   address (identical otherwise): pick_one() in vt_common.R keeps the copy matching the name's latest address, else
#   the first (arbitrary).
#   Rscript state/vt/code/vt_expends.R   (from the accountability_datacleaning root)
source(here::here("state", "vt", "code", "vt_common.R"))
out_dir <- dir_create(here("state", "vt", "expends", "data", "clean"))
RENAME <- c(filing_entity_id = "filing_entity_id", filing_entity_name = "filing_entity_name",
            committee_name = "committee_name", registration_type = "registration_type",
            transaction_id = "transaction_id", transaction_type = "transaction_type",
            transaction_subtype = "transaction_subtype", goods_or_service_donated = "goods_donated_service_donated",
            purpose = "purpose", other_purpose_comments = "other_purpose_comments", payee_type = "payee_type",
            payee_last_name = "payee_last_name", payee_first_name = "payee_first_name",
            payee_address1 = "payee_address_line_1", payee_address2 = "payee_address_line_2",
            payee_city = "payee_address_city", payee_state = "payee_address_state", payee_zip = "payee_address_zip_code",
            transaction_date = "transaction_date", amount = "transaction_amount", election_type = "election_type",
            election_year = "election_year", transaction_comments = "transaction_comments", amended = "amended",
            timed_report_name = "timed_report_name", timed_report_filed_date = "timed_report_filed_date",
            report_name = "report_name", report_filed_date = "report_filed_date", filing_year = "filing_year",
            source = "source")
LAYOUT <- c(names(RENAME), "payee_name", "spender_name", "na_flag", "dupe_flag", "year",
            "address_clean", "city_clean", "state_clean", "zip_clean")
x <- read_vt(here("state", "vt", "data", "parsed", "vt_expenditures.csv"), RENAME)
x <- pick_one(x, c("payee_last_name", "payee_first_name"), c("payee_address1", "payee_city", "payee_zip"), "transaction_date")
x[, payee_name := fifelse(is.na(payee_first_name) | payee_first_name == payee_last_name,
                          payee_last_name, paste0(payee_last_name, ", ", payee_first_name))]
x[, spender_name := fcoalesce(committee_name, filing_entity_name)]
print(x[, .N, keyby = .(source, filing_year)])
build_vt(x, "transaction_date", "amount", "payee_name", "spender_name",
         c("payee_address1", "payee_address2", "payee_city", "payee_state", "payee_zip"),
         LAYOUT, "vt_expends", out_dir)
