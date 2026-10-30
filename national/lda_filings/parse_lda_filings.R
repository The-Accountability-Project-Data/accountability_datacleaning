#!/usr/bin/env Rscript

# Kiernan Nicholls
# Parse LDA files to CSV
# https://lda.senate.gov/api/
# Fri Oct 29 13:41:24 2021 ------------------------------
#
# Revised Oct 2026 (Claude, for the datacleaning_agents effort):
#   * reads the per-filing-year JSON pages written by scrape_lda_filings.R
#     (data/json/filings/<year>/page_*.json) and writes one file per table per filing year:
#     data/csv/lda_<table>_<year>.csv
#   * the same five tables as before, built the same way (one row per filing; per filing x lobbyist with the
#     issues collapsed; per conviction disclosure; per foreign entity; per affiliated organization)
#   * columns follow lda_cols.csv (the headers of the Jan 2023 update files), in that order; fields the API
#     has added since are appended at the end (sorted), so every year's file has the same header
#   * values are as published; dt_posted is converted to UTC (2022-04-05T05:47:33Z), as the old files had it
#   * no upload (the old version uploaded public-read); a check row per table/year goes to data/csv/parse_check.csv
#
#   * a folder written with LDA_POSTED_AFTER (e.g. 2022_after_2023-01-11) is parsed to
#     lda_<table>_2022_posted-after-20230111.csv
#   * LDA_EXCLUDE_UUIDS=<file> (one filing_uuid per line): filings already in an older file are skipped, so they
#     aren't loaded twice (2026-10-07: the 71,511 filings of the Jan 2023 update file)
#
# Rscript --vanilla national/lda_filings/parse_lda_filings.R <year | year_after_yyyy-mm-dd> [...]

suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(readr))
suppressPackageStartupMessages(library(lubridate))
suppressPackageStartupMessages(library(cli))
suppressPackageStartupMessages(library(fs))

here_dir <- if (dir_exists("national/lda_filings")) "national/lda_filings" else "."
json_root <- path(here_dir, "data", "json", "filings")
csv_dir <- dir_create(path(here_dir, "data", "csv"))
check_file <- path(csv_dir, "parse_check.csv")
ref <- read_csv(path(here_dir, "lda_cols.csv"), col_types = cols(.default = col_character()))

years <- commandArgs(trailingOnly = TRUE)
if (!length(years) || !all(grepl("^\\d{4}(_after_\\d{4}-\\d{2}-\\d{2})?$", years))) {
  cli_alert_danger("Usage: parse_lda_filings.R <year | year_after_yyyy-mm-dd> [...]"); quit(save = "no", status = 1)
}
label <- function(token) sub("_after_(\\d{4})-(\\d{2})-(\\d{2})$", "_posted-after-\\1\\2\\3", token)
exclude_file <- Sys.getenv("LDA_EXCLUDE_UUIDS", "")
exclude <- if (nzchar(exclude_file)) unique(trimws(read_lines(exclude_file))) else character()
if (length(exclude)) cli_alert_info("Skipping {length(exclude)} filing_uuids listed in {exclude_file}")

# helpers -------------------------------------------------------------------

na_chr <- function(v) if (is.null(v) || length(v) == 0) NA_character_ else as.character(v)

