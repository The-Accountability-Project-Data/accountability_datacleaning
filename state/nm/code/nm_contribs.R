# New Mexico campaign contributions (TAP dataset 392), November 2026: every contribution and loan in the CFIS yearly
# files (2020-2026), plus the 2021 build's rows from the earlier CFIS (through the June 2020 reports) that do not
# match a new row. Contributions with no contributor name are left out. See nm_common.R.
#   Rscript state/nm/code/nm_contribs.R   (from the accountability_datacleaning root)
source(here::here("state", "nm", "code", "nm_common.R"))
build_nm(new = here("state", "nm", "data", "parsed", "nm_contribs.csv"), old = "nm_contribs_2000-20210817.csv",
         id = "transaction_id", date = "transaction_date", amount = "transaction_amount", year = "transaction_year",
         name = c("last_name", "first_name", "middle_name"),
         addr = c("contributor_address_line_1", "contributor_address_line_2", "contributor_city", "contributor_state", "contributor_zip_code"),
         drop_noname = TRUE, stem = "nm_contribs", out_dir = dir_create(here("state", "nm", "contribs", "data", "clean")))
