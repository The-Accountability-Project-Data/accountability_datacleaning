# New York City contracts -- rebuild 2026-10-14.
# Follows state/ny/nyc/contracts/docs/nyc_contracts_diary.Rmd (2020), with these changes:
#   - reads the saved export data/raw/Recent_Contract_Awards_2026-10-14.csv (downloaded once with a
#     browser user agent from https://data.cityofnewyork.us/api/views/qyyg-4tf5/rows.csv?accessType=DOWNLOAD);
#   - campfin from CRAN (1.0.11) instead of GitHub; pacman not used; col_types use the cleaned names (start_date,
#     not StartDate) and col_date_mdy (col_date_usa is deprecated);
#   - the diary's remove_empty("cols") made the layout depend on the data; the
#     output is pinned to the 2020 file's 28 columns, in order (source-only columns are dropped and listed below);
#   - notices already in the 2020 file keep its address fields (the source lost city/state/ZIP; see below);
#   - otherwise the same steps: address split into addr/state/zip, agency_state "NY", na_flag, dupe check, year from
#     start_date.
# Output: data/clean/nyc_contracts_2003-2026.csv (UTF-8).
#   Rscript state/ny/nyc/contracts/code/nyc_contracts.R from the repo root; put the export in
#   state/ny/nyc/contracts/data/raw/ and the 2020 nyc_contracts_clean.csv in state/ny/nyc/contracts/data/old/.
suppressPackageStartupMessages({
  library(dplyr); library(stringr); library(readr); library(vroom); library(lubridate); library(janitor)
  library(campfin); library(fs); library(glue); library(here)
})
here::i_am("state/ny/nyc/contracts/code/nyc_contracts.R")
base <- here("state", "ny", "nyc", "contracts", "data")
raw_path <- path(base, "raw", "Recent_Contract_Awards_2026-10-14.csv")
clean_dir <- dir_create(path(base, "clean"))

old_cols <- c("request_id", "start_date", "end_date", "agency_name", "agency_state", "type_of_notice_description",
              "category_description", "short_title", "selection_method_description", "section_name",
              "special_case_reason_description", "pin", "address_to_request", "contact_name", "contact_phone",
              "contract_amount", "additional_description1", "other_info1", "vendor_name", "vendor_address", "printout1",
              "printout2", "document_links", "addr", "state", "zip", "na_flag", "year")

nyc <- vroom(
  file = raw_path, .name_repair = make_clean_names, escape_double = FALSE, escape_backslash = FALSE,
  na = c("", "NA", "......"), progress = FALSE,
  # col_types are matched to the repaired names in current vroom (the diary used StartDate etc.)
  col_types = cols(.default = col_character(), start_date = col_date_mdy(), end_date = col_date_mdy(),
                   contract_amount = col_double())
)
message("read ", nrow(nyc), " rows, ", ncol(nyc), " columns")
stopifnot(all(nyc$type_of_notice_description == "Award"))

# address -> addr / state / zip (diary)
nyc <- mutate(nyc, addr = str_to_upper(vendor_address))
nyc$addr <- str_remove_all(nyc$addr, "\\.(?=\\S)")
nyc <- mutate(nyc, zip = normal_zip(str_extract(addr, "\\d+(?:-\\d{4})?$")))
nyc$addr <- str_trim(str_remove(nyc$addr, "[:punct:]?\\s?\\d+(?:-\\d{4})?$"))
rx_abbs <- valid_state
names(rx_abbs) <- glue("{valid_name}$")
nyc$addr <- str_replace_all(nyc$addr, rx_abbs)
nyc <- mutate(nyc, state = str_extract(addr, "(?<=\\W)[:upper:]{2}$"))
nyc$addr <- str_remove(nyc$addr, "[:punct:]?\\s[:upper:]{2}$")
nyc$addr <- nyc$addr %>% str_normal(punct = FALSE) %>% abbrev_full(usps_street)

nyc <- mutate(nyc, agency_state = "NY", .after = agency_name)
nyc <- flag_na(nyc, agency_name, vendor_name, start_date, contract_amount)
message("na_flag: ", sum(nyc$na_flag))
n_dupes <- sum(duplicated(nyc) | duplicated(nyc, fromLast = TRUE))
message("duplicated rows: ", n_dupes)
stopifnot(n_dupes == 0)    # the 2020 layout has no dupe_flag column
nyc <- mutate(nyc, year = year(start_date))

# Address regression at the source (found 2026-10-14): for many notices the city now publishes only the street
# ("1411 Broadway"), sometimes a different one, without city/state/ZIP (state found on 91% of the 2020 file's rows,
# 55% of today's export; 3% for 2025-26). Notices that were
# in the 2020 file keep its address fields (vendor_address, addr, state, zip): the address as originally published.
old_path <- path(base, "old", "nyc_contracts_clean.csv")   # the 2020 file, csv/nyc_contracts_clean.csv
old <- read_csv(old_path, col_types = cols(.default = col_character()), na = "", progress = FALSE) %>%
  select(request_id, o_vendor_address = vendor_address, o_addr = addr, o_state = state, o_zip = zip) %>%
  filter(!is.na(o_vendor_address))
nyc <- left_join(nyc, old, by = "request_id")
keep_old <- !is.na(nyc$o_vendor_address)
message("address fields kept from the 2020 file: ", sum(keep_old), " notices (",
        sum(keep_old & is.na(nyc$state) & !is.na(nyc$o_state)), " regain a state, ",
        sum(keep_old & coalesce(nyc$vendor_address != nyc$o_vendor_address, FALSE)), " differ from today's text)")
nyc <- mutate(nyc,
  vendor_address = if_else(keep_old, o_vendor_address, vendor_address), addr = if_else(keep_old, o_addr, addr),
  state = if_else(keep_old, o_state, state), zip = if_else(keep_old, o_zip, zip)) %>%
  select(-starts_with("o_"))

dropped <- setdiff(names(nyc), old_cols)
for (c in dropped) message("dropped source column ", c, ": ", sum(!is.na(nyc[[c]])), " non-empty")
for (c in setdiff(old_cols, names(nyc))) nyc[[c]] <- NA
nyc <- nyc[old_cols]

out <- path(clean_dir, sprintf("nyc_contracts_%d-%d.csv", min(nyc$year, na.rm = TRUE), max(nyc$year, na.rm = TRUE)))
write_csv(nyc, out, na = "")
message("wrote ", out, ": ", nrow(nyc), " rows")
