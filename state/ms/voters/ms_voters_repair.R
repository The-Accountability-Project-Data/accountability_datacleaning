#!/usr/bin/env Rscript

# Mississippi voters: repair of the indexed file (dataset 219, csv/ms_voters_clean.csv, uploaded 2023-01-02)
# Claude, Oct 2026, for the datacleaning_agents effort; see datacleaning_agents/datasets/219-ms-voters.md.
#
# The indexed file has the right values in the right columns, but every record ends with a field holding a line
# break (WSD) plus an extra blank column whose name is itself a line break, so each record spans two lines. Cause:
# the raw extract's header ends with a trailing comma (59 names, 58 fields per row) and has CRLF line endings,
# and it was read without quoting (needed: the state typed apostrophes as double quotes, e.g. O"KEEFE, which
# make a normal CSV reader merge lines).
#
# This rebuilds the file from the raw extract, read the same way, with the indexed file's column names:
#   * 58 columns: the trailing empty header column is dropped; WSD is blank (it is blank in every raw row)
#   * EFFECTIVE_REGN_DATE is named REGN_DATE, as in the indexed file (the mapping uses these names)
#   * fix 1 (user, 2026-10-07): whitespace squished in every column (district codes were space-padded)
#   * fix 2 (user, 2026-10-07): a double quote inside a value becomes an apostrophe (O"KEEFE -> O'KEEFE)
#   * nothing else changes; values are as delivered (dates stay M/D/YYYY)
# Checks: row count equals the raw line count. ms_voters_compare.py then checks, streaming, that every value
# matches the indexed file once the same fixes are applied to it.
#
# Rscript --vanilla ms_voters_repair.R <raw extract csv> <indexed clean csv> <output csv>

suppressPackageStartupMessages(library(readr))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(stringr))
suppressPackageStartupMessages(library(cli))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  cli_alert_danger("Usage: ms_voters_repair.R <raw csv> <indexed clean csv> <output csv>"); quit(save = "no", status = 1)
}
raw_path <- args[1]; old_path <- args[2]; out_path <- args[3]

# raw: no quoting, everything character; the header's trailing comma adds an empty 59th name
raw_names <- strsplit(sub("[\r\n]+$", "", read_lines(raw_path, n_max = 1)), ",")[[1]]
raw_names <- raw_names[nzchar(raw_names)]
stopifnot(length(raw_names) == 58, raw_names[58] == "WSD")
msv <- read_delim(
  raw_path, delim = ",", quote = "", escape_backslash = FALSE, escape_double = FALSE, skip = 1,
  col_names = raw_names, col_types = cols(.default = col_character()), na = character(),
  trim_ws = FALSE, progress = FALSE
)
msv <- mutate(msv, WSD = str_remove(WSD, "\r$"))   # CRLF: the last field carries the \r
n_raw <- length(count.fields(raw_path, sep = "\x01", quote = "", blank.lines.skip = FALSE)) - 1
cli_alert_info("raw: {format(nrow(msv), big.mark = ',')} rows x {ncol(msv)} cols (lines after header: {format(n_raw, big.mark = ',')})")
stopifnot(nrow(msv) == n_raw, all(msv$WSD == ""))

# the indexed file's names (its last, line-break-named column is dropped)
old_names <- names(read_csv(old_path, n_max = 0, col_types = cols(.default = col_character())))
old_names <- old_names[seq_len(58)]
stopifnot(old_names[22] == "REGN_DATE", raw_names[22] == "EFFECTIVE_REGN_DATE")
names(msv) <- old_names

# fixes
n_quote <- sum(vapply(msv, function(x) sum(str_detect(x, fixed('"'))), 0))
n_pad <- sum(vapply(msv, function(x) sum(x != str_squish(x)), 0))
msv <- mutate(msv, across(everything(), ~ str_replace_all(str_squish(.x), fixed('"'), "'")))
cli_alert_info("fixed: {n_quote} values with a double quote, {format(n_pad, big.mark = ',')} values with extra whitespace")

write_csv(msv, out_path, na = "")
cli_alert_success("wrote {out_path}: {format(nrow(msv), big.mark = ',')} rows x {ncol(msv)} cols")
