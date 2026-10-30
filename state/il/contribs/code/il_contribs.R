# Copied 2026-10-30 from the datacleaning_agents repo (ec2/il/il_contribs.R): the script that built the October 2026 file.
# It ran on the project's EC2 build box and reads/writes paths there (e.g. ~/tx/raw, ~/il/); point them at your
# own raw and output folders before running it from here.
#
# Illinois campaign contributions (dataset 400): rebuild from the SBE bulk Receipts.txt, split by year.
# Follows accountability_datacleaning state/il/contribs/docs/il_contribs_diary.Rmd (2023): read the tab-delimited file,
# snake_case names, join the recipient committee from Committees.txt (normalized address/ZIP/state/city as cmte_*),
# na_flag (rcv_date, last_only_name, amount, cmte_name), dupe_flag (identical on every column except id, within the
# same rcv_date), rcv_year, campfin address/ZIP/state normalization and city norm/swap/refine.
# Differences (user, 2026-10-12): records superseded by an amendment (archived = TRUE) are DROPPED; the 2023 hand fixes
# for broken lines are replaced by ~/il/repair.sh (continuation lines joined; lines with a stray tab set aside); output
# is one file per rcv_year: il_contribs_<year>.csv (before 1994 -> il_contribs_pre1994.csv). Same 41 columns and order
# as the 2023 file (il_contribs_clean_new.csv), which dataset 400's index mapping reads.
#   Rscript il_contribs.R
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(lubridate); library(janitor); library(tidyr)
  library(campfin); library(refinr); library(fs); library(cli); library(openssl)
})
out_dir <- dir_create(path_expand("~/il/clean_contribs")); dir_walk(out_dir, file_delete)
layout <- c("id","committee_id","filed_doc_id","e_trans_id","last_only_name","first_name","rcv_date","amount",
  "aggregate_amount","loan_amount","occupation","employer","address1","address2","city","state","zip","d2part",
  "description","vendor_last_only_name","vendor_first_name","vendor_address1","vendor_address2","vendor_city",
  "vendor_state","vendor_zip","archived","country","redaction_requested","cmte_name","cmte_address","cmte_city",
  "cmte_state","cmte_zip","na_flag","dupe_flag","rcv_year","address_clean","city_clean","state_clean","zip_clean")

# committees, normalized as in the diary
committees <- read_delim(path_expand("~/il/raw/Committees.txt"), delim = "\t", quote = "", escape_backslash = FALSE,
  escape_double = FALSE, trim_ws = TRUE, locale = locale(encoding = "windows-1252"), col_types = cols(.default = col_character(), ID = col_integer()),
  progress = FALSE) %>% clean_names(case = "snake") %>%
  select(id, name, starts_with("address"), city, state, zip) %>%
  unite(col = address, starts_with("address"), sep = " ", remove = TRUE, na.rm = TRUE) %>%
  mutate(address = normal_address(address = address, abbs = usps_street, na_rep = TRUE),
         zip = normal_zip(zip = zip, na_rep = TRUE, na = ""))
il_zip <- zipcodes$zip[zipcodes$state == "IL"]
committees$state[committees$state %in% c("L", "O:") & committees$zip %in% il_zip] <- "IL"
committees$state <- normal_state(state = committees$state, valid = valid_state)
committees <- committees %>%
  mutate(city_norm = normal_city(city = city, abbs = usps_city, states = c("IL", "DC", "ILLINOIS"),
                                 na = invalid_city, na_rep = TRUE)) %>%
  left_join(zipcodes, by = c("state", "zip"), suffix = c("", "_match")) %>%
  mutate(match_abb = is_abbrev(city_norm, city_match), match_dist = str_dist(city_norm, city_match),
         city = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)) %>%
  select(id, name, address, city, state, zip) %>% distinct(id, .keep_all = TRUE) %>%
  rename_with(~paste0("cmte_", .), -id)
cli_alert_success("{nrow(committees)} committees")

ilc <- read_delim(path_expand("~/il/work/Receipts-fixed.txt"), delim = "\t", quote = "", escape_backslash = FALSE,
  escape_double = FALSE, trim_ws = TRUE, locale = locale(encoding = "windows-1252"), progress = FALSE,
  col_types = cols(.default = col_character(), ID = col_integer(), CommitteeID = col_integer(),
                   FiledDocID = col_integer(), RcvDate = col_datetime(), Amount = col_double(),
                   AggregateAmount = col_double(), LoanAmount = col_double(), Archived = col_logical(),
                   RedactionRequested = col_logical()))
