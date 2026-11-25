# Massachusetts campaign contributions -- rebuild 2002-2026, November 2026 (replaces ma_contribs_clean.csv and
# ma_contribs_clean_2020-2023.csv with one file).
#   python3 state/ma/code/reparse.py state/ma, then Rscript state/ma/code/ma_contribs.R, from the repo root.
#   Raw: state/ma/data/raw/<YYYY>/ (unzipped ocpf-<YYYY>-reports.zip). Output: state/ma/contribs/data/clean/.
#
# Follows state/ma/contribs/docs/ma_contribs_diary_2023.Rmd ("Update: November 2026"):
# - Source: OCPF yearly files 2002-2026, retrieved 2026-11-15 (current report versions only; amended versions
#   excluded by OCPF). The Access database the 2020 file was built from is no longer published.
# - Record types: those either earlier file carried: 201-207, 210, 211, 220, 230, 303, 319, 401-403.
# - Columns: the 32 columns of ma_contribs_clean_2020-2023.csv, in its order. cont_type = record type name,
#   tender = tender type name (as the diary: "0" and blank kept), recip_any = the report's OCPF_Full_Name, rpt_type =
#   Report_Type_Description, contrib_any = first + last, na_flag on contrib_any, recip_any, date, amount; dupe_flag on
#   every column but id; year = year(date).
# - Added November 2026 (after recip_any): recip_cpf_id = the report's CPF_ID (the receiving committee; not
#   Filer_CPF_ID, which is the bank's ID on bank reports), comm_name = OCPF_Comm_Name, cand_name = the report's
#   OCPF candidate first + last name (blank for committees without a candidate). 32 -> 35 columns.
# - City refine: kept only where the refined city/state/ZIP is valid for that row's state and ZIP.
library(here)
here::i_am("state/ma/code/ma_contribs.R")
source(here("state", "ma", "code", "ma_common.R"))
TYPES <- c(201:207, 210, 211, 220, 230, 303, 319, 401:403)
COLS <- c("id", "rpt_id", "record_type_id", "date", "amount", "last", "first", "address", "city", "state", "zip",
          "description", "cpf_id", "occupation", "employer", "officer", "tender", "clarified_name",
          "clarified_purpose", "is_supported", "is_previous_year_receipt", "cont_type", "recip_any", "recip_cpf_id", "comm_name", "cand_name", "rpt_type",
          "contrib_any", "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")

mac <- select_items(TYPES) %>%
  clean_names("snake") %>%
  rename(id = item_id, rpt_id = report_id, last = name, first = first_name, address = street_address,
         cpf_id = related_cpf_id, officer = principal_officer, tender = tender_type_id) %>%
  left_join(rename(rec_types, cont_type = type_name), by = "record_type_id", relationship = "many-to-one") %>%
  left_join(tender_types, by = c("tender" = "tender_id"), relationship = "many-to-one") %>%
  mutate(tender = coalesce(tender_name, tender)) %>%
  select(-tender_name, -source_year)
n0 <- nrow(mac)
mac <- mac %>%
  left_join(select(reports, rpt_id = Report_ID, recip_any = OCPF_Full_Name, recip_cpf_id = CPF_ID,
                   comm_name = OCPF_Comm_Name, cand_first = OCPF_Candidate_First_Name,
                   cand_last = OCPF_Candidate_Last_Name, rpt_type = Report_Type_Description),
            by = "rpt_id", relationship = "many-to-one") %>%
  unite(cand_name, cand_first, cand_last, sep = " ", na.rm = TRUE) %>%
  mutate(cand_name = na_if(cand_name, "")) %>%
  unite(contrib_any, first, last, sep = " ", na.rm = TRUE, remove = FALSE) %>%
  mutate(contrib_any = na_if(contrib_any, "")) %>%
  flag_na(contrib_any, recip_any, date, amount)
stopifnot(nrow(mac) == n0)
cat("na_flag:", sum(mac$na_flag), "\n")
mac <- flag_dupes(mac, -id)
cat("dupe_flag:", sum(mac$dupe_flag), "\n")
mac <- mac %>%
  mutate(year = year(date)) %>%
  add_geo()
print(count(mac, year), n = 80)
print(count(mac, record_type_id, cont_type), n = 40)
write_out(mac, COLS, "contribs", "ma_contribs_2002-2026.csv")
