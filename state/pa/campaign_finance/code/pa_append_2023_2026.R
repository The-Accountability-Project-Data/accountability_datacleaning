# Pennsylvania contributions and expenditures: 2023-2026 append, 2026-11-10. The 2000-2022 files built in 2023,
# which have street addresses, are kept; this script builds the 2023-2026 reports from the Department of State's
# yearly full exports, which have no street addresses.
#   Rscript state/pa/campaign_finance/code/pa_append_2023_2026.R from the repo root; outputs go to
#   state/pa/campaign_finance/data/clean/.
# Source: https://www.pa.gov/agencies/dos/resources/voting-and-elections-resources/campaign-finance-data, 2023.zip -
# 2026.zip (fetch.sh, retrieved 2026-11-10), extracted to state/pa/campaign_finance/data/raw/x/. Layout in readme-cf-data.txt. Lines are ASCII or Windows-1252.
# Rows: every contribution and expense of the filer reports (filer file rows) of the 2023-2026 exports, except those of
# a report superseded by a later report of the same filer, year (EYEAR) and cycle (CYCLE): the latest SubmittedDate
# (then highest CampaignFinanceID) is kept. Output columns are those of the current files (pa_contribs_clean.csv,
# pa_expends_clean.csv); the filer columns come from the row's own report.
# ADDRESS1 and ADDRESS2 are blank in the source, so the address columns are blank.

suppressPackageStartupMessages({library(readr); library(dplyr); library(stringr); library(campfin); library(here)})
here::i_am("state/pa/campaign_finance/code/pa_append_2023_2026.R")
x_dir <- here("state", "pa", "campaign_finance", "data", "raw", "x")
out_dir <- here("state", "pa", "campaign_finance", "data", "clean")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
years <- 2023:2026
enc <- locale(encoding = "windows-1252")

rd <- function(kind) {
  bind_rows(lapply(years, function(y) {
    read_csv(file.path(x_dir, sprintf("%s_%d.txt", kind, y)), col_types = cols(.default = col_character()),
             locale = enc, na = character(), trim_ws = TRUE, progress = FALSE)
  }))
}

fil <- rd("filer")
names(fil)[1] <- "CampaignFinanceID"
fil <- fil %>% mutate(.id = as.numeric(CampaignFinanceID))
latest <- fil %>% group_by(FILERID, EYEAR, CYCLE) %>%
  arrange(desc(SubmittedDate), desc(.id), .by_group = TRUE) %>% slice(1) %>% ungroup() %>%
  select(CampaignFinanceID, EYEAR)
message("reports ", nrow(fil), "; kept (latest per filer-year-cycle) ", nrow(latest))
# report 432861 is listed in both the 2025 and 2026 filer files (different EYEAR), so reports are keyed by ID and EYEAR
fil <- fil %>% semi_join(latest, by = c("CampaignFinanceID", "EYEAR")) %>%
  transmute(CampaignFinanceID, EYEAR, fil_reportid = CampaignFinanceID, fil_timestamp = SubmittedDate, fil_cycle = CYCLE,
            ammend = AMMEND, terminate = TERMINATE, fil_type = FILERTYPE, filer = FILERNAME, office = OFFICE,
            district = DISTRICT, party = PARTY, fil_addr1 = ADDRESS1, fil_addr2 = ADDRESS2, fil_city = CITY,
            fil_state = STATE, fil_zip = ZIPCODE, county = COUNTY, fil_phone = PHONE, beginning = BEGINNING,
            monetary = MONETARY, inkind = INKIND)

ymd8 <- function(d) {
  out <- ifelse(str_detect(d, "^\\d{8}$"), paste(substr(d, 1, 4), substr(d, 5, 6), substr(d, 7, 8), sep = "-"), NA)
  as.Date(out)
}
clean_city <- function(x) normal_city(x, abbs = usps_city, states = c("PA", "DC"), na = invalid_city, na_rep = TRUE)
clean_zip <- function(x) normal_zip(x, na_rep = TRUE)
clean_addr <- function(x) normal_address(x, abbs = usps_street, na_rep = TRUE)

# contributions
con <- rd("contrib")
n_all <- nrow(con)
con <- con %>% inner_join(fil, by = c("CampaignFinanceID", "EYEAR"), relationship = "many-to-one")
message("contributions ", n_all, "; in kept reports ", nrow(con))
con <- con %>% transmute(
  filerid = FilerID, eyear = EYEAR, cycle = CYCLE, section = Section, contributor = CONTRIBUTOR,
  con_addr1 = ADDRESS1, con_addr2 = ADDRESS2, con_city = CITY, con_state = STATE, con_zip = ZIPCODE,
  occupation = OCCUPATION, ename = ENAME, date = ymd8(CONTDATE1), amount = as.numeric(CONTAMT1),
  fil_type, filer, office, district, party, fil_addr1, fil_addr2, fil_city, fil_state, fil_zip, county, fil_phone)
con <- con %>% mutate(
  na_flag = is.na(contributor) | contributor == "" | is.na(date) | is.na(amount) | is.na(filer) | filer == "",
  dupe_flag = duplicated(.) | duplicated(., fromLast = TRUE),
  year = as.integer(format(date, "%Y")),
  con_addr_clean = clean_addr(str_squish(paste(con_addr1, con_addr2))),
  fil_addr_clean = clean_addr(str_squish(paste(fil_addr1, fil_addr2))),
  con_city_clean = clean_city(con_city), fil_city_clean = clean_city(fil_city),
  con_zip_clean = clean_zip(con_zip), fil_zip_clean = clean_zip(fil_zip))
write_csv(con, file.path(out_dir, "pa_contribs_2023-2026.csv"), na = "")
message("wrote contributions ", nrow(con), "; years ", paste(names(table(con$year)), table(con$year), collapse = " "))

# expenditures
exp <- rd("expense")
n_all <- nrow(exp)
exp <- exp %>% inner_join(fil, by = c("CampaignFinanceID", "EYEAR"), relationship = "many-to-one")
message("expenses ", n_all, "; in kept reports ", nrow(exp))
exp <- exp %>% transmute(
  filerid = FILERID, eyear = EYEAR, exp_cycle = CYCLE, expname = EXPNAME, exp_addr1 = ADDRESS1,
  exp_addr2 = ADDRESS2, exp_city = CITY, exp_state = STATE, exp_zip = ZIPCODE, expdate = ymd8(EXPDATE),
  expamt = as.numeric(EXPAMT), expdesc = EXPDESC, exp_reportid = CampaignFinanceID, exp_timestamp = SubmittedDate,
  fil_reportid, fil_timestamp, fil_cycle, ammend, terminate, fil_type, filer, office, district, party, fil_addr1,
  fil_addr2, fil_city, fil_state, fil_zip, county, fil_phone, beginning, monetary, inkind)
exp <- exp %>% mutate(
  na_flag = is.na(expname) | expname == "" | is.na(expdate) | is.na(expamt) | is.na(filer) | filer == "",
  year = as.integer(format(expdate, "%Y")),
  exp_addr_norm = clean_addr(str_squish(paste(exp_addr1, exp_addr2))),
  fil_addr_norm = clean_addr(str_squish(paste(fil_addr1, fil_addr2))),
  exp_zip_clean = clean_zip(exp_zip), fil_zip_clean = clean_zip(fil_zip),
  fil_city_clean = clean_city(fil_city), exp_city_clean = clean_city(exp_city))
write_csv(exp, file.path(out_dir, "pa_expends_2023-2026.csv"), na = "")
message("wrote expenses ", nrow(exp), "; years ", paste(names(table(exp$year)), table(exp$year), collapse = " "))
