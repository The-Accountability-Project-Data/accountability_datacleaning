# DC campaign expenditures -- full rebuild from the DC Office of Campaign Finance e-filing search, November 2026
# (replaces dc_expends_20030101-20211230.csv and dc_expends_20030101-20230504.csv, from the same search). From the
# repo root: python3 state/dc/code/reparse.py <raw dir>; Rscript state/dc/code/dc_expends.R
# Output: state/dc/expends/data/clean/dc_expends_2003-2026.csv.
#
# - Source and reading: see dc_common.R.
# - Rows: every expenditure, all filer types, as published (including about 1,400 $0.00 rows with no payee, from
#   committees' empty reports).
# - Layout: the earlier build's 21 columns in its order: expendee_name (the paying committee, "Committee Name"),
#   payee_first_name, payee_middle_name, payee_last_name, payee_organization_name, number_and_street, city, state,
#   zip, purpose_of_expenditure, further_explanation, payment_date, amount, payee_name ("first middle last", or the
#   organization name), na_flag, dupe_flag, payment_year, address_clean, city_clean, state_clean, zip_clean.
# - All rows kept. na_flag: payment_date, amount, payee_name or expendee_name missing. dupe_flag: every copy of a
#   row identical on all source columns. payment_year = year(payment_date).
library(here)
here::i_am("state/dc/code/dc_expends.R")
source(here("state", "dc", "code", "dc_common.R"))
SRC <- c("Committee Name", "Payee First Name", "Payee Middle Name", "Payee Last Name", "Payee Organization Name",
         "Payee Street", "Payee City", "Payee State", "Payee ZipCode", "Purpose of Expenditure", "Further Explanation",
         "Payment Date", "Amount")
NAMES <- c("expendee_name", "payee_first_name", "payee_middle_name", "payee_last_name", "payee_organization_name",
           "number_and_street", "city", "state", "zip", "purpose_of_expenditure", "further_explanation",
           "payment_date", "amount")
LAYOUT <- c(NAMES, "payee_name", "na_flag", "dupe_flag", "payment_year", "address_clean", "city_clean", "state_clean", "zip_clean")
out_dir <- dir_create(here("state", "dc", "expends", "data", "clean"))
build_dc(here("state", "dc", "data", "parsed", "dc_expenditures.csv"), SRC, NAMES, "payment_date", "payment_year",
         "payee_name", "expendee_name",
         list(src = c("number_and_street", "city", "state", "zip"),
              out = c("address_clean", "city_clean", "state_clean", "zip_clean")),
         LAYOUT, "dc_expends", out_dir,
         extra = function(x) x[, payee_name := full_name(payee_first_name, payee_middle_name, payee_last_name,
                                                         payee_organization_name)])
