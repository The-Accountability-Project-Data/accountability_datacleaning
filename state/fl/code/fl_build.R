# Florida campaign contributions / expenditures, 2023 onward -- November 2026 update.
#   Rscript state/fl/code/fl_build.R <raw dir> contribs|expends, from the repo root.
# Output: state/fl/contribs/data/clean/fl_contribs_2023-2026.csv or state/fl/expends/data/clean/fl_expends_2023-2026.csv.
# The earlier files are kept for 1995-2022 (cut at 2023-01-01).
#
# - Source: the Florida Division of Elections Campaign Finance Database query forms
#   (https://dos.elections.myflorida.com/campaign-finance/contributions/ and .../expenditures/), all candidates and
#   committees, "Return Results in a Tab Delimited Text File", no record limit, queried 2026-11-17:
#   contributions by calendar quarter 2023 Q1-2026 Q4 plus dates from 2027-01-01 on (typos as filed);
#   expenditures from 2023-01-01 with no end date (the expenditure form answers "Invalid Date Range" to any end date).
# - Reading: tab-separated, CRLF, no quoting; every record has the header's field count (9 / 8). Lines are UTF-8 when
#   valid, otherwise windows-1252 (latin1 for its five undefined bytes).
# - Layout: the earlier files' columns: the source headers in snake case (Candidate/Committee -> comm_name), then
#   na_flag, dupe_flag, year, address_clean, city_clean, state_clean, zip_clean. date as YYYY-MM-DD, amount as a number;
#   everything else as published (addresses the state withholds appear as asterisks).
# - na_flag: date, contributor/payee name, amount or comm_name missing. dupe_flag: every copy of a row identical on all
#   source columns. year = year(date).
# - city_state_zip ("MIAMI, FL 33101") is split as in the earlier build (city before the comma, two letters before the
#   ZIP, the trailing ZIP); address split at 3+ spaces into two lines, each normalized, joined. state_clean, zip_clean,
#   city_clean normalized; the city swapped with the ZIP code's city when an abbreviation or one edit away, then
#   refined where the refined city/state/ZIP is valid.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
here::i_am("state/fl/code/fl_build.R")
args <- commandArgs(TRUE); raw <- args[1]; kind <- args[2]
stopifnot(kind %in% c("contribs", "expends"))
src <- if (kind == "contribs") "contrib" else "expend"
NAME <- if (kind == "contribs") "contributor_name" else "payee_name"
out_dir <- dir_create(here("state", "fl", kind, "data", "clean"))

read_tsv_fixed <- function(path) {
  x <- readLines(path, warn = FALSE, encoding = "bytes")
  ok8 <- validUTF8(x)
  y <- x[!ok8]; Encoding(y) <- "unknown"
  w <- iconv(y, from = "windows-1252", to = "UTF-8")
  w[is.na(w)] <- iconv(y[is.na(w)], from = "latin1", to = "UTF-8")
  Encoding(x) <- "unknown"; x[!ok8] <- w; Encoding(x) <- "UTF-8"
  d <- fread(text = x, sep = "\t", quote = "", colClasses = "character", na.strings = "", encoding = "UTF-8",
             fill = FALSE, strip.white = FALSE, showProgress = FALSE)
  cat(basename(path), nrow(d), "rows;", sum(!ok8), "non-UTF-8 lines\n")
  d
}
files <- sort(dir_ls(raw, regexp = paste0("/fl_", src, "_[^/]+\\.txt$")))
fl <- rbindlist(lapply(files, read_tsv_fixed), use.names = TRUE)
setnames(fl, function(h) gsub("_+", "_", gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(h)))))
setnames(fl, "candidate_committee", "comm_name")
SRC <- names(fl)
LAYOUT <- c(SRC, "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")
cat("rows:", nrow(fl), " columns:", paste(SRC, collapse = ", "), "\n")

fl[, date := as.IDate(date, format = "%m/%d/%Y")]
cat("dates not parsed:", fl[is.na(date), .N], "\n")
fl[, amount := as.numeric(gsub(",", "", amount))]
fl[, na_flag := is.na(date) | is.na(get(NAME)) | is.na(amount) | is.na(comm_name)]
fl[, dupe_flag := duplicated(fl, by = SRC) | duplicated(fl, by = SRC, fromLast = TRUE)]
fl[, year := year(date)]

