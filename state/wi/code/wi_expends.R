# Wisconsin campaign expenditures -- rebuild from Sunshine, November 2026 (replaces wi_expends_clean.csv, whose
# source, CFIS, is retired). Rscript state/wi/code/wi_expends.R <raw dir>, from the repo root.
# Output: state/wi/expends/data/clean/wi_expends_<first year>-2022.csv and wi_expends_2023-<this year>.csv.
#
# - Source and reading: see wi_common.R.
# - Rows: Transaction Type "Disbursement": contributor = the paying registrant, payee = who was paid; final_recipient
#   for in-kind and pass-through payments, related_entity for independent expenditures (the candidate).
# - Layout: the 61 source columns in snake case, then na_flag, dupe_flag, year, and address/city/state/ZIP clean
#   columns for the contributor (payer) and the payee. date as YYYY-MM-DD, amount as a number; everything else as
#   published (transaction_purpose = the old expense_purpose, transaction_category = expense_category,
#   support_stance = support_oppose, communication_date as published, MM/DD/YYYY).
# - Compared with the CFIS build: no filing fee / recount / recall / referendum name columns (category and
#   related_entity instead), no 72-hour report or segregated fund columns. New: payer and payee entity IDs, types and
#   addresses (the payer's address is new), registrant type and party, final recipient, office/district, ballot event.
# - All rows kept. na_flag: date, amount, contributor_name (payer) or payee_name missing. dupe_flag: every copy of a
#   row identical on all columns but id. year = year(date).
library(here)
here::i_am("state/wi/code/wi_expends.R")
source(here("state", "wi", "code", "wi_common.R"))
raw <- commandArgs(TRUE)[1]
out_dir <- dir_create(here("state", "wi", "expends", "data", "clean"))
build_wi(raw, "Disbursement", "wi_expends", out_dir)
