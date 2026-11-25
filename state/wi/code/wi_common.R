# Shared code for the Wisconsin campaign finance builds (wi_contribs.R, wi_expends.R), November 2026.
#
# Source: Sunshine, the Wisconsin Ethics Commission's campaign finance system (https://campaignfinance.wi.gov/, which
# replaced CFIS in 2026), Browse Data > Transactions > "Download Results > Download as CSV", fetched 2026-11-18 in
# transaction-date windows of at most 90,000 rows (the site allows 99,999 per download):
# wi_transactions_<from|start>_<to|end>.csv. Every file's row count
# matched the site's count for its window. UTF-8, LF, no BOM, 61 columns. Contributions and disbursements come
# together in one list (column "Transaction Type"); the history from CFIS was migrated into Sunshine.
#
# Amendments: Sunshine returns transactions as they now stand (each has one stable ID; an amended report changes the
# transaction in place), so there are no superseded rows to drop.
#
# Reading: every column as text, blank -> missing. Line breaks inside a field (Registrant Address is
# "street\ncity, ST zip"; some comments) become a space; in Reports (one report per line) they become "; ". Columns renamed to snake case; the two contributor columns
# "Contributor Entity ID (-> Related Payer Entity ID if applicable)" and "Contributor Name (-> Related Payer Name if
# applicable)" become contributor_entity_id and contributor_name. Everything else as published (including the
# migration's "MISSING" address placeholders and the committee's current ballot event on old rows).
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
SOURCE_COLS <- 61L
TYPES <- c("Contribution", "Conduit Contribution", "Disbursement")

snake <- function(x) gsub("_+", "_", gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(x))))

# All window files, keeping only the rows whose Transaction Type is in `types`.
read_wi <- function(raw, types) {
  fs <- sort(dir_ls(raw, regexp = "/wi_transactions_[^/]+\\.csv$"))
  if (!length(fs)) stop("no wi_transactions_*.csv in ", raw)
  seen <- list()
  x <- rbindlist(lapply(fs, function(f) {
    y <- fread(f, colClasses = "character", na.strings = "", encoding = "UTF-8", showProgress = FALSE)
    if (ncol(y) != SOURCE_COLS) stop(basename(f), ": ", ncol(y), " columns")
    seen[[basename(f)]] <<- y[, .N, by = `Transaction Type`]
    y[`Transaction Type` %chin% types]
  }), use.names = TRUE)
  tt <- rbindlist(seen)[, .(N = sum(N)), by = `Transaction Type`]
  cat(length(fs), "files; transaction types in all files:\n"); print(tt)
  other <- setdiff(tt$`Transaction Type`, TYPES)
  if (length(other)) stop("unknown transaction types: ", paste(other, collapse = ", "))
  nm <- names(x)
  nm[startsWith(nm, "Contributor Entity ID")] <- "contributor_entity_id"
  nm[startsWith(nm, "Contributor Name")] <- "contributor_name"
  setnames(x, snake(nm))
  for (j in names(x)) {
    v <- x[[j]]
    i <- which(!is.na(v) & trimws(v) == ""); if (length(i)) set(x, i = i, j = j, value = NA_character_)
    i <- which(grepl("[\r\n]", v))
    if (length(i)) {
      cat("  line breaks replaced in", j, ":", length(i), "\n")
      sep <- if (j == "reports") "; " else " "     # reports: one report per line -> "; "
      set(x, i = i, j = j, value = str_squish(gsub("\\s*(\r\n|\r|\n)\\s*", sep, trimws(v[i]))))
    }
  }
  if (anyDuplicated(x$id)) stop("duplicate transaction IDs: ", sum(duplicated(x$id)))
  x
}
# "10/16/2026" -> IDate
parse_wi_date <- function(v) {
  out <- as.IDate(v, format = "%m/%d/%Y")
  bad <- sum(is.na(out) & !is.na(v)); if (bad) cat("  dates not parsed:", bad, head(unique(v[is.na(out) & !is.na(v)])), "\n")
  out
}
parse_amount <- function(v) {
  out <- suppressWarnings(as.numeric(gsub("[$,]", "", v)))
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
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("WI", "DC", "WISCONSIN"),
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
# <prefix>_address_clean (address 1 + 2), _zip_clean, _state_clean, _city_clean for one party.
clean_party <- function(x, p) {
  a1 <- x[[paste0(p, "_address_1")]]; a2 <- x[[paste0(p, "_address_2")]]
  set(x, j = paste0(p, "_address_clean"), value = norm_address(na_blank(str_squish(paste(fcoalesce(a1, ""), fcoalesce(a2, ""))))))
  set(x, j = paste0(p, "_zip_clean"), value = norm_zip(x[[paste0(p, "_zip")]]))
  set(x, j = paste0(p, "_state_clean"), value = norm_state(x[[paste0(p, "_state")]]))
  cn <- norm_city(x[[paste0(p, "_city")]])
  sw <- do_city_swap(cn, x[[paste0(p, "_state_clean")]], x[[paste0(p, "_zip_clean")]])
  set(x, j = paste0(p, "_city_clean"), value = do_refine(sw, x[[paste0(p, "_state_clean")]], x[[paste0(p, "_zip_clean")]]))
  invisible(x)
}
CLEAN <- function(p) paste0(p, c("_address_clean", "_city_clean", "_state_clean", "_zip_clean"))

# The whole build for one side: read, parse, flag, clean both parties, write two parts split at CUT (rows dated through
# the end of 2022 -- or undated -- and rows from 2023 on), so the newer part alone can replace a cut-off old file.
CUT <- as.IDate("2023-01-01")
build_wi <- function(raw, types, stem, out_dir) {
  x <- read_wi(raw, types)
  src <- copy(names(x))            # copy: data.table names() grows by reference as columns are added
  cat("rows:", nrow(x), "\n"); print(x[, .N, keyby = .(transaction_type, transaction_category)], nrows = 200)
  x[, date := parse_wi_date(date)]
  x[, amount := parse_amount(amount)]
  x[, na_flag := is.na(date) | is.na(amount) | is.na(contributor_name) | is.na(payee_name)]
  x[, dupe_flag := duplicated(x, by = setdiff(src, "id")) | duplicated(x, by = setdiff(src, "id"), fromLast = TRUE)]
  x[, year := year(date)]
  clean_party(x, "contributor"); clean_party(x, "payee")
  layout <- c(src, "na_flag", "dupe_flag", "year", CLEAN("contributor"), CLEAN("payee"))
  setorder(x, date, id)
  cat("na_flag", sum(x$na_flag), " dupe_flag", sum(x$dupe_flag), " date missing", sum(is.na(x$date)), "\n")
  print(x[, .N, keyby = year], nrows = 100)
  this_year <- year(Sys.Date())
  yrs <- x[!is.na(year), .N, keyby = year]
  y0 <- min(yrs[N >= 1000, year])                  # earliest year with a real number of rows (older ones are typos)
  old <- x[is.na(date) | date < CUT]; new <- x[!is.na(date) & date >= CUT]
  files <- c(sprintf("%s_%d-%d.csv", stem, y0, year(CUT) - 1), sprintf("%s_%d-%d.csv", stem, year(CUT), this_year))
  for (k in 1:2) {
    d <- list(old, new)[[k]]; f <- path(out_dir, files[k])
    fwrite(d[, ..layout], f, na = "", dateTimeAs = "ISO")
    cat("wrote", f, nrow(d), "rows,", length(layout), "columns, dates", format(min(d$date, na.rm = TRUE)), "to",
        format(max(d$date, na.rm = TRUE)), "\n")
  }
  invisible(x)
}
