# Oregon campaign contributions -- update 2026-11-06. One new file after the three 2018 files
# (OR_contributions_2002_2010.csv, _2011_2014.csv, _20150101-20180715.csv (named _2015_2018.csv until 2026-11-06); transaction dates through 2018-07-15):
#   OR_contributions_20180716-20261104.csv  ORESTAR transactions dated 2018-07-16 to 2026-11-04, current versions only, sub
#                                   types Cash Contribution, In-Kind Contribution and Return or Refund of Contribution
#                                   (the three in the 2018 files); the 2018 files' 44 columns in their order, then
#                                   country and foreign_postal_code.
#   Rscript state/or/contribs/code/or_contribs_2026.R [input csv] from the repo root
# input: the CSV written by orestar-scraper's combine.py (default: the one .csv in state/or/contribs/data/raw/).
# Output goes to state/or/contribs/data/clean/.
#
# Input: orestar-scraper's combine.py over the filed-all-versions store (ORESTAR's public transaction search,
# exported by filed date 2018-07-16 to 2026-11-04 with all versions, retrieved 2026-11-04 to 2026-11-06), run with
# --tran-dates 2018-07-16 2026-11-04. combine.py keeps the last filed version of each transaction (same Original Id)
# and leaves out transactions whose last version is deleted or expired.
#
# Values are written as published. The export has no Agent Name column: agent_name is blank. Tran Status is
# "Original" or "Amended" (the 2018 files have O and A). The file is written in windows-1252, the dataset's encoding;
# characters windows-1252 has no code for are written as "?".
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(fs); library(here)
})
here::i_am("state/or/contribs/code/or_contribs_2026.R")
comma <- function(x) format(x, big.mark = ",")

src_csv <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(src_csv)) {
  src_csv <- dir_ls(here("state", "or", "contribs", "data", "raw"), glob = "*.csv")
  stopifnot(length(src_csv) == 1)
}
out_dir <- dir_create(here("state", "or", "contribs", "data", "clean"))
out_csv <- path(out_dir, "OR_contributions_20180716-20261104.csv")

# ORESTAR export column -> 2018 file column, in the 2018 files' order (agent_name has no export column)
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
subtypes <- c("Cash Contribution", "In-Kind Contribution", "Return or Refund of Contribution")

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
          all(or$contributor_payee != ""), all(or$filer != ""), all(or$filer_id != ""))
message("contributions: ", comma(nrow(or)), "; by sub type:")
print(count(or, subtype, sort = TRUE))
print(table(year = format(tran_date, "%Y")))

# windows-1252: replace characters it cannot encode, write UTF-8, then convert the file
unenc <- 0
or <- mutate(or, across(everything(), function(v) {
  w <- iconv(v, "UTF-8", "windows-1252", sub = "?")
  stopifnot(!anyNA(w))
  r <- iconv(w, "windows-1252", "UTF-8")
  unenc <<- unenc + sum(r != v)
  r
}))
message("values with a character not in windows-1252: ", unenc)
tmp <- path(out_dir, "OR_contributions_20180716-20261104.utf8.csv")
write_csv(or, tmp, na = "")
stopifnot(system2("iconv", c("-f", "UTF-8", "-t", "WINDOWS-1252", shQuote(tmp)), stdout = out_csv) == 0)
file_delete(tmp)
message("wrote ", out_csv, ": ", comma(nrow(or)), " rows, ", ncol(or), " columns, ",
        comma(file_size(out_csv)), " bytes")
