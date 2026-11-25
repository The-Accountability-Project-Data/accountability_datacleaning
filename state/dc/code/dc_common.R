# Shared code for the DC campaign finance builds (dc_contribs.R, dc_expends.R), November 2026.
#
# Source: DC Office of Campaign Finance, Contribution and Expenditure Search
# (https://efiling.ocf.dc.gov/ContributionExpenditure), all filer types, Excel export ("Export > Excel"), fetched
# 2026-11-20 in calendar-year windows
# (2003-2026; nothing dated before 2003 or after 2026). The Excel export is used because the CSV export leaves out
# Payee Organization Name. state/dc/code/reparse.py turns the workbooks into state/dc/data/parsed/
# dc_<contributions|expenditures>.csv. Totals match DC's open data layers (opendata.dc.gov "Campaign Financial
# Contributions" / "Expenditures", updated 2026-11-16) within a week of filings (309,865 vs 309,787; 126,120 vs
# 126,043). The open data is not used: whole-dollar amounts and no committee on expenditures.
#
# Reading: every column as text, blank -> missing; line breaks inside a field become a space. Letter case and
# everything else as published. Amounts "$1,234.50" -> 1234.5 (parentheses = negative); dates MM/DD/YYYY ->
# YYYY-MM-DD.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
read_dc <- function(path, source_cols, names) {
  x <- fread(path, colClasses = "character", na.strings = "", encoding = "UTF-8", showProgress = FALSE)
  if (!identical(names(x), c(source_cols, "source_file"))) stop(path, ": unexpected header: ", paste(names(x), collapse = ", "))
  x[, source_file := NULL]
  setnames(x, names)
  for (j in names(x)) {
    v <- x[[j]]
    i <- which(!is.na(v) & trimws(v) == ""); if (length(i)) set(x, i = i, j = j, value = NA_character_)
    i <- which(grepl("[\r\n]", v))
    if (length(i)) {
      cat("  line breaks replaced in", j, ":", length(i), "\n")
      set(x, i = i, j = j, value = str_squish(gsub("\\s*(\r\n|\r|\n)\\s*", " ", v[i])))
    }
  }
  cat(basename(path), ":", nrow(x), "rows\n")
  x
}
parse_dc_date <- function(v) {
  out <- as.IDate(v, format = "%m/%d/%Y")
  bad <- sum(is.na(out) & !is.na(v)); if (bad) cat("  dates not parsed:", bad, head(unique(v[is.na(out) & !is.na(v)])), "\n")
  out
}
parse_amount <- function(v) {
  neg <- grepl("^\\s*\\(.*\\)\\s*$", v) | grepl("^\\s*-", v)
  out <- suppressWarnings(as.numeric(gsub("[$,()\\s-]", "", v)))
  out <- ifelse(neg, -out, out)
  bad <- sum(is.na(out) & !is.na(v)); if (bad) cat("  amounts not parsed:", bad, head(unique(v[is.na(out) & !is.na(v)])), "\n")
  out
}
na_blank <- function(v) { v[!is.na(v) & trimws(v) == ""] <- NA_character_; v }
# "First Middle Last", or the organization name when there is no person's name.
full_name <- function(first, middle, last, org) {
  person <- na_blank(str_squish(paste(fcoalesce(first, ""), fcoalesce(middle, ""), fcoalesce(last, ""))))
  fcoalesce(person, org)
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
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("DC", "MD", "VA", "DISTRICT OF COLUMBIA"),
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
# Clean columns for one party: src = c(addr1, addr2, city, state, zip), out = c(addr, city, state, zip).
clean_party <- function(x, src, out) {
  set(x, j = out[1], value = norm_address(na_blank(str_squish(paste(fcoalesce(x[[src[1]]], ""), fcoalesce(x[[src[2]]], ""))))))
  set(x, j = out[4], value = norm_zip(x[[src[5]]]))
  set(x, j = out[3], value = norm_state(x[[src[4]]]))
  cn <- norm_city(x[[src[3]]])
  sw <- do_city_swap(cn, x[[out[3]]], x[[out[4]]])
  set(x, j = out[2], value = do_refine(sw, x[[out[3]]], x[[out[4]]]))
  invisible(x)
}

# Clean columns for one party: src = c(street, city, state, zip), out = c(addr, city, state, zip).
clean_party <- function(x, src, out) {
  set(x, j = out[1], value = norm_address(x[[src[1]]]))
  set(x, j = out[4], value = norm_zip(x[[src[4]]]))
  set(x, j = out[3], value = norm_state(x[[src[3]]]))
  cn <- norm_city(x[[src[2]]])
  sw <- do_city_swap(cn, x[[out[3]]], x[[out[4]]])
  set(x, j = out[2], value = do_refine(sw, x[[out[3]]], x[[out[4]]]))
  invisible(x)
}
# The whole build for one side, written as one file <stem>_<first year>-<last year>.csv.
build_dc <- function(path, source_cols, names, date_col, year_col, name_col, committee_col, party, layout, stem, out_dir, extra) {
  x <- read_dc(path, source_cols, names)
  src <- copy(names(x))            # copy: data.table names() grows by reference as columns are added
  set(x, j = date_col, value = parse_dc_date(x[[date_col]]))
  x[, amount := parse_amount(amount)]
  extra(x)
  x[, na_flag := is.na(get(date_col)) | is.na(amount) | is.na(get(name_col)) | is.na(get(committee_col))]
  x[, dupe_flag := duplicated(x, by = src) | duplicated(x, by = src, fromLast = TRUE)]
  set(x, j = year_col, value = year(x[[date_col]]))
  clean_party(x, party$src, party$out)
  stopifnot(setequal(layout, names(x)))
  setorderv(x, date_col)
  cat("rows", nrow(x), " na_flag", sum(x$na_flag), " dupe_flag", sum(x$dupe_flag), " date missing", sum(is.na(x[[date_col]])), "\n")
  print(x[, .N, keyby = c(year_col)], nrows = 100)
  yrs <- range(x[[year_col]], na.rm = TRUE)
  f <- path(out_dir, sprintf("%s_%d-%d.csv", stem, yrs[1], yrs[2]))
  fwrite(x[, ..layout], f, na = "", dateTimeAs = "ISO")
  cat("wrote", f, nrow(x), "rows,", length(layout), "columns\n")
  invisible(x)
}
