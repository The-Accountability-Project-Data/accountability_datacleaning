# Oregon campaign expenditures -- new dataset, built 2026-11-06. One file:
#   OR_expenditures_2018_2026.csv  ORESTAR transactions dated 2018-07-16 to 2026-11-04, current versions only, of
#                                  ORESTAR's Expenditure type: sub types Cash Expenditure, Personal Expenditure for
#                                  Reimbursement, Account Payable and Loan Payment (Non-Exempt); the same 46 columns
#                                  as the Oregon contributions file OR_contributions_2018_2026.csv.
#   Rscript state/or/expends/code/or_expends_2026.R [input csv] from the repo root
# input: the CSV written by orestar-scraper's combine.py (default: the one .csv in state/or/expends/data/raw/).
# Output goes to state/or/expends/data/clean/.
#
# Input: orestar-scraper's combine.py over the filed-all-versions store (ORESTAR's public transaction search,
# exported by filed date 2018-07-16 to 2026-11-04 with all versions, retrieved 2026-11-04 to 2026-11-06), run with
# --tran-dates 2018-07-16 2026-11-04. combine.py keeps the last filed version of each transaction (same Original Id)
# and leaves out transactions whose last version is deleted or expired. The sub types of the Expenditure type are
# from the ORESTAR User's Manual: Transaction Filing, p. 32.
#
# Values are written as published. The export has no Agent Name column: agent_name is blank. UTF-8.
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(fs); library(here)
})
here::i_am("state/or/expends/code/or_expends_2026.R")
comma <- function(x) format(x, big.mark = ",")

src_csv <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(src_csv)) {
  src_csv <- dir_ls(here("state", "or", "expends", "data", "raw"), glob = "*.csv")
  stopifnot(length(src_csv) == 1)
}
out_dir <- dir_create(here("state", "or", "expends", "data", "clean"))
out_csv <- path(out_dir, "OR_expenditures_2018_2026.csv")

# ORESTAR export column -> contributions file column, in its order (agent_name has no export column)
cols <- c(
  tran_id = "Tran Id", original_id = "Original Id", tran_date = "Tran Date", tran_status = "Tran Status",
  filer = "Filer", contributor_payee = "Contributor/Payee", agent_name = NA,
  payer_personal_expend = "Payer of Personal Expenditure", subtype = "Sub Type", amount = "Amount",
  aggregate_amount = "Aggregate Amount", contributor_payee_committee_id = "Contributor/Payee Committee ID",
  filer_id = "Filer Id", attest_by_name = "Attest By Name", attest_date = "Attest Date",
  review_by_name = "Review By Name", review_date = "Review Date", due_date = "Due Date",
  occptn_ltr_date = "Occptn Ltr Date", pymt_sched_txt = "Pymt Sched Txt", purp_desc = "Purp Desc",
  intrst_rate = "Intrst Rate", check_nbr = "Check Nbr", tran_stsfd_ind = "Tran Stsfd Ind",
  filed_by_name = "Filed By Name", filed_date = "Filed Date", addrbook_agent_name = "Addr book Agent Name",
  book_type = "Book Type", title_txt = "Title Txt", occptn_txt = "Occptn Txt", emp_name = "Emp Name",
  emp_city = "Emp City", emp_state = "Emp State", employ_ind = "Employ Ind", self_employ_ind = "Self Employ Ind",
  addr_line1 = "Addr Line1", addr_line2 = "Addr Line2", city = "City", state = "State", zip = "Zip",
  zip_plus_four = "Zip Plus Four", county = "County", purpose_codes = "Purpose Codes", exp_date = "Exp Date",
  country = "Country", foreign_postal_code = "Foreign Postal Code"
)
subtypes <- c("Cash Expenditure", "Personal Expenditure for Reimbursement", "Account Payable",
              "Loan Payment (Non-Exempt)")

src <- read_csv(src_csv, col_types = cols(.default = col_character()), na = character(), trim_ws = FALSE,
                progress = FALSE)
stopifnot(nrow(problems(src)) == 0, ncol(src) == 45, setequal(names(src), na.omit(cols)))
message("combined transactions: ", comma(nrow(src)))

or <- filter(src, `Sub Type` %in% subtypes)
or <- bind_cols(lapply(names(cols), function(k) {
  tibble(!!k := if (is.na(cols[[k]])) "" else or[[cols[[k]]]])
}))
tran_date <- as.Date(or$tran_date, "%m/%d/%Y")
stopifnot(!anyNA(tran_date), min(tran_date) >= as.Date("2018-07-16"), max(tran_date) <= as.Date("2026-11-04"),
          !anyDuplicated(or$tran_id), !anyDuplicated(or$original_id),
          all(or$filer != ""), all(or$filer_id != ""))
message("blank contributor_payee (payee): ", sum(or$contributor_payee == ""))
message("expenditures: ", comma(nrow(or)), "; by sub type:")
print(count(or, subtype, sort = TRUE))
print(table(year = format(tran_date, "%Y")))

write_csv(or, out_csv, na = "")
message("wrote ", out_csv, ": ", comma(nrow(or)), " rows, ", ncol(or), " columns, ",
        comma(file_size(out_csv)), " bytes")
