# New Hampshire campaign expenditures (TAP dataset 191), November 2026: every transaction in the CFS "Download Data"
# Expenditures files, filing years 2016-2026 (expenditures, independent expenditures, returned expenditures).
# The payee address is one field ("street, line 2, city, ST ZIP"); it is split into payee_address_sep,
# payee_city_sep, payee_state_sep and payee_zip_sep where it has that form (else the whole value goes in
# payee_address_sep). See nh_common.R.
#   Rscript state/nh/code/nh_expends.R   (from the accountability_datacleaning root)
source(here::here("state", "nh", "code", "nh_common.R"))
out_dir <- dir_create(here("state", "nh", "expends", "data", "clean"))
RENAME <- c(filing_entity_id = "filing_entity_id", filing_entity_name = "filing_entity_name",
            filing_entity_type = "filing_entity_type", transaction_type = "transaction_type",
            transaction_sub_type = "transaction_sub_type", payee_type = "payee_worker_creditor_loan_source_type",
            payee_name = "payee_worker_creditor_loan_source_name", payee_address = "payee_worker_creditor_loan_source_address",
            amount = "transaction_amount", transaction_date = "transactiondate", election_type = "election_type",
            description = "transaction_description", timed_report = "timed_report", filing_year = "filing_year")
SEP <- c("payee_address_sep", "payee_city_sep", "payee_state_sep", "payee_zip_sep")
LAYOUT <- c(names(RENAME), SEP, "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")
x <- read_nh(here("state", "nh", "data", "parsed", "nh_expenditures.csv"), RENAME)
a <- str_squish(x$payee_address)
m <- str_match(a, "^(.*?),\\s*([^,]+?),?\\s+([A-Za-z]{2})\\.?,?\\s+(\\d{4,5}(?:-?\\d{4})?)-?$")
ok <- !is.na(m[, 1])
cat("payee addresses:", sum(!is.na(a)), " split:", sum(ok), "\n")
street <- str_squish(gsub("(,\\s*)+$", "", gsub("(,\\s*){2,}", ", ", m[, 2])))
x[, payee_address_sep := fifelse(ok, na_blank(street), a)]
x[, payee_city_sep := fifelse(ok, m[, 3], NA_character_)]
x[, payee_state_sep := fifelse(ok, toupper(m[, 4]), NA_character_)]
x[, payee_zip_sep := fifelse(ok, m[, 5], NA_character_)]
x[, payee_address2_none := NA_character_]
build_nh(x, "transaction_date", "amount", "payee_name", "filing_entity_name",
         c("payee_address_sep", "payee_address2_none", "payee_city_sep", "payee_state_sep", "payee_zip_sep"),
         LAYOUT, "nh_expends", out_dir)
