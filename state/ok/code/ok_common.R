# Shared code for the Oklahoma campaign finance builds (ok_build.R), November 2026.
#
# Source: Oklahoma Ethics Commission, Guardian "Data Download" (https://guardian.ok.gov/PublicSite/DataDownload.aspx;
# "extracted ... as it existed as of 11/14/2026"), downloaded 2026-11-17:
# <year>_ContributionLoanExtract.csv and <year>_ExpenditureExtract.csv, 2014-2026, 23 columns each, the same header
# in every year.
# Reading: every field is wrapped in quotes and records end with CRLF, but quotes inside values are not escaped
# ("1627 I" STREET, NW", "W C BILL" SELLERS, INC") and values can hold line breaks. So the text is split into records
# at '"<CRLF>"' and each record into fields at '","' (the outer quotes removed); every record must have 23 fields.
# Values are kept as published (no unescaping). Files are windows-1252 except 2014 (UTF-8); each record is decoded as
# UTF-8 when valid and as windows-1252 otherwise.
# Amended: "Y/N indicator to show if an amendment was filed for this record" (file layout PDF); the export holds one
# version of each record (IDs unique), so all rows are kept.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
read_extract <- function(path) {
  raw <- readBin(path, "raw", file.size(path))
  txt <- rawToChar(raw); Encoding(txt) <- "bytes"
  txt <- sub("\r\n$", "", txt, useBytes = TRUE)
  recs <- strsplit(txt, "\"\r\n\"", fixed = FALSE, useBytes = TRUE)[[1]]
  ok8 <- validUTF8(recs)
  Encoding(recs) <- "unknown"
  recs[!ok8] <- iconv(recs[!ok8], from = "windows-1252", to = "UTF-8")
  Encoding(recs) <- "UTF-8"
  recs[1] <- sub("^\ufeff", "", recs[1]); recs[1] <- sub("^\"", "", recs[1])
  n <- length(recs); recs[n] <- sub("\"$", "", recs[n])
  # strsplit drops one trailing empty piece, so a separator is appended to keep a last empty field
  f <- strsplit(paste0(recs, '","'), '","', fixed = TRUE)
  k <- lengths(f); h <- f[[1]]
  bad <- which(k != length(h))
  if (length(bad)) stop(basename(path), ": records without ", length(h), " fields: ", paste(head(bad), collapse = ","))
  x <- as.data.table(do.call(rbind, f[-1])); setnames(x, h)
  for (j in names(x)) set(x, i = which(x[[j]] == ""), j = j, value = NA_character_)
  cat(basename(path), nrow(x), "rows;", sum(!ok8), "windows-1252 records\n")
  x
}
snake <- function(h) gsub("_+", "_", gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(h))))
parse_mdy <- function(v) {
  out <- as.IDate(v, format = "%m/%d/%Y")
  bad <- sum(is.na(out) & !is.na(v)); if (bad) cat("  dates not parsed:", bad, head(unique(v[is.na(out) & !is.na(v)])), "\n")
  out
}
parse_amount <- function(v) {
  out <- suppressWarnings(as.numeric(gsub("[$,]", "", v)))
  bad <- sum(is.na(out) & !is.na(v)); if (bad) cat("  amounts not parsed:", bad, head(unique(v[is.na(out) & !is.na(v)])), "\n")
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
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("OK", "DC", "OKLAHOMA"),
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
