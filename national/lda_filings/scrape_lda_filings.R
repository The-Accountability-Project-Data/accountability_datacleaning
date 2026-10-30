#!/usr/bin/env Rscript

# Kiernan Nicholls
# Find all senate lobbyists
# https://lda.senate.gov/api/
# Tue Jul 27 14:21:30 2021 ------------------------------------------------
#
# Revised Oct 2026 (Claude, for the datacleaning_agents effort):
#   * the API moved to https://lda.gov/api/v1/ (lda.senate.gov was sunset July 31, 2026)
#   * pages are now capped at 25 records, and the API requires a filter to page past page 1, so this
#     pages one filing_year at a time, ordered by dt_posted (filings posted mid-run land at the end)
#   * one request at a time, at least DELAY seconds between requests (user's rule); API key required
#   * resumable: each page is saved as JSON the moment it arrives (write .part, then rename) and a restart
#     continues after the last saved page
#   * on HTTP 429 it waits out a short Retry-After once, otherwise stops; server errors retry 3 times with
#     backoff, then stop -- it never hammers the API
#   * every request is logged to data/json/<endpoint>/requests.csv
#   * also scrapes the contributions (LD-203) endpoint
#
# Rscript --vanilla national/lda_filings/scrape_lda_filings.R <filings|contributions> <year> [<year> ...]
# LDA_API_KEY must be set in the environment (never put the key in this file).

suppressPackageStartupMessages(library(httr))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(cli))
suppressPackageStartupMessages(library(fs))

`%||%` <- function(x, y) if (is.null(x)) y else x # base R has it only from 4.4

DELAY <- 0.5         # seconds between requests; one request in flight at a time
PAGE_SIZE <- 25      # the API's maximum (100 and 250 tested 2026-10-06: still 25)
API <- "https://lda.gov/api/v1"
MAX_PAGES <- as.integer(Sys.getenv("LDA_MAX_PAGES", "0")) # testing only: stop each year after this many pages
# optional: only filings posted after this date (yyyy-mm-dd); pages go to <year>_after_<date>/ instead of <year>/
POSTED_AFTER <- Sys.getenv("LDA_POSTED_AFTER", "")
if (nzchar(POSTED_AFTER) && !grepl("^\\d{4}-\\d{2}-\\d{2}$", POSTED_AFTER)) cli_quit("LDA_POSTED_AFTER must be yyyy-mm-dd")
UA <- user_agent("https://publicaccountability.org/")

cli_quit <- function(text) {
  cli_alert_danger(text)
  quit(save = "no", status = 1)
}

# arguments ---------------------------------------------------------------

cmd_args <- commandArgs(trailingOnly = TRUE)
if (length(cmd_args) < 2 || !(cmd_args[1] %in% c("filings", "contributions"))) {
  cli_quit("Usage: scrape_lda_filings.R <filings|contributions> <year> [<year> ...]")
}
endpoint <- cmd_args[1]
years <- as.integer(cmd_args[-1])
if (anyNA(years)) cli_quit("Years must be integers")

api_key <- Sys.getenv("LDA_API_KEY")
if (!nzchar(api_key)) cli_quit("Set LDA_API_KEY in the environment")
auth <- add_headers(Authorization = paste("Token", api_key))

here_dir <- if (dir_exists("national/lda_filings")) "national/lda_filings" else "."
out_root <- dir_create(path(here_dir, "data", "json", endpoint))
req_log <- path(out_root, "requests.csv")
if (!file_exists(req_log)) {
  write("time_utc,url,status,n_results,seconds,note", req_log)
}

# one request ---------------------------------------------------------------

last_request_end <- 0