# scalar fields of a record, nested objects flattened as parent.child; arrays are skipped
flat <- function(x, prefix = "") {
  out <- list()
  for (k in names(x)) {
    v <- x[[k]]
    key <- paste0(prefix, k)
    if (is.list(v) && !is.null(names(v))) {
      out <- c(out, flat(v, paste0(key, ".")))
    } else if (is.null(v) || (is.atomic(v) && length(v) <= 1)) {
      out[[key]] <- na_chr(v)
    }
  }
  out
}
keep <- function(x) x[!grepl("_display$", names(x)) & !grepl("ppb_", names(x))]
utc <- function(x) format(ymd_hms(x, quiet = TRUE), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

lob_fields <- function(l, with_display) {
  out <- list(`lobbyist.id` = na_chr(l$id))
  if (with_display) {
    out <- c(out, list(`lobbyist.prefix` = na_chr(l$prefix), `lobbyist.prefix_display` = na_chr(l$prefix_display)))
  } else {
    out <- c(out, list(`lobbyist.prefix` = na_chr(l$prefix_display)))
  }
  out <- c(out, list(`lobbyist.first_name` = na_chr(l$first_name), `lobbyist.nickname` = na_chr(l$nickname),
                     `lobbyist.middle_name` = na_chr(l$middle_name), `lobbyist.last_name` = na_chr(l$last_name)))
  if (with_display) {
    c(out, list(`lobbyist.suffix` = na_chr(l$suffix), `lobbyist.suffix_display` = na_chr(l$suffix_display)))
  } else {
    c(out, list(`lobbyist.suffix` = na_chr(l$suffix_display)))
  }
}

parse_filing <- function(r) {
  f <- keep(flat(r))
  f$dt_posted <- utc(f$dt_posted)
  reg <- list(filing_uuid = f$filing_uuid, dt_posted = f$dt_posted,
              `registrant.id` = f$registrant.id, `registrant.name` = f$registrant.name,
              `registrant.address_1` = f$registrant.address_1, `registrant.address_2` = f$registrant.address_2,
              `registrant.city` = f$registrant.city, `registrant.state` = f$registrant.state,
              `registrant.zip` = f$registrant.zip)
  cli <- list(filing_uuid = f$filing_uuid, dt_posted = f$dt_posted, `client.id` = f$client.id,
              `client.name` = f$client.name, `client.state` = f$client.state)

  # lobbyists: one row per lobbyist, issues of every activity they appear on, in order
  lobs <- list(); issues <- list()
  for (a in r$lobbying_activities) {
    for (le in a$lobbyists) {
      id <- na_chr(le$lobbyist$id)
      if (is.null(lobs[[id]])) lobs[[id]] <- lob_fields(le$lobbyist, with_display = FALSE)
      issues[[id]] <- c(issues[[id]], na_chr(a$general_issue_code_display))
    }
  }
  lob_rows <- lapply(names(lobs), function(id) c(reg, lobs[[id]], list(all_issues = paste(issues[[id]], collapse = ", "))))

  con_rows <- lapply(r$conviction_disclosures, function(cd) {
    c(reg, list(date = na_chr(cd$date), description = na_chr(cd$description)), lob_fields(cd$lobbyist, TRUE))
  })
  for_rows <- lapply(r$foreign_entities, function(e) {
    e <- keep(flat(e)); names(e) <- paste0("entity.", names(e)); c(cli, e)
  })
  org_rows <- lapply(r$affiliated_organizations, function(o) {
    o <- keep(flat(o)); names(o) <- paste0("org.", names(o)); c(cli, o)
  })
  list(`client-firm` = list(f), `firm-lobbyist` = lob_rows, `convict-lobbyist` = con_rows,
       `client-foreign` = for_rows, `client-affiliate` = org_rows)
}

# parse ------------------------------------------------------------------------

tables <- c("client-firm", "firm-lobbyist", "convict-lobbyist", "client-foreign", "client-affiliate")
parsed <- list()
for (year in years) {
  pages <- dir_ls(path(json_root, year), regexp = "page_\\d+\\.json$")
  cli_h2("filings {year}: {length(pages)} pages")
  acc <- setNames(lapply(tables, function(t) list()), tables)
  n_skip <- 0
  for (p in pages) {
    for (r in fromJSON(p, simplifyVector = FALSE)$results) {
      if (length(exclude) && isTRUE(r$filing_uuid %in% exclude)) { n_skip <- n_skip + 1; next }
      x <- parse_filing(r)
      for (t in tables) if (length(x[[t]])) acc[[t]][[length(acc[[t]]) + 1]] <- x[[t]]
    }
  }
  if (length(exclude)) cli_alert_info("{year}: skipped {n_skip} filings already in an older file")
  parsed[[as.character(year)]] <- lapply(acc, function(chunks) {
    rows <- unlist(chunks, recursive = FALSE)  # one list of rows per filing -> one list of rows
    if (length(rows)) bind_rows(rows) else tibble()
  })
}

# align across years so each table has one header, then write --------------------------------

for (t in tables) {
  all_cols <- unique(unlist(lapply(parsed, function(p) names(p[[t]]))))
  want <- ref$column[ref$table == t]
  extra <- sort(setdiff(all_cols, want))
  for (year in names(parsed)) {
    df <- parsed[[year]][[t]]
    for (m in setdiff(c(want, extra), names(df))) df[[m]] <- rep(NA_character_, nrow(df))
    df <- df[, c(want, extra)]
    out <- path(csv_dir, sprintf("lda_%s_%s.csv", t, label(year)))
    write_csv(df, out, na = "")
    write_csv(tibble(table = t, year = year, file = basename(out), rows = nrow(df), cols = ncol(df),
                     blank_ref_cols = paste(want[vapply(want, function(c) all(is.na(df[[c]])), TRUE)], collapse = " "),
                     added_cols = paste(extra, collapse = " "), checked = as.character(Sys.time())),
              check_file, append = file_exists(check_file))
    cli_alert_success("{basename(out)}: {format(nrow(df), big.mark = ',')} rows x {ncol(df)} cols")
  }
}
cli_alert_info("Done; nothing was uploaded.")
