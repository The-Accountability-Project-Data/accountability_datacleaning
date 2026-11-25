# Massachusetts campaign expenditures -- rebuild 2002-2026, November 2026 (replaces ma_expends_clean.csv).
#   python3 state/ma/code/reparse.py state/ma, then Rscript state/ma/code/ma_expends.R, from the repo root.
#   Raw: state/ma/data/raw/<YYYY>/ (unzipped ocpf-<YYYY>-reports.zip). Output: state/ma/expends/data/clean/.
#
# See state/ma/expends/docs/ma_expends_diary.Rmd ("Update: November 2026"):
# - Source: OCPF yearly files 2002-2026, retrieved 2026-11-15 (current report versions only; amended versions
#   excluded by OCPF). The Access database the 2019 file was built from is no longer published.
# - Record types: those the earlier file carried (301-304, 307-312, 314-316, 318-320, 331, 332, 351, 352, 354, 951)
#   plus 305 (refunded credit card contribution) and 952 (subvendor payment, stand-alone).
# - New column layout from the yearly files, named like the contributions file (the earlier file's Access columns
#   are not in the source): payee fields from the item (last = Name, first = First_Name, address, city, state, zip),
#   description (purpose), cpf_id = the payee's CPF ID (Related_CPF_ID); filer fields from the report: payer_any =
#   OCPF_Full_Name, filer_cpf_id = CPF_ID, comm_name = OCPF_Comm_Name, office, district, rpt_type, rpt_year.
#   cand_name = the report's OCPF candidate first + last name (blank for committees without a candidate); 32 -> 33 columns;
#   exp_type = record type name; payee_any = first + last; na_flag on payee_any, payer_any, date, amount; dupe_flag on
#   every column but id; year = year(date); clean address/city/state/ZIP as the contributions file.
library(here)
here::i_am("state/ma/code/ma_expends.R")
source(here("state", "ma", "code", "ma_common.R"))
TYPES <- c(301:305, 307:312, 314:316, 318:320, 331, 332, 351, 352, 354, 951, 952)
COLS <- c("id", "rpt_id", "record_type_id", "date", "amount", "last", "first", "address", "city", "state", "zip",
          "description", "cpf_id", "clarified_name", "clarified_purpose", "is_supported", "exp_type", "payer_any",
          "filer_cpf_id", "comm_name", "cand_name", "office", "district", "rpt_type", "rpt_year", "payee_any", "na_flag",
          "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")

mae <- select_items(TYPES) %>%
  clean_names("snake") %>%
  rename(id = item_id, rpt_id = report_id, last = name, first = first_name, address = street_address,
         cpf_id = related_cpf_id) %>%
  left_join(rename(rec_types, exp_type = type_name), by = "record_type_id", relationship = "many-to-one") %>%
  select(-source_year, -occupation, -employer, -principal_officer, -tender_type_id, -is_previous_year_receipt)
n0 <- nrow(mae)
mae <- mae %>%
  left_join(select(reports, rpt_id = Report_ID, payer_any = OCPF_Full_Name, filer_cpf_id = CPF_ID,
                   comm_name = OCPF_Comm_Name, cand_first = OCPF_Candidate_First_Name,
                   cand_last = OCPF_Candidate_Last_Name, office = OCPF_Office, district = OCPF_District,
                   rpt_type = Report_Type_Description, rpt_year = Report_Year),
            by = "rpt_id", relationship = "many-to-one") %>%
  unite(cand_name, cand_first, cand_last, sep = " ", na.rm = TRUE) %>%
  mutate(cand_name = na_if(cand_name, "")) %>%
  unite(payee_any, first, last, sep = " ", na.rm = TRUE, remove = FALSE) %>%
  mutate(payee_any = na_if(payee_any, "")) %>%
  flag_na(payee_any, payer_any, date, amount)
stopifnot(nrow(mae) == n0)
cat("na_flag:", sum(mae$na_flag), "\n")
mae <- flag_dupes(mae, -id)
cat("dupe_flag:", sum(mae$dupe_flag), "\n")
mae <- mae %>%
  mutate(year = year(date)) %>%
  add_geo()
print(count(mae, year), n = 80)
print(count(mae, record_type_id, exp_type), n = 40)
write_out(mae, COLS, "expends", "ma_expends_2002-2026.csv")
