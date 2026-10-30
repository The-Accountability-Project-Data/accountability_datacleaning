#!/usr/bin/env Rscript

# Mon Mar 22 10:12:51 2021 ------------------------------------------------
# Request US spending between fiscal years
# Investigative Reporting Workshop
# The Accountability Project
# Author: Kiernan Nicholls
#   * kiernan@workshop.org
#   * kiernann@protonmail.com
#
# Revised Oct 2026 (Claude, for the datacleaning_agents effort):
#   * paths follow the current repo layout (national/omb_spending/)
#   * fixed: undefined `bulk_file`, missing lubridate, unzip of every zip on each pass,
#     reading CSVs from a different folder than they were extracted to, and a "failed"
#     status that could never be reached while waiting
#   * no longer adds assist_amount / na_flag / action_year / zip_clean -- the published
#     history files are USAspending's columns as-is
#   * aligns each file to the columns in spend_cols.csv (renames/splits as in
#     spend_update.R, drops columns USAspending added since 2021, blank-fills any removed)
#   * writes us_<contract|assist>-<prime|sub>_<FY>-<n>.csv to data/clean/ and appends the
#     file mapping to spend_names.csv, like the 2021 run
#   * stops before any upload
#   * optional third argument `assistance` or `contracts` downloads USAspending's
#     pre-generated archive Full files (prime transactions only) instead of requesting
#     a bulk download -- the bulk API was failing even on one-month requests in Oct 2026
#   * COVID-19 amount columns renamed by USAspending are carried over to the old names;
#     UEI columns (DUNS replacements since Apr 2022) are kept, appended at the end

# load packages -----------------------------------------------------------

pkg <- c("readr", "httr", "here", "cli", "fs", "lubridate", "dplyr", "tidyr")
pkg <- pkg[!(pkg %in% rownames(installed.packages()))]
if (length(pkg) > 0) {
  message(
    sprintf("Please install %s additional package(s):\n", length(pkg)),
    paste("  -", pkg, collapse = "\n")
  )
  quit(save = "no", status = 1)
}

suppressPackageStartupMessages(library(readr))
suppressPackageStartupMessages(library(httr))
suppressPackageStartupMessages(library(here))
suppressPackageStartupMessages(library(cli))
suppressPackageStartupMessages(library(fs))
suppressPackageStartupMessages(library(lubridate))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tidyr))

# misc --------------------------------------------------------------------

cli_h1("Obtain Federal Spending")

# check working directory for here::here()
suppressMessages(here::i_am("national/omb_spending/spend_history.R"))
if (!grepl("accountability_datacleaning", here())) {
  cli_alert_danger("Please run from inside {.path accountability_datacleaning/}")
  quit(save = "no", status = 1)
}

# change cli theme
t <- builtin_theme()
t$span.code[1:2] <- list(`background-color` = "#232323", color = "#ffffff")
options(cli.user_theme = t)

# notes -------------------------------------------------------------------

# Award Types: All
# Agency: Awarding Agency, All
# Location: Recipient Location
# Date Type: Action Date
# File Format: CSV (Comma Delimited)

# One request per federal fiscal year (Oct 1 - Sep 30) returns four file types,
# each split by USAspending into 1,000,000-row parts:
#   1. All_Contracts_PrimeTransactions_*_<n>.csv   -> us_contract-prime_<FY>-<n>.csv
#   2. All_Assistance_PrimeTransactions_*_<n>.csv  -> us_assist-prime_<FY>-<n>.csv
#   3. All_Contracts_Subawards_*_<n>.csv           -> us_contract-sub_<FY>-<n>.csv
#   4. All_Assistance_Subawards_*_<n>.csv          -> us_assist-sub_<FY>-<n>.csv

# functions ---------------------------------------------------------------

# NULL default (base R has %||% only from 4.4)
`%||%` <- function(x, y) if (is.null(x)) y else x

# add time to message
wt <- function(...) {
  paste(..., cli::col_silver(Sys.time()))
}

ua <- user_agent("https://publicaccountability.org/") # identify to server

# script args -------------------------------------------------------------

# call script from command line with (1) first year (2) last year
# Rscript --vanilla national/omb_spending/spend_history.R 2021 2026
# or, for the archive Full files of one prime award family, add (3) assistance|contracts
# Rscript --vanilla national/omb_spending/spend_history.R 2026 2026 assistance

# the last *complete* fiscal year: FY ends Sep 30
last_full_fy <- function(today = Sys.Date()) {
  ifelse(month(today) >= 10, year(today), year(today) - 1)
}

