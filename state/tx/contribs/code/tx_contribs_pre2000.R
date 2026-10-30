# Copied 2026-10-30 from the datacleaning_agents repo (ec2/tx/tx_contribs_pre2000.R). Run after tx_contribs.R, on its
# output folder (on the EC2 build box that was ~/tx/clean); pass another folder as the first argument.
#
# Texas campaign contributions (dataset 473): the step after tx_contribs.R that was done by hand on 2026-10-12, as a
# script (written 2026-10-30 from the notes in datasets/473-tx-contributions.md and checked against the uploaded files).
# tx_contribs.R writes one file per contribution year plus tx_contribs_undated.csv. Before upload:
#   * the 1994 (18 rows) and 1999 (248 rows) files are combined, in that order, into tx_contribs_pre2000.csv;
#   * the 17 undated rows are appended to the file of the year they were received (received_dt, 2008-2014), with
#     contribution_yr left empty.
# Every value is kept as written (all columns read as text); the year files and the undated file are removed after.
#
#   Rscript tx_contribs_pre2000.R [clean dir]   # default ~/tx/clean, as tx_contribs.R
suppressPackageStartupMessages({ library(readr); library(dplyr); library(fs); library(cli) })

args <- commandArgs(trailingOnly = TRUE)
clean_dir <- path_expand(if (length(args)) args[1] else "~/tx/clean")
read_text <- function(f) read_csv(f, col_types = cols(.default = col_character()), na = "", progress = FALSE)
yr_file <- function(y) path(clean_dir, sprintf("tx_contribs_%s.csv", y))

# 1. the years before 2000 -> tx_contribs_pre2000.csv
files <- basename(dir_ls(clean_dir, regexp = "tx_contribs_\\d{4}\\.csv$"))
years <- as.integer(substr(files, 13, 16))
early <- sort(years[years < 2000])
pre <- bind_rows(lapply(early, function(y) read_text(yr_file(y))))
write_csv(pre, path(clean_dir, "tx_contribs_pre2000.csv"), na = "")
file_delete(yr_file(early))
cli_alert_success("pre2000: {nrow(pre)} rows from {paste(early, collapse = ', ')}")

# 2. undated rows -> the file of their received year
undated_csv <- path(clean_dir, "tx_contribs_undated.csv")
if (file_exists(undated_csv)) {
  und <- read_text(undated_csv)
  stopifnot(all(is.na(und$contribution_yr)), !anyNA(und$received_dt))
  for (y in split(und, substr(und$received_dt, 1, 4))) {
    yr <- substr(y$received_dt[1], 1, 4)
    stopifnot(file_exists(yr_file(yr)))
    write_csv(y, yr_file(yr), na = "", append = TRUE, col_names = FALSE)
    cli_alert_success("undated: {nrow(y)} rows -> tx_contribs_{yr}.csv")
  }
  file_delete(undated_csv)
}
