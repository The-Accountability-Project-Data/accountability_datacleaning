# Copied 2026-10-30 from the datacleaning_agents repo (datasets/369-417-mn-campaign-finance/mn_common.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Shared reader for the Minnesota CFB downloads (369/417 rebuild, Oct 2026). Sourced by mn_contribs.R / mn_expends.R.
#
# The CFB CSVs are RFC-style (fields with commas/quotes/CR-LF are quoted, a quote inside is doubled ""), EXCEPT that
# in a few dozen values the board's export wrote a quote as backslash-quote (\"), e.g.
#   "Signed Copy of \"Turning Point\" by Jimmy Carter"     "Ehrhardt, George \\\"Mac\\\""     "200-4\\"x6\\" ..."
# while other values legitimately END with a literal backslash: "...Campaign Website\",2026,...
# readr/fread mis-split those records (5 contribution records swallowed others). Fix, kept minimal: a backslash-quote
# that is NOT followed by a comma or a line break is an escaped quote inside the value, so its quote is doubled
# (\" -> \""). The backslash itself is kept, so the value keeps the published characters (\"). A backslash-quote
# followed by a comma/line break is a literal trailing backslash plus the closing quote, left alone. Nothing else is
# changed. The result must give exactly the record count Python's csv module finds (reparse.py) with the right number
# of fields in every record, and every value that has no backslash must equal Python's parse.
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(lubridate); library(janitor); library(campfin)
  library(fs); library(here); library(glue)
})
comma <- function(x) format(x, big.mark = ",", scientific = FALSE)
base    <- here("work", "369-417-mn-campaign-finance")
raw_dir <- path(base, "raw", "2026-10-28")
out_dir <- dir_create(path(base, "out"))

read_cfb <- function(f, col_types, expected_records) {
  txt <- read_file(f, locale = locale(encoding = "UTF-8"))
  n_fix <- str_count(txt, '\\\\"(?![,\\r\\n])')
  txt <- str_replace_all(txt, '\\\\"(?![,\\r\\n])', '\\\\""')
  df <- read_delim(I(txt), delim = ",", col_types = col_types, na = "", trim_ws = FALSE, quote = '"', escape_double = TRUE,
                 escape_backslash = FALSE, progress = FALSE, lazy = FALSE)
  pr <- problems(df)
  cat(basename(f), ": backslash-quotes doubled", n_fix, "; records", comma(nrow(df)), "; parse problems", nrow(pr), "\n")
  if (nrow(pr)) print(pr, n = 50)
  stopifnot(nrow(df) == expected_records, nrow(pr) == 0)
  # cross-check with Python's csv parse (parsed/ copy written by reparse.py): all values without a backslash equal
  py <- read_csv(path(base, "parsed", basename(f)), col_types = cols(.default = col_character()), na = "",
                 trim_ws = FALSE, progress = FALSE, lazy = FALSE)
  stopifnot(nrow(py) == nrow(df), identical(names(py), names(df)))
  chr <- df %>% mutate(across(everything(), as.character))
  bad <- 0; checked <- 0
  for (cn in names(df)) {
    a <- py[[cn]]; b <- chr[[cn]]
    if (!is.character(df[[cn]])) next   # typed columns are checked by parsing (no problems) above
    keep <- !(str_detect(coalesce(a, ""), fixed("\\")) | str_detect(coalesce(b, ""), fixed("\\")))
    checked <- checked + sum(keep)
    bad <- bad + sum(!(a[keep] == b[keep] | (is.na(a[keep]) & is.na(b[keep]))), na.rm = TRUE) +
      sum(xor(is.na(a[keep]), is.na(b[keep])))
  }
  cat("  python cross-check: character values compared", comma(checked), "; differing", bad, "\n")
  stopifnot(bad == 0)
  df
}

read_old <- function(f) {
  read_csv(f, col_types = cols(.default = col_character()), na = "", trim_ws = FALSE, progress = FALSE, lazy = FALSE)
}
