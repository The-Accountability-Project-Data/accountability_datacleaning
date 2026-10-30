# Copied 2026-10-30 from the datacleaning_agents repo (ec2/il/il_expends.R): the script that built the October 2026 file.
# It ran on the project's EC2 build box and reads/writes paths there (e.g. ~/tx/raw, ~/il/); point them at your
# own raw and output folders before running it from here.
#
# Illinois campaign expenditures (dataset 308): rebuild from the SBE bulk Expenditures.txt, one file.
# The 2020 file (il_expends_clean.csv, DataFile 1029) came from the SBE search export; dataset 308's index mapping reads
# comm_id, vendor, committee, date, year, amount, address_clean, city_clean, state_clean, zip_clean. This keeps the 2020
# file's 28 columns in order, filled from the bulk file + FiledDocs.txt (report) + Committees.txt (committee name):
#   file (= "Expenditures.txt"), comm_id, vendor, date, amount, address1, address2, city, state, zip,
#   type (D2Part: 6 Transfer Out, 7 Loan Made, 8 Expenditure, 9 Independent Expenditure), purpose,
#   beneficiary (not in the bulk file: blank), candidate, office_district, support (Supporting/Opposing),
#   doc_name, election (election type + year), report_begin, report_end, rpt_rcvd_date, committee, dupe_flag, year,
#   address_clean, zip_clean, state_clean, city_clean
# and appends the bulk-only fields: id, filed_doc_id, e_trans_id, last_only_name, first_name, aggregate_amount, d2part,
# country, redaction_requested, na_flag. Superseded records (archived = TRUE) are DROPPED (user, 2026-10-12).
#   Rscript il_expends.R
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(lubridate); library(janitor); library(tidyr)
  library(campfin); library(refinr); library(fs); library(cli); library(openssl)
})
out_dir <- dir_create(path_expand("~/il/clean_expends")); dir_walk(out_dir, file_delete)
rd <- function(f, types) read_delim(path_expand(f), delim = "\t", quote = "", escape_backslash = FALSE,
  escape_double = FALSE, trim_ws = TRUE, progress = FALSE, col_types = types,
  locale = locale(encoding = "windows-1252"))  # SBE bulk files are windows-1252, not UTF-8
cmte <- rd("~/il/raw/Committees.txt", cols(.default = col_character(), ID = col_integer())) %>%
  clean_names(case = "snake") %>% select(id, committee = name) %>% distinct(id, .keep_all = TRUE)
docs <- rd(path_expand("~/il/raw/FiledDocs.txt"), cols(.default = col_character(), ID = col_integer())) %>%
  clean_names(case = "snake") %>%
  transmute(id, doc_name, election = str_squish(paste(coalesce(election_type, ""), coalesce(election_year, ""))),
            report_begin = as.Date(parse_date_time(rpt_pd_beg_date, c("mdY HMS", "mdY", "Ymd HMS", "Ymd"), quiet = TRUE)),
            report_end = as.Date(parse_date_time(rpt_pd_end_date, c("mdY HMS", "mdY", "Ymd HMS", "Ymd"), quiet = TRUE)),
            rpt_rcvd_date = as.Date(parse_date_time(rcvd_date_time, c("mdY HMS", "mdY IMS p", "Ymd HMS", "mdY", "Ymd"), quiet = TRUE))) %>%
  mutate(election = na_if(election, "")) %>% distinct(id, .keep_all = TRUE)
ile <- rd("~/il/work/Expenditures-fixed.txt",
  cols(.default = col_character(), ID = col_integer(), CommitteeID = col_integer(), FiledDocID = col_integer(),
       ExpendedDate = col_datetime(), Amount = col_double(), AggregateAmount = col_double(),
       Archived = col_logical(), RedactionRequested = col_logical())) %>% clean_names(case = "snake")
