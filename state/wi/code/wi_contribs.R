# Wisconsin campaign contributions -- rebuild from Sunshine, November 2026 (replaces wi_contribs_2008-20230604.csv,
# whose source, CFIS, is retired). Rscript state/wi/code/wi_contribs.R <raw dir>, from the repo root.
# Output: state/wi/contribs/data/clean/wi_contribs_<first year>-2022.csv and wi_contribs_2023-<this year>.csv.
#
# - Source and reading: see wi_common.R.
# - Rows: Transaction Type "Contribution" (received by a registrant: contributor -> payee = the registrant) and
#   "Conduit Contribution" (a conduit's own report: contributor = the conduit, payee = the individual, final_recipient =
#   the committee). The receiving committee reports the same money as a Contribution with Category "Conduit
#   Contribution" and the conduit as related_entity, so conduit money appears twice; both are kept, told apart by
#   transaction_type.
# - Layout: the 61 source columns in snake case (id, date, amount, ..., registrant_id -- the zero-padded old CFIS
#   ethcfid --, ..., reports), then na_flag, dupe_flag, year, and address/city/state/ZIP clean columns for the
#   contributor and the payee. date as YYYY-MM-DD, amount as a number; everything else as published.
# - Compared with the CFIS build: no employer name/address, no first/last name split (one contributor_name), no
#   filing period column (reports holds report names; empty on many migrated rows), no 72-hour report or segregated
#   fund columns. New: contributor and payee entity IDs and types, payee (registrant) address, registrant type and
#   party, related entity, final recipient, office/district/branch, ballot event.
# - All rows kept. na_flag: date, amount, contributor_name or payee_name missing. dupe_flag: every copy of a row
#   identical on all columns but id. year = year(date).
library(here)
here::i_am("state/wi/code/wi_contribs.R")
source(here("state", "wi", "code", "wi_common.R"))
raw <- commandArgs(TRUE)[1]
out_dir <- dir_create(here("state", "wi", "contribs", "data", "clean"))
build_wi(raw, c("Contribution", "Conduit Contribution"), "wi_contribs", out_dir)