cmd_args <- commandArgs(trailingOnly = TRUE)
archive_type <- NA_character_
if (length(cmd_args) == 3) {
  archive_type <- cmd_args[3]
  if (!(archive_type %in% c("assistance", "contracts"))) {
    cli_alert_danger("Third argument must be {.code assistance} or {.code contracts}")
    quit(save = "no", status = 1)
  }
  cli_alert_info("Using the archive Full files for prime {archive_type}")
  cmd_args <- cmd_args[1:2]
}
if (length(cmd_args) == 2) {
  cli_alert_info("Using fiscal years from arguments")
  start_yr <- as.integer(cmd_args[1])
  end_yr <- as.integer(cmd_args[2])
  if (end_yr < start_yr) {
    cli_alert_danger("First year must come before second year")
    quit(save = "no", status = 1)
  }
} else if (length(cmd_args) == 0) {
  start_yr <- end_yr <- last_full_fy()
  cli_alert_info("No arguments: using the last complete fiscal year")
} else {
  cli_alert_danger("When using args, supply (1) start year & (2) end year")
  quit(save = "no", status = 1)
}
if (end_yr > last_full_fy()) {
  cli_alert_warning("FY{end_yr} has not ended yet; its file will be partial")
}

seq_yr <- seq(start_yr, end_yr)
n_yr <- length(seq_yr)
cli_alert("FY{start_yr} to FY{end_yr} ({n_yr} year{?s})")
if (n_yr > 4) {
  cli_alert_warning("Requesting many years takes time!")
}

# folders: data/ is gitignored; spend_names.csv is the committed file mapping
om_dir <- here("national", "omb_spending")
raw_dir <- dir_create(path(om_dir, "data", "raw"))
clean_dir <- dir_create(path(om_dir, "data", "clean"))
name_file <- path(om_dir, "data", "bulk_names.csv") # requests made (run state)
if (!is.na(archive_type)) name_file <- path(om_dir, "data", paste0("archive_names_", archive_type, ".csv"))
check_file <- path(om_dir, "data", "spend_check.csv") # one row per output file
map_file <- path(om_dir, "spend_names.csv") # committed: fy, zip, csv -> aws name

# archive Full files ----------------------------------------------------------
# pre-generated per fiscal year, all agencies; listed by list_monthly_files

if (!is.na(archive_type)) {
  cli_h2("List archive files")
  bulk_names <- tibble(year = integer(), name = character(), url = character(),
                       status = character(), size = character(), nrow = character())
  for (fy in seq_yr) {
    Sys.sleep(1)
    lst <- POST(
      ua, url = "https://api.usaspending.gov/api/v2/bulk_download/list_monthly_files/",
      encode = "json", body = list(agency = "all", fiscal_year = fy, type = archive_type)
    )
    if (http_error(lst)) {
      cli_alert_danger(wt(paste0("FY", fy), http_status(lst)$message))
      quit(save = "no", status = 1)
    }
    full <- Filter(function(f) grepl("_Full_\\d{8}\\.zip$", f$url), content(lst)$monthly_files)
    if (length(full) != 1) {
      cli_alert_danger("FY{fy}: expected one Full file, found {length(full)}")
      quit(save = "no", status = 1)
    }
    cli_alert_success(wt("FY{fy}: {.path {basename(full[[1]]$url)}} (updated {full[[1]]$updated_date})"))
    bulk_names <- bind_rows(bulk_names, tibble(
      year = fy, name = basename(full[[1]]$url), url = full[[1]]$url,
      status = "finished", size = NA_character_, nrow = NA_character_
    ))
  }
  write_csv(bulk_names, name_file)
} else {

# prep data ---------------------------------------------------------------
cli_h2("Prepare request")

# request all award types
award_types <- GET("https://api.usaspending.gov/api/v2/references/award_types", ua)
award_types <- unlist(lapply(content(award_types), names))
cli_alert_success(wt("Found {length(award_types)} award types"))

# make request ============================================================
cli_h2("Request bulk download")

if (file_exists(name_file)) {
  bulk_names <- read_csv(name_file, col_types = cols(.default = col_character()))
  bulk_names$year <- as.integer(bulk_names$year)
} else {
  bulk_names <- tibble(year = integer(), name = character(), url = character(),
                       status = character(), size = character(), nrow = character())
}

cli_alert("Making requests to {.url https://api.usaspending.gov/}")
for (fy in seq_yr) {
  if (fy %in% bulk_names$year) {
    cli_alert_success("FY{fy} already requested: {.path {bulk_names$name[bulk_names$year == fy]}}")
    next
  }
  award_post <- POST(
    ua,
    url = "https://api.usaspending.gov/api/v2/bulk_download/awards/",
    encode = "json", # send post body as json
    body = list(
      filters = list(
        prime_award_types = award_types, # all award types from above
        sub_award_types = c("procurement", "grant"), # all sub-awards
        date_type = "action_date",
        date_range = list(
          start_date = sprintf("%i-10-01", fy - 1),
          end_date = sprintf("%i-09-30", fy)
        ),
        def_codes = list(),
        agencies = list(
          list(name = "All", tier = "toptier", type = "awarding") # all agencies
        )
      ),
      file_format = "csv"
    )
  )
  if (http_error(award_post)) {
    cli_alert_danger(wt(paste0("FY", fy), http_status(award_post)$message))
    quit(save = "no", status = 1)
  }
  post_data <- content(award_post)
  cli_alert_success(wt("FY{fy} requested: {.path {post_data$file_name}}"))
  bulk_names <- bind_rows(bulk_names, tibble(
    year = fy, name = post_data$file_name, url = post_data$file_url,
    status = NA_character_, size = NA_character_, nrow = NA_character_
  ))
  write_csv(bulk_names, name_file) # save after every request
}
bulk_names <- filter(bulk_names, year %in% seq_yr)

# check status ------------------------------------------------------------
cli_h2("Check each file status")

repeat {
  for (i in seq_len(nrow(bulk_names))) {
    if (isTRUE(bulk_names$status[i] == "finished")) next
    status_data <- content(GET(
      "https://api.usaspending.gov/api/v2/bulk_download/status/", ua,
      query = list(file_name = bulk_names$name[i])
    ))
    bulk_names$status[i] <- status_data$status
    bulk_names$size[i] <- as.character(fs_bytes(as.numeric(status_data$total_size %||% 0) * 1000))
    bulk_names$nrow[i] <- as.character(status_data$total_rows %||% NA)
    if (!is.null(status_data$file_url)) bulk_names$url[i] <- status_data$file_url
  }
  write_csv(bulk_names, name_file)
  if (any(bulk_names$status == "failed")) {
    cli_alert_danger(wt("Status: {col_red('failed')} for {bulk_names$name[bulk_names$status == 'failed']}"))
    quit(save = "no", status = 1)
  }
  n_fin <- sum(bulk_names$status == "finished")
  if (n_fin == nrow(bulk_names)) {
    cli_alert_success(wt("Status {col_green(n_fin)}/{nrow(bulk_names)} finished"))
    break
  }
  cli_alert_info(wt("Status: {col_cyan(n_fin)}/{nrow(bulk_names)} done, waiting 10 min"))
  Sys.sleep(600)
}

} # end bulk download request

