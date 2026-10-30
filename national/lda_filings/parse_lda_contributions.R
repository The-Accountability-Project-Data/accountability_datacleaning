#!/usr/bin/env Rscript

# Parse LDA contribution reports (LD-203) to CSV
# Claude, Oct 2026, for the datacleaning_agents effort. Replaces lda_contribs_py/read_file.py, which parsed the
# House XML downloads (disclosures.house.gov), a source that's gone; the same reports now come from
# https://lda.gov/api/v1/contributions/ (scraped by scrape_lda_filings.R into data/json/contributions/<year>/).
#
# One row per contribution item, and only reports that list contributions -- as the old files did. The first
# 22 columns keep the old files' names (lda_cols.csv, table "contributions"), filled from the matching API
# fields; fields the old files didn't have are appended after them. Values are as published by the API, so a few
# differ in form from the XML era:
#   type          contribution_type_display  ("FECA", "Honorary Expenses", ...: same as before)
#   date          MM/DD/YYYY                 (converted from the API's YYYY-MM-DD: dataset 2's mapping takes the
#                                            year from the last 4 characters of date, fromdate / xYYYY)
#   filenum       filing_uuid                (was the House XML file number)
#   source        "lda.gov API v1"           (was e.g. 2018_MidYear_XML)
#   filerType     filer_type_display         ("Lobbyist" / "Organization"; was L / O)
#   signedDate    dt_posted, UTC              (was the signed date in local time)
#   amendment     "true" for MA / YA report types
# Writes data/csv/lda_contributions_<year>.csv; a check row per year goes to data/csv/parse_check.csv. No upload.
#
# Rscript --vanilla national/lda_filings/parse_lda_contributions.R <year> [<year> ...]

suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(readr))
suppressPackageStartupMessages(library(lubridate))
suppressPackageStartupMessages(library(cli))
suppressPackageStartupMessages(library(fs))

here_dir <- if (dir_exists("national/lda_filings")) "national/lda_filings" else "."
json_root <- path(here_dir, "data", "json", "contributions")
csv_dir <- dir_create(path(here_dir, "data", "csv"))
check_file <- path(csv_dir, "parse_check.csv")
ref <- read_csv(path(here_dir, "lda_cols.csv"), col_types = cols(.default = col_character()))
want <- ref$column[ref$table == "contributions"]

years <- as.integer(commandArgs(trailingOnly = TRUE))
if (!length(years) || anyNA(years)) {
  cli_alert_danger("Usage: parse_lda_contributions.R <year> [<year> ...]"); quit(save = "no", status = 1)
}

na_chr <- function(v) if (is.null(v) || length(v) == 0) NA_character_ else as.character(v)
mdy_date <- function(x) ifelse(grepl("^\\d{4}-\\d{2}-\\d{2}$", x), sub("^(\\d{4})-(\\d{2})-(\\d{2})$", "\\2/\\3/\\1", x), x)
utc <- function(x) format(ymd_hms(x, quiet = TRUE), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

report_fields <- function(r) {
  l <- r$lobbyist %||% list()
  g <- r$registrant %||% list()
  list(
    filenum = na_chr(r$filing_uuid), source = "lda.gov API v1", filerType = na_chr(r$filer_type_display),
    organizationName = na_chr(g$name),
    lobbyistPrefix = na_chr(l$prefix_display), lobbyistFirstName = na_chr(l$first_name),
    lobbyistMiddleName = na_chr(l$middle_name), lobbyistLastName = na_chr(l$last_name),
    lobbyistSuffix = na_chr(l$suffix_display),
    senateRegID = na_chr(g$id), houseRegID = na_chr(g$house_registrant_id),
    reportYear = na_chr(r$filing_year), reportType = na_chr(r$filing_type),
    amendment = if (isTRUE(r$filing_type %in% c("MA", "YA"))) "true" else "false",
    signedDate = utc(na_chr(r$dt_posted)), noContributions = tolower(na_chr(r$no_contributions)),
    # appended: not in the old files
    lobbyist_id = na_chr(l$id), filing_period = na_chr(r$filing_period),
    filer_address_1 = na_chr(r$address_1), filer_address_2 = na_chr(r$address_2), filer_city = na_chr(r$city),
    filer_state = na_chr(r$state), filer_zip = na_chr(r$zip), filer_country = na_chr(r$country),
    contact_name = na_chr(r$contact_name), comments = na_chr(r$comments),
    pacs = if (length(r$pacs)) paste(unlist(r$pacs), collapse = "; ") else NA_character_,
    filing_document_url = na_chr(r$filing_document_url)
  )
}
`%||%` <- function(x, y) if (is.null(x)) y else x

for (year in years) {
  pages <- dir_ls(path(json_root, year), regexp = "page_\\d+\\.json$")
  cli_h2("contributions {year}: {length(pages)} pages")
  rows <- list(); n_reports <- 0; n_with <- 0
  for (p in pages) {
    for (r in fromJSON(p, simplifyVector = FALSE)$results) {
      n_reports <- n_reports + 1
      if (!length(r$contribution_items)) next
      n_with <- n_with + 1
      base <- report_fields(r)
      for (it in r$contribution_items) {
        rows[[length(rows) + 1]] <- c(list(
          type = na_chr(it$contribution_type_display), contributorName = na_chr(it$contributor_name),
          payeeName = na_chr(it$payee_name), recipientName = na_chr(it$honoree_name),
          amount = na_chr(it$amount), date = mdy_date(na_chr(it$date))), base)
      }
    }
  }
  df <- bind_rows(rows)
  extra <- setdiff(names(df), want)
  df <- df[, c(want, extra)]
  out <- path(csv_dir, sprintf("lda_contributions_%s.csv", year))
  write_csv(df, out, na = "")
  write_csv(tibble(table = "contributions", year = year, file = basename(out), rows = nrow(df), cols = ncol(df),
                   blank_ref_cols = paste(want[vapply(want, function(c) all(is.na(df[[c]])), TRUE)], collapse = " "),
                   added_cols = paste(extra, collapse = " "),
                   checked = sprintf("%s; %d reports, %d with contributions", Sys.time(), n_reports, n_with)),
            check_file, append = file_exists(check_file))
  cli_alert_success("{basename(out)}: {format(nrow(df), big.mark = ',')} items from {n_with} of {n_reports} reports")
}
cli_alert_info("Done; nothing was uploaded.")
