# Shared code for the Michigan campaign finance builds (mi_contribs.R, mi_expends.R), November 2026.
#
# Input: the MiTN all-transaction export (https://mi-boe.entellitrak.com/etk-mi-boe-prod/page.request.do?page=
# gov.mi.boe.component.cfrexport.page.cfrexportdownload), one zip per transaction type and year, unzipped to
# state/mi/data/raw/<Type>_<YYYY>/*.txt (large years are split into several files). Tab-delimited, no quoting, UTF-8;
# every data row ends with one more (empty) field than the header. Blank values are often a single space.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
raw_dir <- here("state", "mi", "data", "raw")
can_prov <- c("ON", "QC", "NS", "NB", "MB", "BC", "PE", "SK", "AB", "NL")

# Read every .txt file of one type and year; all columns character, trimmed, "" -> NA.
read_mi <- function(type, year) {
  files <- dir_ls(path(raw_dir, paste0(type, "_", year)), glob = "*.txt")
  rbindlist(lapply(files, function(f) {
    hdr <- strsplit(readLines(f, n = 1, encoding = "UTF-8"), "\t", fixed = TRUE)[[1]]
    x <- fread(f, sep = "\t", quote = "", header = FALSE, skip = 1, col.names = c(hdr, "x_trailing"),
               colClasses = "character", na.strings = NULL, strip.white = TRUE, encoding = "UTF-8",
               showProgress = FALSE)
    stopifnot(all(x$x_trailing == ""))
    x[, x_trailing := NULL]
    for (j in names(x)) set(x, j = j, value = na_if_blank(x[[j]]))
    x
  }))
}
na_if_blank <- function(v) { v <- trimws(v); v[v == ""] <- NA_character_; v }

parse_mdy <- function(d) {
  out <- as.IDate(d, format = "%m/%d/%Y")
  stopifnot(sum(is.na(out) & !is.na(d)) == 0)
  out
}
parse_num <- function(v) {
  out <- suppressWarnings(as.numeric(v))
  stopifnot(sum(is.na(out) & !is.na(v)) == 0)
  out
}

# Normalization with caches shared across years (each distinct value is normalized once).
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
                                                                 abbs = usps_city, states = c("MI", "DC", "MICHIGAN"),
                                                                 na = invalid_city, na_rep = TRUE))
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
