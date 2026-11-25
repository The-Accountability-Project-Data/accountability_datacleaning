# Shared code for the Missouri campaign finance builds (mo_contribs.R, mo_expends.R), November 2026.
#
# Source: the Missouri Ethics Commission "Export to CSV" page (https://www.mec.mo.gov/MEC/Campaign_Finance/CF_ContrCSV.aspx),
# downloaded 2026-11-17: one file per year 2011-2026 for "Itemized Contributions
# Received - Form CD1 Part A" and "Itemized Expenditures Over $100 - Form CD3 Part B". UTF-8, CRLF, every field quoted.
# The CD1_A / CD3_B IDs are unique across all years (no year overlaps another).
# Amended reports ("AMENDED July Quarterly Report", ...) hold only the changed items: 196 of 47,834 contribution rows and
# 31 of 22,633 expenditure rows on them repeat a row of the original report, so all rows are kept.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
read_year_files <- function(raw, form) {
  fs <- sort(dir_ls(raw, regexp = paste0("/mo_", form, "_\\d{4}\\.csv$")))
  x <- rbindlist(lapply(fs, function(f) {
    y <- fread(f, colClasses = "character", na.strings = "", encoding = "UTF-8", showProgress = FALSE)
    # every field is quoted, and fread keeps a quoted "" as an empty string: blank -> missing
    for (j in names(y)) set(y, i = which(y[[j]] == ""), j = j, value = NA_character_)
    cat(basename(f), nrow(y), "rows\n"); y
  }), use.names = TRUE)
  setnames(x, gsub("_+", "_", gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(names(x))))))
  x
}
# "12/13/2024 12:00:00 AM" -> IDate
parse_mec_date <- function(v) {
  out <- as.IDate(sub(" .*$", "", v), format = "%m/%d/%Y")
  bad <- sum(is.na(out) & !is.na(v)); if (bad) cat("  dates not parsed:", bad, head(unique(v[is.na(out) & !is.na(v)])), "\n")
  out
}
parse_amount <- function(v) {
  out <- suppressWarnings(as.numeric(v))
  bad <- sum(is.na(out) & !is.na(v)); if (bad) cat("  amounts not parsed:", bad, head(unique(v[is.na(out) & !is.na(v)])), "\n")
  out
}
na_blank <- function(v) { v[!is.na(v) & trimws(v) == ""] <- NA_character_; v }

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
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("MO", "DC", "MISSOURI"),
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
