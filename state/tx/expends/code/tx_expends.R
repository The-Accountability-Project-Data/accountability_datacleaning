# Copied 2026-10-30 from the datacleaning_agents repo (ec2/tx/tx_expends.R): the script that built the October 2026 file.
# It ran on the project's EC2 build box and reads/writes paths there (e.g. ~/tx/raw, ~/il/); point them at your
# own raw and output folders before running it from here.
#
# Texas campaign expenditures (dataset 324): full rebuild from the TEC bulk zip, same columns as the 2023 file
# (tx_expends_clean.csv, DataFile 1063), which dataset 324's index mapping reads. Follows accountability_datacleaning
# state/tx/expends/docs/tx_expends_diary.Rmd step for step: read all expend_*.csv, the diary's renames, drop the empty
# columns, Y/N flags -> logical, na_flag (payee, date, amount, filer), dupe_flag (identical on every column except
# id), year, campfin address/ZIP/state normalization and city norm/swap/refine.
# Differences: duplicates are found by hashing each row instead of duplicated() on the whole table (same result, less
# memory); output is one file, ~/tx/clean_expends/tx_expends_clean.csv.
#   Rscript tx_expends.R
suppressPackageStartupMessages({
  library(readr); library(vroom); library(dplyr); library(stringr); library(lubridate); library(janitor)
  library(campfin); library(refinr); library(fs); library(cli); library(scales); library(openssl); library(tidyr)
})
# campfin::to_logical() (used by the 2023 diary) is gone from campfin 1.0.11: Y/N (and TRUE/FALSE) -> logical
to_logical <- function(x) {
  x <- toupper(trimws(as.character(x)))
  ifelse(x %in% c("Y", "YES", "TRUE", "T"), TRUE, ifelse(x %in% c("N", "NO", "FALSE", "F"), FALSE, NA))
}
raw <- sort(dir_ls(path_expand("~/tx/raw"), regexp = "expend_\\d+\\.csv$"))
out_dir <- dir_create(path_expand("~/tx/clean_expends"))
cli_alert_info("{length(raw)} expenditure files")

txe <- vroom(file = raw, .name_repair = make_clean_names, na = c("", "NA", "N/A", "UNKNOWN"), delim = ",",
             col_names = TRUE, escape_double = TRUE, escape_backslash = FALSE, num_threads = 1, progress = FALSE,
             locale = locale(tz = "US/Central"),
             col_types = cols(.default = col_character(), receivedDt = col_date("%Y%m%d"),
                              expendDt = col_date("%Y%m%d"), expendAmount = col_double()))
n <- nrow(txe)
cli_alert_success("read {comma(n)} rows")

txe <- txe %>%
  rename_with(str_remove, everything(), "_name") %>%
  rename_with(str_remove, everything(), "_cd") %>%
  rename_with(str_remove, everything(), "_street") %>%
  rename_with(str_replace, everything(), "ident", "id") %>%
  rename(form = form_type, schedule = sched_form_type, report_id = report_info_id, received = received_dt,
         info_flag = info_only_flag, id = expend_info_id, date = expend_dt, amount = expend_amount,
         describe = expend_descr, category = expend_cat, description = expend_cat_descr,
         politics_flag = political_expend, reimburse_flag = reimburse_intended_flag,
         corp_flag = src_corp_contrib_flag, liveexp_flag = capital_livingexp_flag, payee_type = payee_persent_type,
         vendor = payee_organization, last = payee_last, suffix = payee_suffix, first = payee_first,
         prefix = payee_prefix, addr1 = payee_addr1, addr2 = payee_addr2, city = payee_city, state = payee_state,
         county = payee_county, country = payee_country, zip = payee_postal_code, region = payee_region) %>%
  select(-record_type, -payee_short, -country, -county) %>%
  mutate(across(liveexp_flag, \(x) na_out(x, c("Y", "N")))) %>%
  mutate(across(ends_with("_flag"), to_logical)) %>%
  mutate(id = as.numeric(id))

# missing values
txe <- txe %>% mutate(payee = coalesce(last, vendor)) %>% flag_na(payee, date, amount, filer) %>% select(-payee)
cli_alert_success("na_flag: {comma(sum(txe$na_flag))}")

