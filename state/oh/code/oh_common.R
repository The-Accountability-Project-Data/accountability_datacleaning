# Shared code for the Ohio campaign finance builds (oh_contribs.R; oh_expends.R later), November 2026.
#
# Input: data/parsed/oh_<dataset>.csv from reparse.py (run it first). It stacks the yearly files of the Ohio Campaign
# Finance System's "All Candidate & Non-Candidate Committee Files" (https://campaignfinance.ohiosos.gov/public/cf/
# downloads), downloaded 2026-11-16, and adds source_file. Column names are the source headers in snake case.
# The export holds the current version of each report: Amended = "Y" marks rows on a report that was amended (in 2024,
# only 37 of 364,171 rows have an identical row with the other flag, all on two different reports), so nothing is
# dropped as superseded.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
can_prov <- c("ON", "QC", "NS", "NB", "MB", "BC", "PE", "SK", "AB", "NL")

read_parsed <- function(dataset) {
  f <- Sys.getenv("OH_PARSED", here("state", "oh", dataset, "data", "parsed", paste0("oh_", dataset, ".csv")))  # OH_PARSED: a test file
  x <- fread(f, colClasses = "character",
             na.strings = "", encoding = "UTF-8", showProgress = FALSE)
  # fread keeps the escaped quotes of quoted fields doubled ("" -> ""); reparse.py's csv writer escapes every quote
  # that way and quotes every field holding one, so "" -> " restores the values exactly.
  for (j in names(x)) if (any(grepl('""', x[[j]], fixed = TRUE))) set(x, j = j, value = gsub('""', '"', x[[j]], fixed = TRUE))
  x
}
na_if_blank <- function(v) { v[!is.na(v) & trimws(v) == ""] <- NA_character_; v }
# The export writes the text "NA" (ZIP "NA-NA") in every address field when no address was given; treated as missing
# in the *_clean columns only (the source columns keep it as published).
na_text <- function(v) { v[!is.na(v) & v %in% c("NA", "NA-NA")] <- NA_character_; v }

parse_mdy <- function(d) {
  out <- as.IDate(d, format = "%m/%d/%Y")
  stopifnot(sum(is.na(out) & !is.na(d)) == 0)
  out
}
# "$1,234.56", "-$5.00" or "($5.00)" -> number
parse_dollars <- function(v) {
  neg <- !is.na(v) & (startsWith(v, "-") | startsWith(v, "("))
  out <- suppressWarnings(as.numeric(gsub("[$,()\\-]", "", v)))
  stopifnot(sum(is.na(out) & !is.na(v)) == 0)
  fifelse(neg, -out, out)
}

# Normalization with caches (each distinct value is normalized once).
cache <- new.env()
memo <- function(name, keys, fun) {
  tab <- cache[[name]]
  u <- unique(keys); u <- u[!is.na(u)]
  new <- if (is.null(tab)) u else setdiff(u, tab$k)
  if (length(new)) {
    add <- data.table(k = new, val = fun(new))
    tab <- rbind(tab, add); setkey(tab, k); cache[[name]] <- tab
  }
  if (is.null(tab)) return(rep(NA_character_, length(keys)))
  tab[J(keys), val, on = "k"]
}
norm_address <- function(a) memo("addr", a, function(u) normal_address(u, abbs = usps_street, na_rep = TRUE))
norm_zip <- function(z) memo("zip", z, function(u) normal_zip(u, na_rep = TRUE))
norm_state <- function(s) memo("state", s, function(u) normal_state(u, abbreviate = TRUE, na_rep = TRUE,
                                                                     valid = c(valid_state, can_prov)))
norm_city <- function(c) memo("city", c, function(u) normal_city(str_replace(u, "\\bTWP\\b", "TOWNSHIP"),
                                                                 abbs = usps_city, states = c("OH", "DC", "OHIO"),
                                                                 na = c(invalid_city, "UNAVAILABLE"), na_rep = TRUE))
# City swap: replace the normalized city with the ZIP code's city when it is an abbreviation of it or one edit away;
# otherwise keep the normalized city (also when the ZIP code has no match).
zc <- as.data.table(zipcodes)
do_city_swap <- function(city_norm, state_norm, zip_norm) {
  q <- data.table(city_norm, state_norm, zip_norm)
  k <- unique(q)[!is.na(city_norm)]
  k <- merge(k, zc[, .(state_norm = state, zip_norm = zip, city_match = city)], by = c("state_norm", "zip_norm"),
             all.x = TRUE, allow.cartesian = TRUE)
  k[, swap := fifelse(!is.na(city_match) & (is_abbrev(city_norm, city_match) |
                                               str_dist(city_norm, city_match) == 1), city_match, city_norm)]
  k <- k[, .(swap = swap[1]), by = .(city_norm, state_norm, zip_norm)]
  k[q, swap, on = c("city_norm", "state_norm", "zip_norm")]
}
# Refine (OpenRefine key collision + 1-gram merge over the whole column), kept only where the refined city, state
# and ZIP code are a valid combination. Returns a table city_swap, state, zip -> city_refine.
refine_map <- function(swap, state, zip) {
  m <- unique(data.table(city_swap = swap)[!is.na(city_swap)][, city_refine := n_gram_merge(key_collision_merge(city_swap), numgram = 1)])
  m <- unique(m)[city_refine != city_swap]
  combos <- unique(data.table(city_swap = swap, state_norm = state, zip_norm = zip))
  good <- merge(combos, m, by = "city_swap")
  good[zc, on = .(city_refine = city, state_norm = state, zip_norm = zip), nomatch = 0L][
    , .(city_swap, state_norm, zip_norm, city_refine)]
}
