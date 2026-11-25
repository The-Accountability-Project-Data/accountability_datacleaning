# Shared code for the North Carolina campaign finance builds (nc_contribs.R, nc_expends.R), November 2026.
#
# Source: NC State Board of Elections Advanced Transaction Search (https://cf.ncsbe.gov/CFTxnLkup/AdvancedSearch/),
# rebuilt since the 2022 update: its export is now POST /CFTxnLkup/Export. Fetched 2026-11-20,
# receipts and expenditures SEPARATELY (their transaction type
# names overlap: Debt Payment, Refund/Reimbursement, Building Fund; the 2022 update asked for both at once), in
# transaction-date windows: years before 1990 together, then years, quarters or months. Every window's rows were
# checked against the site's count for that period. UTF-8, 24 columns.
# state/nc/code/reparse.py stacks the windows into state/nc/data/parsed/nc_<receipts|expenditures>.csv; it rejoins
# the 8 expenditure records whose Purpose holds an unquoted line break (split over two lines by the export).
#
# Reading: every column as text, blank -> missing; line breaks inside a field become a space. Columns get the names
# of the earlier builds (con_*/rec_* for contributions, payee_*/comm_* for expenditures). Letter case, "Not
# Available" and "---" placeholders, and everything else as published (the earlier builds uppercased every field).
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
SOURCE_COLS <- c("Name", "Street Line 1", "Street Line 2", "City", "State", "Zip Code", "Profession/Job Title",
                 "Employer's Name/Specific Field", "Transction Type", "Committee Name", "Committee SBoE ID",
                 "Committee Street 1", "Committee Street 2", "Committee City", "Committee State", "Committee Zip Code",
                 "Report Name", "Date Occured", "Account Code", "Amount", "Form of Payment", "Purpose",
                 "Candidate/Referendum Name", "Declaration")

read_nc <- function(path, names) {
  x <- fread(path, colClasses = "character", na.strings = "", encoding = "UTF-8", showProgress = FALSE)
  if (!identical(names(x), c(SOURCE_COLS, "source_file"))) stop(path, ": unexpected header")
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
# "11/02/2026" -> IDate
parse_nc_date <- function(v) {
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
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("NC", "DC", "NORTH CAROLINA"),
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

# The whole build for one side. `names` = the 24 output names for the source columns; `name_cols` = the two party
# name columns for na_flag; `parties` = list(list(src = 5 columns, out = 4 clean columns), ...); `layout` = output
# column order; `extra` = function(x) adding derived columns. Writes two parts split at CUT (rows dated before 2023,
# or undated, and rows from 2023 on).
CUT <- as.IDate("2023-01-01")
build_nc <- function(path, names, name_cols, parties, layout, stem, out_dir, extra = NULL, drop = NULL) {
  x <- read_nc(path, names)
  if (!is.null(drop)) {            # drop(x) -> TRUE for rows left out; logged with their count and amount
    d <- drop(x)
    cat("rows dropped:", sum(d), " amount", format(sum(parse_amount(x$amount[d]), na.rm = TRUE), big.mark = ","), "\n")
    print(x[d, .N, by = c(name_cols[1])][order(-N)])
    x <- x[!d]
  }
  src <- copy(names(x))            # copy: data.table names() grows by reference as columns are added
  print(x[, .N, keyby = .(type = x[[names[9]]])], nrows = 100)
  x[, date := parse_nc_date(date)]
  x[, amount := parse_amount(amount)]
  x[, na_flag := is.na(date) | is.na(amount) | is.na(get(name_cols[1])) | is.na(get(name_cols[2]))]
  x[, dupe_flag := duplicated(x, by = src) | duplicated(x, by = src, fromLast = TRUE)]
  x[, year := year(date)]
  if (!is.null(extra)) extra(x)
  for (p in parties) clean_party(x, p$src, p$out)
  stopifnot(setequal(layout, names(x)))
  setorder(x, date)
  cat("rows", nrow(x), " na_flag", sum(x$na_flag), " dupe_flag", sum(x$dupe_flag), " date missing", sum(is.na(x$date)), "\n")
  print(x[, .N, keyby = year], nrows = 200)
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