ilc <- clean_names(ilc, case = "snake")
n_read <- nrow(ilc)
ilc <- filter(ilc, !coalesce(archived, FALSE))
cli_alert_success("read {format(n_read, big.mark=',')} records; dropped {format(n_read - nrow(ilc), big.mark=',')} superseded (archived) -> {format(nrow(ilc), big.mark=',')}")

ilc <- left_join(ilc, committees, by = c("committee_id" = "id"))
ilc <- flag_na(ilc, rcv_date, last_only_name, amount, cmte_name)
cli_alert_success("na_flag: {sum(ilc$na_flag)}")
key <- do.call(paste, c(lapply(select(ilc, -id), function(v) coalesce(as.character(v), "")), sep = "\x1f"))
h <- substr(as.character(md5(key)), 1, 20); rm(key); invisible(gc())
ilc$dupe_flag <- duplicated(h) | duplicated(h, fromLast = TRUE); rm(h); invisible(gc())
cli_alert_success("dupe_flag: {sum(ilc$dupe_flag)} ({round(100 * mean(ilc$dupe_flag), 2)}%)")
ilc <- mutate(ilc, rcv_year = year(rcv_date))

# donor address, ZIP, state, city (normalizing distinct values, as the diary does)
norm_addr <- ilc %>% distinct(address1, address2) %>%
  unite(col = address_full, starts_with("address"), sep = " ", remove = FALSE, na.rm = TRUE) %>%
  mutate(address_clean = normal_address(address = address_full, abbs = usps_street, na_rep = TRUE)) %>%
  select(-address_full)
ilc <- left_join(ilc, norm_addr, by = c("address1", "address2")); rm(norm_addr)
ilc <- mutate(ilc, zip_clean = normal_zip(zip = zip, na_rep = TRUE))
st <- ilc %>% distinct(state) %>% mutate(state_clean = normal_state(state = state, abbreviate = TRUE, na_rep = TRUE, valid = valid_state))
ilc <- left_join(ilc, st, by = "state")
norm_city <- ilc %>% distinct(city, state_clean, zip_clean) %>%
  mutate(city_norm = normal_city(city = city, abbs = usps_city, states = c("IL", "DC", "ILLINOIS"),
                                 na = invalid_city, na_rep = TRUE)) %>%
  left_join(zipcodes, by = c("state_clean" = "state", "zip_clean" = "zip"), suffix = c("", "_match")) %>%
  mutate(match_abb = is_abbrev(city_norm, city_match), match_dist = str_dist(city_norm, city_match),
         city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)) %>%
  select(city, state_clean, zip_clean, city_swap) %>% distinct(city, state_clean, zip_clean, .keep_all = TRUE)
ilc <- left_join(ilc, norm_city, by = c("city", "state_clean", "zip_clean")); rm(norm_city)
good_refine <- ilc %>% select(state_clean, zip_clean, city_swap) %>%
  mutate(city_refine = city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)) %>%
  filter(city_refine != city_swap) %>%
  inner_join(zipcodes, by = c("city_refine" = "city", "state_clean" = "state", "zip_clean" = "zip")) %>%
  distinct(state_clean, zip_clean, city_swap, .keep_all = TRUE)
ilc <- ilc %>% left_join(good_refine, by = c("state_clean", "zip_clean", "city_swap")) %>%
  mutate(city_clean = coalesce(city_refine, city_swap)) %>% select(-city_swap, -city_refine)
stopifnot(setequal(names(ilc), layout))
ilc <- select(ilc, all_of(layout))
bucket <- ifelse(is.na(ilc$rcv_year), "undated", ifelse(ilc$rcv_year < 1994, "pre1994", as.character(ilc$rcv_year)))
for (b in sort(unique(bucket))) {
  write_csv(ilc[bucket == b, ], path(out_dir, sprintf("il_contribs_%s.csv", b)), na = "")
}
print(table(bucket))
cli_alert_success("wrote {format(nrow(ilc), big.mark=',')} rows in {length(unique(bucket))} files")