# city, state, ZIP from city_state_zip (as the earlier build)
csz <- unique(fl[, .(city_state_zip)])[!is.na(city_state_zip)]
csz[, x := city_state_zip |> str_squish() |>
      str_replace("(?<=\\s)F, L,?\\.?", ", FL") |> str_remove("(?<=FL),") |>
      str_replace("([A-Z]{2})(\\d+)", "\\1 \\2") |> str_replace("\\sDC,", ", DC")]
csz[, `:=`(city_sep = str_extract(x, "(.*)(?=,(\\s|$))"),
           state_sep = str_extract(x, "[A-Z\\*\\.]{1,}(?=\\s\\d|$)"),
           zip_sep = str_extract(x, "\\d{2,5}(?:-\\d{4})?$"))]
fl[csz, `:=`(city_sep = i.city_sep, state_sep = i.state_sep, zip_sep = i.zip_sep), on = "city_state_zip"]

addr <- unique(fl[, .(address)])[!is.na(address)]
addr[, a1 := sub("\\s{3,}.*$", "", address)][, a2 := fifelse(grepl("\\s{3,}", address), sub("^.*?\\s{3,}", "", address), NA_character_)]
na_star <- function(v) { v[!is.na(v) & grepl("^\\*+$", v)] <- NA_character_; v }
addr[, address_clean := {
  n1 <- normal_address(na_star(a1), abbs = usps_street, na_rep = TRUE, na = invalid_city)
  n2 <- normal_address(na_star(a2), abbs = usps_street, na_rep = TRUE, na = invalid_city)
  out <- str_squish(paste(fcoalesce(n1, ""), fcoalesce(n2, ""))); out[out == ""] <- NA_character_; out }]
fl[addr, address_clean := i.address_clean, on = "address"]

zc <- as.data.table(zipcodes)
geo <- unique(fl[, .(city_sep, state_sep, zip_sep)])
geo[, zip_clean := normal_zip(na_star(zip_sep), na_rep = TRUE)]
geo[, state_clean := normal_state(na_star(state_sep), abbreviate = TRUE, na_rep = TRUE, valid = valid_state)]
geo[, city_norm := normal_city(na_star(city_sep), abbs = usps_city, states = c("FL", "DC", "FLORIDA"),
                               na = invalid_city, na_rep = TRUE)]
k <- merge(geo, zc[, .(state_clean = state, zip_clean = zip, city_match = city)], by = c("state_clean", "zip_clean"),
           all.x = TRUE, allow.cartesian = TRUE)
k[, swap := fifelse(!is.na(city_match) & !is.na(city_norm) &
                      (is_abbrev(city_norm, city_match) | str_dist(city_norm, city_match) == 1), city_match, city_norm)]
k <- k[, .(city_swap = swap[1]), by = .(city_sep, state_sep, zip_sep)]
geo[k, city_swap := i.city_swap, on = c("city_sep", "state_sep", "zip_sep")]
fl[geo, `:=`(zip_clean = i.zip_clean, state_clean = i.state_clean, city_swap = i.city_swap),
   on = c("city_sep", "state_sep", "zip_sep")]
m <- unique(fl[!is.na(city_swap), .(city_swap)])[, city_refine := n_gram_merge(key_collision_merge(city_swap), numgram = 1)]
m <- m[city_refine != city_swap]
good <- unique(merge(unique(fl[, .(city_swap, state_clean, zip_clean)]), m, by = "city_swap"))
good <- good[zc, on = .(city_refine = city, state_clean = state, zip_clean = zip), nomatch = 0L]
cat("refine: combinations changed:", nrow(good), "\n")
fl[good, city_refine := i.city_refine, on = c("city_swap", "state_clean", "zip_clean")]
fl[, city_clean := fcoalesce(city_refine, city_swap)]

out <- path(out_dir, sprintf("fl_%s_2023-2026.csv", kind))
fwrite(fl[, ..LAYOUT], out, na = "", dateTimeAs = "ISO")
cat("na_flag", sum(fl$na_flag), " dupe_flag", sum(fl$dupe_flag), "\n")
print(fl[, .N, keyby = year], nrows = 60)
cat("wrote", out, nrow(fl), "rows,", length(LAYOUT), "columns\n")
