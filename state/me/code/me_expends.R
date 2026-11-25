# Maine campaign expenditures (TAP dataset 141), November 2026: every transaction paid out (expenditures, independent
# expenditures, debt and loan payments, returned contributions, returned MCEA funds, debts) in the Maine Campaign
# Finance Disclosure downloads, 2018-2026, plus the 2020 build's rows (all dated before 2018). Rows with no payee name
# are kept (na_flag). Earlier rows: expenditure id, org_id, expender, committee office and district, type, date,
# amount, explanation, purpose, payee name (first middle last), address, city, state and ZIP code become the new
# columns; committee type, report and filed date are kept as earlier_*. See me_common.R.
#   Rscript state/me/code/me_expends.R   (from the accountability_datacleaning root)
source(here::here("state", "me", "code", "me_common.R"))
x <- read_new(TYPES$paid)
o <- fread(path(OLD, "me_expends_clean.csv"), colClasses = "character", na.strings = "", encoding = "UTF-8"); blank_na(o)
cat("earlier:", nrow(o), "rows;", o[as.IDate(expenditure_date) < CUT, .N], "dated before", format(CUT), "kept\n")
o <- o[as.IDate(expenditure_date) < CUT]
o <- o[, .(transaction_id = expenditure_id, filer_id = org_id, filer_name = expender_name, filer_office = committee_office,
           filer_district = committee_district, transaction_type = expenditure_type,
           transaction_date = as.IDate(expenditure_date), amount = as.numeric(expenditure_amount), description = explanation,
           contact_name = na_blank(str_squish(paste(fcoalesce(first_name, ""), fcoalesce(middle_name, ""), fcoalesce(last_name, "")))),
           contact_street_address_1 = address1, contact_street_address_2 = address2, contact_city = city_raw,
           contact_state = state, contact_zip = zip, purpose,
           earlier_committee_type = committee_type, earlier_report = report_name, earlier_filed_date = filed_date,
           dupe_flag = dupe_flag == "TRUE", address_clean = address_norm, city_clean, state_clean = state_norm, zip_clean = zip_norm)]
build_me(x, o, drop_noname = FALSE, earlier = c("earlier_committee_type", "earlier_report", "earlier_filed_date"),
         stem = "me_expends", out_dir = dir_create(here("state", "me", "expends", "data", "clean")))
