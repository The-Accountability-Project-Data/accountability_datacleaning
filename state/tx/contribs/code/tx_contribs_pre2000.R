# Texas campaign contributions: run after tx_contribs.R, on its output folder (default state/tx/contribs/data/clean; pass another
# folder as the first argument).
# tx_contribs.R writes one file per contribution year plus tx_contribs_undated.csv. This script then:
#   * the 1994 (18 rows) and 1999 (248 rows) files are combined, in that order, into tx_contribs_pre2000.csv;
#   * the 17 undated rows are appended to the file of the year they were received (received_dt, 2008-2014), with
#     contribution_yr left empty.
# Every value is kept as written (all columns read as text); the year files and the undated file are removed after.
#
#   Rscript state/tx/contribs/code/tx_contribs_pre2000.R [clean dir]   # from the repo root; default state/tx/contribs/data/clean, as tx_contribs.R
suppressPackageStartupMessages({ library(readr); library(dplyr); library(fs); library(cli); library(here) })

args <- commandArgs(trailingOnly = TRUE)
clean_dir <- if (length(args)) path_expand(args[1]) else here("state", "tx", "contribs", "data", "clean")
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
