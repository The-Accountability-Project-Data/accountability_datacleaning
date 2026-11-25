# Shared code for the New Mexico campaign finance builds (nm_contribs.R, nm_expends.R), November 2026.
#
# Source: New Mexico Secretary of State, Campaign Finance Information System (https://login.cfis.sos.state.nm.us),
# Data Download: yearly files of contributions and loans (CON_<year>.csv) and expenditures (EXP_<year>.csv) by
# transaction year, 2020-2026, downloaded 2026-11-23 and joined by state/nm/code/reparse.py into
# state/nm/data/parsed/nm_<contribs|expends>.csv. This system holds reports filed in it, from 2020 on.
# Transactions filed in the earlier CFIS (no transaction ID; through the June 2020 reports) come from our 2021 build
# (csv/nm_contribs_2000-20210817.csv, csv/nm_expends_2000-20210817.csv), as published then, with their clean columns;
# that build's rows from the current system (with an ID) are replaced by the new files.
#
# Reading: every column as text, blank -> missing; letter case and everything else as published. Amounts -> numbers;
# transaction dates M/D/YYYY h:mm:ss AM (new) or YYYY-MM-DDThh:mm:ssZ (2021 build; the date part) -> YYYY-MM-DD.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
parse_nm_date <- function(v) {
  d <- sub("[ T].*$", "", v)
  out <- fifelse(grepl("^\\d{4}-", d), as.IDate(d, format = "%Y-%m-%d"), as.IDate(d, format = "%m/%d/%Y"))
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
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("NM", "NEW MEXICO"),
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

blank_na <- function(x) { for (j in names(x)) { v <- x[[j]]; i <- which(!is.na(v) & trimws(v) == ""); if (length(i)) set(x, i = i, j = j, value = NA_character_) }; invisible(x) }
U <- function(v) str_squish(toupper(gsub("[^A-Za-z0-9]+", " ", fcoalesce(v, ""))))   # for matching: case and punctuation ignored
OLD <- here("state", "nm", "data", "old")   # the earlier build files

# The whole build for one side.
#   new: parsed file; old: 2021 build file. id, date, amount, year: column names. name: the counterparty name
#   columns (a row with all of them missing has no name). addr: c(addr1, addr2, city, state, zip) of the counterparty.
#   drop_noname: leave out rows with no counterparty name (contributions). Layout = the 2021 build's columns.
build_nm <- function(new, old, id, date, amount, year, name, addr, drop_noname, stem, out_dir) {
  x <- fread(new, colClasses = "character", na.strings = "", encoding = "UTF-8"); blank_na(x)
  setnames(x, "orgid", "org_id"); x[, file_year := NULL]
  o <- fread(path(OLD, old), colClasses = "character", na.strings = "", encoding = "UTF-8"); blank_na(o)
  layout <- copy(names(o)); src <- copy(names(x))   # copy: names() grows by reference
  stopifnot(all(src %in% layout))
  cat("new:", nrow(x), " earlier build:", nrow(o), "\n")
  x[, d := parse_nm_date(get(date))]; o[, d := parse_nm_date(get(date))]
  # earlier build: keep the earlier system's rows (no ID), any date, and rows with an ID dated before 2020
  keep <- is.na(o[[id]]) | (!is.na(o$d) & o$d < as.IDate("2020-01-01"))
  cat("earlier build rows from the current system (ID, 2020 on), replaced:", sum(!keep), "\n")
  o <- o[keep]
  # ... except those that match a new row (candidate or committee, counterparty, date, amount)
  who <- function(z) U(fcoalesce(z$candidate_last_name, z$committee_name))
  nm <- function(z) U(do.call(paste, lapply(name, function(j) fcoalesce(z[[j]], ""))))
  k <- function(z) paste(who(z), nm(z), z$d, round(as.numeric(z[[amount]]), 2))
  hit <- k(o) %chin% k(x)
  cat("earlier rows kept:", nrow(o), "; matching a new row (left out):", sum(hit), "\n")
  print(o[!hit, .N, keyby = .(y = year(d) >= 2020)])
  o <- o[!hit]
  noname <- function(z) Reduce(`&`, lapply(name, function(j) is.na(z[[j]])))
  if (drop_noname) {
    cat("no counterparty name, left out: new", sum(noname(x)), " earlier", sum(noname(o)), "\n")
    x <- x[!noname(x)]; o <- o[!noname(o)]
  }
  # new rows: parse, flag, clean
  set(x, j = date, value = x$d); x[, d := NULL]
  set(x, j = amount, value = parse_amount(x[[amount]]))
  x[, dupe_flag := duplicated(x, by = setdiff(src, id)) | duplicated(x, by = setdiff(src, id), fromLast = TRUE)]
  clean_party(x, addr, c("address_clean", "city_clean", "state_clean", "zip_clean"))
  # earlier rows: as published then, with their clean columns and dupe_flag
  set(o, j = date, value = o$d); o[, d := NULL]
  set(o, j = amount, value = as.numeric(o[[amount]]))
  o[, dupe_flag := dupe_flag == "TRUE"]
  x <- rbind(x, o, fill = TRUE)
  x[, na_flag := is.na(get(date)) | is.na(get(amount)) | noname(x) | (is.na(committee_name) & is.na(candidate_last_name))]
  set(x, j = year, value = year(x[[date]]))
  stopifnot(all(layout %in% names(x)))
  setorderv(x, date, na.last = TRUE)   # undated rows last (previews show the first rows)
  cat("rows", nrow(x), " na_flag", sum(x$na_flag), " dupe_flag", sum(x$dupe_flag), " date missing", sum(is.na(x[[date]])), "\n")
  print(x[, .N, keyby = c(year)], nrows = 100)
  yrs <- x[!is.na(get(year)), .N, keyby = c(year)]
  f <- path(out_dir, sprintf("%s_%d-%d.csv", stem, min(yrs[N >= 100][[year]]), max(yrs[[year]][yrs[[year]] <= 2026])))
  fwrite(x[, ..layout], f, na = "", dateTimeAs = "ISO")
  cat("wrote", f, nrow(x), "rows,", length(layout), "columns, dates", format(min(x[[date]], na.rm = TRUE)), "to",
      format(max(x[[date]], na.rm = TRUE)), "\n")
  invisible(x)
}
