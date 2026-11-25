# Maine campaign contributions (TAP dataset 349), November 2026: every transaction received (contributions, loans,
# loan forgiveness, MCEA payments, returned expenditures, bank interest, transfers) in the Maine Campaign Finance
# Disclosure downloads, 2018-2026, plus the 2020 build's rows dated before 2018. Rows with no contributor name are
# left out, except public funding (MCEA) payments, which are kept with na_flag. Earlier rows: id, org_id, the committee or candidate, office, district, type, date, amount, election
# type, description, source type, contributor, address, city, state, ZIP code, occupation and employer become the
# new columns; committee type, report and filed date are kept as earlier_*. See me_common.R.
#   Rscript state/me/code/me_contribs.R   (from the accountability_datacleaning root)
source(here::here("state", "me", "code", "me_common.R"))
x <- read_new(TYPES$received)
o <- fread(path(OLD, "me_contribs_clean.csv"), colClasses = "character", na.strings = "", encoding = "UTF-8"); blank_na(o)
cat("earlier:", nrow(o), "rows;", o[as.IDate(date) < CUT, .N], "dated before", format(CUT), "kept\n")
o <- o[as.IDate(date) < CUT]
o <- o[, .(transaction_id = id, filer_id = org_id, filer_name = fcoalesce(committee, candidate), filer_office = office,
           filer_district = district, transaction_type = type, transaction_date = as.IDate(date), amount = as.numeric(amount),
           election = election_type, description, contact_type = source_type, contact_name = contributor,
           contact_street_address_1 = address1, contact_street_address_2 = address2, contact_city = city,
           contact_state = state, contact_zip = zip, occupation, employer_name = employer,
           earlier_committee_type = committee_type, earlier_report = report, earlier_filed_date = filed_date,
           dupe_flag = dupe_flag == "TRUE", address_clean, city_clean, state_clean, zip_clean)]
build_me(x, o, drop_noname = TRUE, earlier = c("earlier_committee_type", "earlier_report", "earlier_filed_date"),
         stem = "me_contribs", out_dir = dir_create(here("state", "me", "contribs", "data", "clean")))