# download bulk zip when ready --------------------------------------------
cli_h2("Download bulk files")

for (i in seq_len(nrow(bulk_names))) {
  raw_zip <- path(raw_dir, bulk_names$name[i])
  cli_h3(wt("FY{bulk_names$year[i]} ({bulk_names$size[i]})"))
  if (file_exists(raw_zip)) {
    cli_alert_warning("File already exists on disk")
    next
  }
  fy_url <- bulk_names$url[i]
  if (is.na(fy_url) || !nzchar(fy_url)) {
    fy_url <- paste0("https://files.usaspending.gov/generated_downloads/", bulk_names$name[i])
  }
  # a dropped connection raises an error rather than returning a response; either way,
  # remove the partial zip so the next run downloads again instead of skipping it
  bulk_save <- tryCatch(
    GET(fy_url, ua, write_disk(path = raw_zip), progress(type = "down")),
    error = function(e) e
  )
  if (inherits(bulk_save, "error") || http_error(bulk_save)) {
    if (file_exists(raw_zip)) file_delete(raw_zip)
    msg <- if (inherits(bulk_save, "error")) conditionMessage(bulk_save) else http_status(bulk_save)$message
    cli_alert_danger(wt("Download failed: {msg}"))
    quit(save = "no", status = 1)
  }
  cli_alert_success(wt("Download complete {.emph ({file_size(raw_zip)})}"))
}

# reference columns, as published -------------------------------------------

us_cols <- read_csv(
  file = path(om_dir, "spend_cols.csv"),
  col_types = cols(is_con = col_logical(), is_sub = col_logical(),
                   column = col_character(), type = col_character())
)

# align a file to the published columns for its type (renames as spend_update.R)
align_cols <- function(us, is_con, is_sub) {
  want <- us_cols$column[us_cols$is_con == is_con & us_cols$is_sub == is_sub]
  # keep UEI, the DUNS replacement since Apr 2022: each *_duns gets a *_uei, at the end
  want <- c(want, sub("_duns$", "_uei", grep("_duns$", want, value = TRUE)))
  # COVID-19 amounts: USAspending renamed "funded_by" -> "from"; ours are cut at 64 chars
  for (w in grep("funded_by_COVID", setdiff(want, names(us)), value = TRUE)) {
    hit <- names(us)[startsWith(names(us), sub("funded_by", "from", w))]
    if (length(hit) == 1) names(us)[names(us) == hit] <- w
  }
  desc <- "prime_award_base_transaction_description"
  if (desc %in% names(us)) {
    new_desc <- ifelse(is_sub, "prime_award_description", "award_description")
    if (!(new_desc %in% names(us))) names(us)[names(us) == desc] <- new_desc
  }
  if (!is_con && is_sub && "prime_award_cfda_numbers_and_titles" %in% names(us) &&
      !("prime_award_cfda_number" %in% names(us))) {
    us <- separate(us, col = prime_award_cfda_numbers_and_titles,
                   into = c("prime_award_cfda_number", "prime_award_cfda_title"),
                   sep = "(?<=\\d):\\s", remove = TRUE, extra = "merge", fill = "right")
  }
  missing <- setdiff(want, names(us))
  dropped <- setdiff(names(us), want)
  for (m in missing) us[[m]] <- NA_character_
  list(data = us[, want], missing = missing, dropped = dropped)
}

