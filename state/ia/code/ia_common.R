# Shared code for the Iowa campaign finance builds (ia_contribs.R, ia_expends.R), November 2026.
#
# Source: Iowa Ethics and Campaign Disclosure Board data on the Iowa Data Hub (data.iowa.gov left Socrata):
# dataset 917 "Iowa Campaign Contributions Received" (four CSV parts) and 918 "Iowa Campaign Expenditures",
# https://idh-be.iowa.gov/api/v1/datasets/<id>/rows.csv (a zip), both updated 2026-11-21, downloaded 2026-11-22. The
# data may not be used for commercial
# purposes (Iowa Code section 68B.32A(7)).
#
# Reading: every column as text, blank -> missing; letter case and everything else as published. Amounts -> numbers;
# dates are YYYY-MM-DD already.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
read_ia <- function(path, rename) {
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
parse_ia_date <- function(v) {
  out <- as.IDate(v, format = "%Y-%m-%d")
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
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("IA", "DC", "IOWA"),
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
build_ia <- function(x, date_col, amount_col, name_col, to_cols, addr, layout, stem, out_dir) {
  src <- copy(names(x))            # copy: data.table names() grows by reference as columns are added
  set(x, j = date_col, value = parse_ia_date(x[[date_col]]))
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
