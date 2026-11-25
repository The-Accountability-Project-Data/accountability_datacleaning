# Shared code for the Kansas campaign finance builds (ks_contribs.R, ks_expends.R), November 2026.
#
# Source: Kansas Secretary of State campaign finance viewer (https://kssos.org/elections/cfr_viewer/,
# cfr_examiner_contribution.aspx and cfr_examiner_expenditure.aspx; statewide candidates), as in the earlier builds.
# Searched by calendar year and exported ("CLICK HERE TO EXPORT THE RESULTS": an HTML table saved as .xls) on
# 2026-11-20; each export's rows matched the
# search's "N record(s) found". state/ks/code/reparse.py takes every value from its labeled span (lblCandName,
# lblContributor, lblAddress, ...) into state/ks/data/parsed/ks_<contribution|expenditure>.csv.
#
# Reading: every column as text, blank -> missing. Letter case and everything else as published. Amounts "$1,283.55"
# -> 1283.55; dates MM/DD/YYYY -> YYYY-MM-DD.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
read_ks <- function(path, rename) {
  x <- fread(path, colClasses = "character", na.strings = "", encoding = "UTF-8", showProgress = FALSE)
  stopifnot(all(rename %in% names(x)))
  x <- x[, ..rename]; setnames(x, names(rename))
  for (j in names(x)) {
    v <- x[[j]]
    i <- which(!is.na(v) & trimws(v) == ""); if (length(i)) set(x, i = i, j = j, value = NA_character_)
    i <- which(grepl("[\r\n]", v))
    if (length(i)) set(x, i = i, j = j, value = str_squish(v[i]))
  }
  cat(basename(path), ":", nrow(x), "rows\n")
  x
}
parse_ks_date <- function(v) {
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
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("KS", "DC", "KANSAS"),
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


# The whole build for one side, one output file <stem>_<first year>-<last year>.csv.
build_ks <- function(path, rename, amount_cols, date_cols, name_col, layout, stem, out_dir) {
  x <- read_ks(path, rename)
  src <- copy(names(x))            # copy: data.table names() grows by reference as columns are added
  for (j in date_cols) set(x, j = j, value = parse_ks_date(x[[j]]))
  for (j in amount_cols) set(x, j = j, value = parse_amount(x[[j]]))
  # missing value = no amount in any of amount_cols (in-kind contributions have only in_kind_amount)
  no_value <- Reduce(`&`, lapply(amount_cols, function(j) is.na(x[[j]])))
  x[, na_flag := is.na(date) | no_value | is.na(get(name_col)) | is.na(cand_name)]
  x[, dupe_flag := duplicated(x, by = src) | duplicated(x, by = src, fromLast = TRUE)]
  x[, year := year(date)]
  clean_party(x, c("address", "address2", "city", "state", "zip"), c("address_clean", "city_clean", "state_clean", "zip_clean"))
  stopifnot(all(layout %in% names(x)))
  setorder(x, date)
  cat("rows", nrow(x), " na_flag", sum(x$na_flag), " dupe_flag", sum(x$dupe_flag), " date missing", sum(is.na(x$date)), "\n")
  print(x[, .N, keyby = year], nrows = 100)
  yrs <- x[!is.na(year), .N, keyby = year]
  y0 <- min(yrs[N >= 100, year]); y1 <- max(yrs$year)
  f <- path(out_dir, sprintf("%s_%d-%d.csv", stem, y0, y1))
  fwrite(x[, ..layout], f, na = "", dateTimeAs = "ISO")
  cat("wrote", f, nrow(x), "rows,", length(layout), "columns, dates", format(min(x$date, na.rm = TRUE)), "to", format(max(x$date, na.rm = TRUE)), "\n")
  invisible(x)
}
