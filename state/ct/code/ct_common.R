# Shared code for the Connecticut campaign finance builds (ct_contribs.R, ct_expends.R), November 2026.
#
# Source: the SEEC eCRIS "Data Downloads for Current and Previous Years" page
# (https://seec.ct.gov/Portal/eCRIS/CurPreYears), downloaded 2026-11-17: Receipts and Disbursements files per year for
# Party/PAC committees (calendar year) and Candidate/Exploratory committees (election year), 2008-2026, and the older
# CIFS receipts files (1999-2007). CSV where offered; 2022 and 2023 are offered only as XLSX.
# Reading:
# - CSV files are UTF-8 (some with a byte-order mark) or windows-1252; a few windows-1252 files also hold UTF-8 lines,
#   so each line is decoded as UTF-8 when valid and as windows-1252 otherwise.
# - XLSX dates are Excel serial numbers; they are written as m/d/yyyy text, as in the CSV files.
# - All values are read as text; whitespace is squished, as in the earlier build.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here); library(readxl)
})

read_lines_fixed <- function(path) {
  x <- readLines(path, warn = FALSE, encoding = "bytes")
  bad <- !validUTF8(x)
  x[bad] <- iconv(x[bad], from = "windows-1252", to = "UTF-8")
  x <- enc2utf8(x)
  x[1] <- sub("^﻿", "", x[1])
  attr(x, "cp1252_lines") <- sum(bad)
  x
}
# Read one CSV or XLSX file as all-text columns with the source headers.
# header = FALSE: the file has no header line (CIFS 2006); col_names must be given.
read_source <- function(path, header = TRUE, col_names = NULL) {
  if (grepl("\\.xlsx$", path, ignore.case = TRUE)) {
    x <- as.data.table(read_excel(path, col_types = "text", .name_repair = "minimal"))
    serial <- function(v) {
      n <- suppressWarnings(as.numeric(v)); ok <- !is.na(n) & grepl("^\\d+(\\.\\d+)?$", v)
      d <- as.Date(floor(n[ok]), origin = "1899-12-30")
      v[ok] <- sprintf("%d/%d/%d", as.integer(format(d, "%m")), as.integer(format(d, "%d")), as.integer(format(d, "%Y")))
      v
    }
    for (j in grep("Date|File To State|File to State|Period Start|Period End", names(x)))
      set(x, j = j, value = serial(x[[j]]))
    setattr(x, "cp1252_lines", 0L)
  } else {
    l <- read_lines_fixed(path)
    x <- fread(text = paste(l, collapse = "\n"), colClasses = "character", header = header, na.strings = "",
               sep = ",", quote = "\"", fill = FALSE, strip.white = FALSE, encoding = "UTF-8", showProgress = FALSE)
    if (!header) setnames(x, col_names)
    setattr(x, "cp1252_lines", attr(l, "cp1252_lines"))
  }
  # duplicated header names (Description twice in candidate disbursements): the second becomes description_1 later
  for (j in seq_along(x)) if (is.character(x[[j]])) set(x, j = j, value = na_if(str_squish(x[[j]]), ""))
  x
}
na_if <- function(v, w) { v[!is.na(v) & v == w] <- NA_character_; v }
parse_amount <- function(v) {
  neg <- !is.na(v) & (startsWith(v, "-") | startsWith(v, "("))
  out <- suppressWarnings(as.numeric(gsub("[$,()\\-]", "", v)))
  bad <- sum(is.na(out) & !is.na(v))
  if (bad) cat("  amounts not parsed:", bad, head(unique(v[is.na(out) & !is.na(v)])), "\n")
  fifelse(neg, -out, out)
}
parse_mdy <- function(v) {
  out <- as.IDate(v, format = "%m/%d/%Y")
  bad <- sum(is.na(out) & !is.na(v))
  if (bad) cat("  dates not parsed:", bad, head(unique(v[is.na(out) & !is.na(v)])), "\n")
  out
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
norm_state <- function(s) memo("state", s, function(u) normal_state(u, abbreviate = TRUE, na_rep = TRUE, valid = valid_state))
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("CT", "DC", "CONNECTICUT"),
                                                                 na = invalid_city, na_rep = TRUE))
zc <- as.data.table(zipcodes)
# City swap: the ZIP code's city when the normalized city is an abbreviation of it or one edit away; otherwise the
# normalized city (also when the ZIP code has no match).
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
# Refine (key collision + 1-gram merge over the whole column), kept only where the refined city, state and ZIP code
# are a valid combination.
do_refine <- function(swap, state, zip) {
  m <- unique(data.table(city_swap = swap)[!is.na(city_swap)][, city_refine := n_gram_merge(key_collision_merge(city_swap), numgram = 1)])
  m <- unique(m)[city_refine != city_swap]
  combos <- unique(data.table(city_swap = swap, state_norm = state, zip_norm = zip))
  good <- merge(combos, m, by = "city_swap")
  good <- good[zc, on = .(city_refine = city, state_norm = state, zip_norm = zip), nomatch = 0L]
  cat("refine: combinations changed:", nrow(good), "\n")
  q <- data.table(city_swap = swap, state_norm = state, zip_norm = zip)
  out <- good[q, city_refine, on = c("city_swap", "state_norm", "zip_norm"), mult = "first"]
  fcoalesce(out, swap)
}