n_read <- nrow(ile)
ile <- filter(ile, !coalesce(archived, FALSE))
cli_alert_success("read {format(n_read, big.mark=',')}; dropped {format(n_read - nrow(ile), big.mark=',')} superseded -> {format(nrow(ile), big.mark=',')}")
d2 <- c("6" = "Transfer Out", "7" = "Loan Made", "8" = "Expenditure", "9" = "Independent Expenditure")
ile <- ile %>%
  left_join(cmte, by = c("committee_id" = "id")) %>%
  left_join(docs, by = c("filed_doc_id" = "id")) %>%
  mutate(file = "Expenditures.txt", comm_id = committee_id,
         vendor = if_else(is.na(first_name) | first_name == "", last_only_name, paste(first_name, last_only_name)),
         date = as.Date(expended_date), type = unname(d2[substr(d2part, 1, 1)]), beneficiary = NA_character_,
         candidate = candidate_name, office_district = office,
         support = case_when(toupper(supporting) %in% c("TRUE", "Y", "1") ~ "Supporting",
                             toupper(opposing) %in% c("TRUE", "Y", "1") ~ "Opposing", TRUE ~ NA_character_))
ile <- flag_na(ile, date, vendor, amount, committee)
cli_alert_success("na_flag: {sum(ile$na_flag)}")
key <- do.call(paste, c(lapply(select(ile, -id), function(v) coalesce(as.character(v), "")), sep = "\x1f"))
h <- substr(as.character(md5(key)), 1, 20); rm(key); invisible(gc())
ile$dupe_flag <- duplicated(h) | duplicated(h, fromLast = TRUE); rm(h); invisible(gc())
cli_alert_success("dupe_flag: {sum(ile$dupe_flag)} ({round(100 * mean(ile$dupe_flag), 2)}%)")
ile <- mutate(ile, year = year(date))
norm_addr <- ile %>% distinct(address1, address2) %>%
  unite(col = address_full, starts_with("address"), sep = " ", remove = FALSE, na.rm = TRUE) %>%
  mutate(address_clean = normal_address(address = address_full, abbs = usps_street, na_rep = TRUE)) %>% select(-address_full)
ile <- left_join(ile, norm_addr, by = c("address1", "address2"))
ile <- mutate(ile, zip_clean = normal_zip(zip = zip, na_rep = TRUE))
st <- ile %>% distinct(state) %>% mutate(state_clean = normal_state(state = state, abbreviate = TRUE, na_rep = TRUE, valid = valid_state))
ile <- left_join(ile, st, by = "state")
norm_city <- ile %>% distinct(city, state_clean, zip_clean) %>%
  mutate(city_norm = normal_city(city = city, abbs = usps_city, states = c("IL", "DC", "ILLINOIS"), na = invalid_city, na_rep = TRUE)) %>%
  left_join(zipcodes, by = c("state_clean" = "state", "zip_clean" = "zip"), suffix = c("", "_match")) %>%
  mutate(match_abb = is_abbrev(city_norm, city_match), match_dist = str_dist(city_norm, city_match),
         city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)) %>%
  select(city, state_clean, zip_clean, city_swap) %>% distinct(city, state_clean, zip_clean, .keep_all = TRUE)
ile <- left_join(ile, norm_city, by = c("city", "state_clean", "zip_clean"))
good_refine <- ile %>% select(state_clean, zip_clean, city_swap) %>%
  mutate(city_refine = city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)) %>%
  filter(city_refine != city_swap) %>%
  inner_join(zipcodes, by = c("city_refine" = "city", "state_clean" = "state", "zip_clean" = "zip")) %>%
  distinct(state_clean, zip_clean, city_swap, .keep_all = TRUE)
ile <- ile %>% left_join(good_refine, by = c("state_clean", "zip_clean", "city_swap")) %>%
  mutate(city_clean = coalesce(city_refine, city_swap))
old28 <- c("file","comm_id","vendor","date","amount","address1","address2","city","state","zip","type","purpose",
  "beneficiary","candidate","office_district","support","doc_name","election","report_begin","report_end",
  "rpt_rcvd_date","committee","dupe_flag","year","address_clean","zip_clean","state_clean","city_clean")
extra <- c("id","filed_doc_id","e_trans_id","last_only_name","first_name","aggregate_amount","d2part","country",
  "redaction_requested","na_flag")
ile <- select(ile, all_of(c(old28, extra)))
out <- path(out_dir, "il_expends_clean.csv"); write_csv(ile, out, na = "")
cli_alert_success("wrote {format(nrow(ile), big.mark=',')} rows, {file_size(out)}; years {paste(range(ile$year, na.rm=TRUE), collapse='-')}")
print(count(ile, year), n = 60); print(count(ile, type))