# extract, align and write --------------------------------------------------
cli_h2("Extract, align and write")

if (file_exists(map_file)) {
  name_map <- read_csv(map_file, col_types = cols(.default = col_character()))
} else {
  name_map <- tibble()
}

for (i in seq_len(nrow(bulk_names))) {
  fy <- bulk_names$year[i]
  raw_zip <- path(raw_dir, bulk_names$name[i])
  fy_dir <- dir_create(path(raw_dir, paste0("FY", fy)))
  z <- unzip(raw_zip, list = TRUE)
  cli_h2("FY{fy}: {nrow(z)} text file{?s} in {.path {basename(raw_zip)}}")
  all_csv <- path(fy_dir, z$Name)
  if (!all(file_exists(all_csv))) {
    cli_process_start("Extracting")
    unzip(raw_zip, exdir = fy_dir)
    cli_process_done()
  }

  for (j in seq_along(all_csv)) {
    csv_nm <- basename(all_csv[j])
    is_con <- grepl("All_Contracts", csv_nm)
    is_sub <- grepl("Subawards", csv_nm)
    file_type <- paste(ifelse(is_con, "contract", "assist"), ifelse(is_sub, "sub", "prime"), sep = "-")
    part <- sub(".*_(\\d+)\\.csv$", "\\1", csv_nm)
    aws_name <- sprintf("us_%s_%i-%s.csv", file_type, fy, part)
    out_path <- path(clean_dir, aws_name)
    cli_alert("{.file {csv_nm}} -> {.file {aws_name}}")
    if (file_exists(out_path)) {
      cli_alert_warning("Already written; skipping")
      next
    }

    us <- read_delim(all_csv[j], delim = ",", escape_double = TRUE, na = "",
                     col_types = cols(.default = col_character()), progress = FALSE)
    n_prob <- nrow(problems(us))
    if (n_prob > 0) cli_alert_warning("Found {n_prob} problem{?s} when reading")

    a <- align_cols(us, is_con, is_sub)
    if (length(a$dropped)) cli_alert_info("Dropped {length(a$dropped)} new column{?s}: {.code {a$dropped}}")
    if (length(a$missing)) cli_alert_warning("Blank-filled {length(a$missing)} removed column{?s}: {.code {a$missing}}")

    dt_col <- ifelse(is_sub, "subaward_action_date", "action_date")
    dts <- as.Date(a$data[[dt_col]])
    fy_start <- as.Date(sprintf("%i-10-01", fy - 1))
    fy_end <- as.Date(sprintf("%i-09-30", fy))
    n_out <- sum(!is.na(dts) & (dts < fy_start | dts > fy_end))
    if (!is_sub && n_out > 0) cli_alert_warning("{n_out} row{?s} with action dates outside FY{fy}")

    write_csv(a$data, out_path, na = "")
    write_csv(tibble(
      fy = fy, file_nm = csv_nm, aws_name = aws_name, file_type = file_type,
      check_dt = as.character(Sys.time()), n_row = nrow(a$data), n_col = ncol(a$data),
      min_dt = as.character(suppressWarnings(min(dts, na.rm = TRUE))),
      max_dt = as.character(suppressWarnings(max(dts, na.rm = TRUE))),
      n_outside_fy = n_out, dropped_cols = paste(a$dropped, collapse = " "),
      blank_cols = paste(a$missing, collapse = " ")
    ), check_file, append = file_exists(check_file))
    name_map <- bind_rows(name_map, tibble(
      fy = as.character(fy), zip_name = basename(raw_zip),
      zip_size = as.character(file_size(raw_zip)), csv_name = csv_nm,
      csv_size = as.character(file_size(all_csv[j])), aws_name = aws_name
    ))
    write_csv(name_map, map_file)
    cli_alert_success(wt("Wrote {format(nrow(a$data), big.mark = ',')} rows"))
    rm(us, a)
    invisible(gc())
  }
}

# stop before upload: uploads are done separately, when asked
cli_alert_info("Done. Clean files are in {.path {clean_dir}}; nothing was uploaded.")
quit(save = "no", status = 0)