# duplicates: identical on every column except id
key <- do.call(paste, c(lapply(select(txe, -id), function(v) coalesce(as.character(v), "")), sep = "\x1f"))
h <- substr(as.character(md5(key)), 1, 20); rm(key); invisible(gc())
txe$dupe_flag <- duplicated(h) | duplicated(h, fromLast = TRUE); rm(h); invisible(gc())
cli_alert_success("dupe_flag: {comma(sum(txe$dupe_flag))} ({percent(mean(txe$dupe_flag), 0.01)})")

# year. The diary's vroom col_types name the original camelCase columns, but .name_repair has already renamed them,
# so dates and amounts arrive as text; the diary converts them here: date -> Date, amount -> number (received stays the
# raw YYYYMMDD text, as in the 2023 file).
txe <- txe %>% mutate(date = as.Date(date, format = "%Y%m%d"), amount = parse_double(amount))
txe <- mutate(txe, year = year(date))

# address, ZIP, state
txe <- txe %>%
  unite(col = addr_full, starts_with("addr"), sep = " ", remove = FALSE, na.rm = TRUE) %>%
  mutate(addr_norm = normal_address(address = addr_full, abbs = usps_street, na_rep = TRUE)) %>%
  select(-addr_full)
txe <- mutate(txe, zip_norm = normal_zip(zip = zip, na_rep = TRUE))
txe <- mutate(txe, state_norm = normal_state(state = state, abbreviate = TRUE, na_rep = TRUE, valid = valid_state))

# city: normalize, swap, refine (refine over every row; only into valid city/state/ZIP combinations)
txe <- txe %>%
  mutate(city_norm = normal_city(city = city, abbs = usps_city, states = c("TX", "DC", "TEXAS"),
                                 na = invalid_city, na_rep = TRUE)) %>%
  rename(city_raw = city) %>%
  left_join(zipcodes, by = c("state_norm" = "state", "zip_norm" = "zip")) %>%
  rename(city_match = city) %>%
  mutate(match_abb = is_abbrev(city_norm, city_match), match_dist = str_dist(city_norm, city_match),
         city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)) %>%
  select(-city_match, -match_dist, -match_abb)
stopifnot(nrow(txe) == n)   # the zipcodes join must not add rows
good_refine <- txe %>% select(state_norm, zip_norm, city_swap) %>%
  mutate(city_refine = city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)) %>%
  filter(city_refine != city_swap) %>%
  inner_join(zipcodes, by = c("city_refine" = "city", "state_norm" = "state", "zip_norm" = "zip")) %>%
  distinct(state_norm, zip_norm, city_swap, .keep_all = TRUE)
txe <- txe %>% left_join(good_refine, by = c("state_norm", "zip_norm", "city_swap")) %>%
  mutate(city_refine = coalesce(city_refine, city_swap))

# conclude, as the diary: drop intermediates, *_norm -> *_clean, *_raw -> original name
txe <- txe %>% select(-city_norm, -city_swap, city_clean = city_refine) %>%
  rename_all(~str_replace(., "_norm", "_clean")) %>% rename_all(~str_remove(., "_raw"))
stopifnot(nrow(txe) == n)
expected <- c("form","schedule","report_id","received","info_flag","filer_id","filer_type","filer","id","date",
  "amount","describe","category","description","itemize_flag","travel_flag","politics_flag","reimburse_flag",
  "corp_flag","liveexp_flag","payee_type","vendor","last","suffix","first","prefix","addr1","addr2","city","state",
  "zip","region","credit_card_issuer","repayment_dt","na_flag","dupe_flag","year","addr_clean","zip_clean",
  "state_clean","city_clean")
if (!identical(names(txe), expected)) {
  cli_alert_warning("column names/order differ from the 2023 file; reordering to match")
  stopifnot(setequal(names(txe), expected))
  txe <- select(txe, all_of(expected))
}
out <- path(out_dir, "tx_expends_clean.csv")
write_csv(txe, out, na = "")
cli_alert_success("wrote {comma(nrow(txe))} rows, {file_size(out)}; years {paste(range(txe$year, na.rm = TRUE), collapse = '-')}")
print(count(txe, year), n = 60)