get_page <- function(year, page) {
  url <- modify_url(
    paste0(API, "/", endpoint, "/"),
    query = c(list(filing_year = year, ordering = "dt_posted", page_size = PAGE_SIZE, page = page),
              if (nzchar(POSTED_AFTER)) list(filing_dt_posted_after = POSTED_AFTER))
  )
  for (attempt in 1:4) {
    wait <- DELAY - (as.numeric(Sys.time()) - last_request_end)
    if (wait > 0) Sys.sleep(wait)
    t0 <- Sys.time()
    res <- tryCatch(GET(url, UA, auth, timeout(120)), error = function(e) e)
    last_request_end <<- as.numeric(Sys.time())
    secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)
    if (inherits(res, "error")) {
      status <- NA; note <- gsub("[,\n]", " ", conditionMessage(res)); n <- NA
    } else {
      status <- status_code(res); note <- ""; n <- NA
    }
    if (isTRUE(status == 200)) {
      txt <- content(res, as = "text", encoding = "UTF-8")
      dat <- fromJSON(txt, simplifyVector = FALSE)
      n <- length(dat$results)
      write(sprintf("%s,%s,%s,%s,%s,", format(Sys.time(), tz = "UTC"), url, status, n, secs),
            req_log, append = TRUE)
      return(list(txt = txt, dat = dat))
    }
    write(sprintf("%s,%s,%s,%s,%s,%s", format(Sys.time(), tz = "UTC"), url, status, n, secs, note),
          req_log, append = TRUE)
    if (isTRUE(status == 429)) {
      retry_after <- suppressWarnings(as.numeric(headers(res)[["retry-after"]] %||% NA))
      if (attempt == 1 && !is.na(retry_after) && retry_after <= 120) {
        cli_alert_warning("Throttled (429); waiting {retry_after}s once")
        Sys.sleep(retry_after + 1)
        next
      }
      cli_quit("Throttled (429), Retry-After {retry_after}s: stopping rather than pushing. Resume later.")
    }
    if (isTRUE(status %in% c(400, 401, 403, 404))) {
      cli_quit("HTTP {status} for {url}: stopping")
    }
    if (attempt == 4) cli_quit("Request failed 4 times ({status} {note}) for {url}: stopping. Resume later.")
    backoff <- c(10, 30, 60)[attempt]
    cli_alert_warning("HTTP {status} {note}; retrying in {backoff}s")
    Sys.sleep(backoff)
  }
}

# each year ---------------------------------------------------------------

for (year in years) {
  cli_h1("{endpoint} {year}")
  year_dir <- dir_create(path(out_root, if (nzchar(POSTED_AFTER)) paste0(year, "_after_", POSTED_AFTER) else year))
  have <- dir_ls(year_dir, regexp = "page_\\d+\\.json$")
  page <- if (length(have)) max(as.integer(sub(".*page_(\\d+)\\.json$", "\\1", have))) + 1 else 1
  if (page > 1) cli_alert_info("Resuming at page {page} ({length(have)} pages on disk)")

  repeat {
    got <- get_page(year, page)
    if (page == 1 || page %% 100 == 0) {
      cli_alert_info("page {page} of {ceiling((got$dat$count %||% 0) / PAGE_SIZE)} (count {got$dat$count})")
    }
    if (length(got$dat$results) == 0) break
    out <- path(year_dir, sprintf("page_%05d.json", page))
    write(got$txt, paste0(out, ".part"))
    file_move(paste0(out, ".part"), out)
    if (is.null(got$dat[["next"]])) break
    if (MAX_PAGES > 0 && page >= MAX_PAGES) { cli_alert_warning("LDA_MAX_PAGES={MAX_PAGES}: stopping early (test)"); break }
    page <- page + 1
  }

  # check: unique records on disk against the API's count on the last page
  files <- dir_ls(year_dir, regexp = "page_\\d+\\.json$")
  uuids <- unlist(lapply(files, function(f) {
    vapply(fromJSON(f, simplifyVector = FALSE)$results, function(r) r$filing_uuid %||% NA_character_, "")
  }))
  last_count <- fromJSON(files[length(files)], simplifyVector = FALSE)$count
  summary <- list(endpoint = endpoint, year = year, posted_after = POSTED_AFTER, pages = length(files), records = length(uuids),
                  unique_uuid = length(unique(uuids)), api_count_at_end = last_count,
                  finished_utc = format(Sys.time(), tz = "UTC"))
  write(toJSON(summary, auto_unbox = TRUE), path(year_dir, "summary.json"))
  cli_alert_success("{endpoint} {year}: {summary$pages} pages, {summary$unique_uuid} unique of count {last_count}")
}
cli_alert_success("Done; nothing was uploaded.")
