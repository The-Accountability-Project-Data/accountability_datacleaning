# Shared code for the Vermont campaign finance builds (vt_contribs.R, vt_expends.R), November 2026.
#
# Source: Vermont Secretary of State, Campaign Finance System (https://campaignfinance.vermont.gov/). Filing years
# 2014-2025 from the "Download Data" page; filing year 2026 (not there yet) from the public search's JSON, by
# transaction-date window. Downloaded 2026-11-21.
# state/vt/code/reparse.py joins lines broken inside fields, regroups records with stray quotes and puts the search
# records in the download's columns, into state/vt/data/parsed/vt_<receipts|expenditures>.csv (header names in snake
# case, plus filing_year and source).
#
# Reading: every column as text, blank -> missing; letter case and everything else as published. Amounts
# "$1,283.55" -> 1283.55; dates "9/11/2014 12:00:00 AM" or "11/14/2026" -> YYYY-MM-DD.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
read_vt <- function(path, rename) {
  x <- fread(path, colClasses = "character", na.strings = "", encoding = "UTF-8", showProgress = FALSE)
  stopifnot(all(rename %in% names(x)), ncol(x) == length(rename))
  x <- x[, ..rename]; setnames(x, names(rename))
  for (j in names(x)) {
    v <- x[[j]]
    i <- which(!is.na(v) & trimws(v) == ""); if (length(i)) set(x, i = i, j = j, value = NA_character_)
  }
  cat(basename(path), ":", nrow(x), "rows\n")
  x
}
parse_vt_date <- function(v) {
  out <- as.IDate(sub(" .*$", "", v), format = "%m/%d/%Y")
  bad <- sum(is.na(out) & !is.na(v)); if (bad) cat("  dates not parsed:", bad, head(unique(v[is.na(out) & !is.na(v)])), "\n")
  out
}
parse_amount <- function(v) {
  neg <- grepl("^\\s*\\(.*\\)\\s*$", v) | grepl("-", v)
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
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("VT", "DC", "VERMONT"),
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

# The whole build for one side. Writes <stem>_<first year with 100+ rows>-<last year>.csv.
#   date_col, amount_col: parsed in place. name_col / to_cols: na_flag when the name or all of to_cols are missing.
#   addr: c(addr1, addr2, city, state, zip) source columns for the clean address columns.
build_vt <- function(x, date_col, amount_col, name_col, to_cols, addr, layout, stem, out_dir) {
  src <- setdiff(copy(names(x)), "transaction_id")   # dupe_flag on every column but the ID (copy: names() grows by reference)
  set(x, j = date_col, value = parse_vt_date(x[[date_col]]))
  set(x, j = amount_col, value = parse_amount(x[[amount_col]]))
  no_to <- Reduce(`&`, lapply(to_cols, function(j) is.na(x[[j]])))
  x[, na_flag := is.na(get(date_col)) | is.na(get(amount_col)) | is.na(get(name_col)) | no_to]
  x[, dupe_flag := duplicated(x, by = src) | duplicated(x, by = src, fromLast = TRUE)]
  x[, year := year(get(date_col))]
  clean_party(x, addr, c("address_clean", "city_clean", "state_clean", "zip_clean"))
  stopifnot(all(layout %in% names(x)))
  setorderv(x, date_col)
  cat("rows", nrow(x), " na_flag", sum(x$na_flag), " dupe_flag", sum(x$dupe_flag), " date missing", sum(is.na(x[[date_col]])), "\n")
  print(x[, .N, keyby = year], nrows = 100)
  yrs <- x[!is.na(year), .N, keyby = year]
  y0 <- min(yrs[N >= 100, year]); y1 <- max(yrs$year)
  f <- path(out_dir, sprintf("%s_%d-%d.csv", stem, y0, y1))
  fwrite(x[, ..layout], f, na = "", dateTimeAs = "ISO")
  cat("wrote", f, nrow(x), "rows,", length(layout), "columns, dates", format(min(x[[date_col]], na.rm = TRUE)), "to",
      format(max(x[[date_col]], na.rm = TRUE)), "\n")
  invisible(x)
}

# One row per transaction_id. The download repeats a transaction once for each version of the contributor's or
# payee's contact record (other columns identical; same report), in an order that carries no meaning, and has no
# column saying which version is current. Among the copies: a copy with a name rather than "Under Threshold - Name
# Withheld" (1,585 contributions have both); then the copy whose street, city and ZIP code equal the same name's
# address on their latest transaction that is not repeated; failing that, the first copy in the file, which is an
# arbitrary choice.
#   name_cols: c(last, first); addr_cols: c(address1, city, zip).
pick_one <- function(x, name_cols, addr_cols, date_col) {
  WH <- "Under Threshold - Name Withheld"
  x[, row_i__ := .I]
  x[, n_id__ := .N, by = transaction_id]
  x[, d__ := as.IDate(sub(" .*$", "", get(date_col)), format = "%m/%d/%Y")]
  key <- function(d, cols) do.call(paste, c(lapply(cols, function(j) fcoalesce(d[[j]], "")), sep = "\r"))
  x[, who__ := key(x, name_cols)]
  x[, where__ := key(x, addr_cols)]
  x[, all__ := key(x, setdiff(names(x), c("row_i__", "n_id__", "d__", "who__", "where__")))]
  x[, named__ := !is.na(get(name_cols[1])) & str_squish(get(name_cols[1])) != WH]
  latest <- x[n_id__ == 1 & !is.na(d__)][order(who__, -d__, -row_i__)][, .(where_latest__ = where__[1]), by = who__]
  x[latest, where_latest__ := i.where_latest__, on = "who__"]
  x[, match__ := n_id__ > 1 & !is.na(where_latest__) & where__ == where_latest__]
  x[, pick__ := {
    if (.N == 1) TRUE else {
      cand <- if (any(named__)) named__ else rep(TRUE, .N)
      k <- which(cand & match__); k <- if (length(k)) k[1] else which(cand)[1]
      seq_len(.N) == k
    }
  }, by = transaction_id]
  g <- x[n_id__ > 1, .(identical = uniqueN(all__) == 1, mixed = any(named__) && !all(named__),
                       matched = any(match__ & (named__ | !any(named__)))), by = transaction_id]
  cat("repeated transaction_id:", nrow(g), "ids on", x[n_id__ > 1, .N], "rows; rows left out:", x[pick__ == FALSE, .N], "\n")
  cat("  identical copies:", g[identical == TRUE, .N], " differing:", g[identical == FALSE, .N],
      "(named vs withheld:", g[mixed == TRUE, .N], "; latest-address copy kept:", g[identical == FALSE & matched == TRUE, .N],
      "; first copy kept, arbitrary:", g[identical == FALSE & matched == FALSE & mixed == FALSE, .N], ")\n")
  out <- x[pick__ == TRUE]
  out[, c("row_i__", "n_id__", "d__", "who__", "where__", "all__", "named__", "where_latest__", "match__", "pick__") := NULL]
  out[]
}
