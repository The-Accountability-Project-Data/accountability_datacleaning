# New Mexico campaign expenditures (TAP dataset 394), November 2026: every expenditure in the CFIS yearly files
# (2020-2026), plus the 2021 build's rows from the earlier CFIS (through the June 2020 reports) that do not match a
# new row. Expenditures with no payee name are kept (na_flag). See nm_common.R.
#   Rscript state/nm/code/nm_expends.R   (from the accountability_datacleaning root)
source(here::here("state", "nm", "code", "nm_common.R"))
build_nm(new = here("state", "nm", "data", "parsed", "nm_expends.csv"), old = "nm_expends_2000-20210817.csv",
         id = "expenditure_id", date = "expenditure_date", amount = "expenditure_amount", year = "expenditure_year",
         name = c("payee_last_name", "payee_first_name", "payee_middle_name"),
         addr = c("payee_address_1", "payee_address_2", "payee_city", "payee_state", "payee_zip_code"),
         drop_noname = FALSE, stem = "nm_expends", out_dir = dir_create(here("state", "nm", "expends", "data", "clean")))
