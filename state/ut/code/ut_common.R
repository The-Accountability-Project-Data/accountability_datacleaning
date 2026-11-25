# Shared code for the Utah campaign finance builds (ut_contribs.R, ut_expends.R), November 2026.
#
# Source: Utah Lieutenant Governor's financial disclosures (https://disclosures.utah.gov/Search/AdvancedSearch),
# "Download Data by Year": one file per filer entity type (PCC = candidates and office holders, CORP, ELECT, INDEXP,
# LABOR, PAC, PIC, PARTY) and report year, 1998-2026, fetched 2026-11-20 (as in
# the earlier builds). Each file holds every transaction on
# that type's reports for that year, contributions and expenditures together (TRAN_TYPE).
# state/ut/code/reparse.py stacks the files into state/ut/data/parsed/ut_transactions.csv (ENTITY_NAME = the
# file's second column, the filer; ENTITY_TYPE and REPORT_YEAR from the file name) and rebuilds the records broken
# by unescaped quotes or line breaks inside fields.
#
# Reading: every column as text, blank -> missing; line breaks inside a field become a space. Letter case, quotes
# inside fields, the "X" flags (FILED, INKIND, LOAN) and everything else as published. AMENDS holds the TRAN_ID of the
# transaction an amendment replaces; the replaced transactions are not in the download, so every row is current.
suppressPackageStartupMessages({
  library(data.table); library(campfin); library(refinr); library(stringr); library(fs); library(here)
})
SOURCE_COLS <- c("FILED", "ENTITY_NAME", "REPORT", "TRAN_ID", "TRAN_TYPE", "TRAN_DATE", "TRAN_AMT", "INKIND", "LOAN",
                 "AMENDS", "NAME", "PURPOSE", "ADDRESS1", "ADDRESS2", "CITY", "STATE", "ZIP", "INKIND_COMMENTS",
                 "ENTITY_TYPE", "REPORT_YEAR")
read_ut <- function(path, type) {
  x <- fread(path, colClasses = "character", na.strings = "", encoding = "UTF-8", showProgress = FALSE)
  if (!identical(names(x), SOURCE_COLS)) stop(path, ": unexpected header")
  print(x[, .N, keyby = TRAN_TYPE])
  x <- x[TRAN_TYPE == type]
  for (j in names(x)) {
    v <- x[[j]]
    i <- which(!is.na(v) & trimws(v) == ""); if (length(i)) set(x, i = i, j = j, value = NA_character_)
    i <- which(grepl("[\r\n]", v))
    if (length(i)) {
      cat("  line breaks replaced in", j, ":", length(i), "\n")
      set(x, i = i, j = j, value = str_squish(gsub("\\s*(\r\n|\r|\n)\\s*", " ", v[i])))
    }
  }
  if (anyDuplicated(x$TRAN_ID)) stop("duplicate TRAN_ID: ", sum(duplicated(x$TRAN_ID)))
  cat(type, ":", nrow(x), "rows\n")
  x
}
parse_ut_date <- function(v) {
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
norm_city <- function(c) memo("city", c, function(u) normal_city(u, abbs = usps_city, states = c("UT", "DC", "UTAH"),
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
# Clean columns: src = c(addr1, addr2, city, state, zip), out = c(addr, city, state, zip).
clean_party <- function(x, src, out) {
  set(x, j = out[1], value = norm_address(na_blank(str_squish(paste(fcoalesce(x[[src[1]]], ""), fcoalesce(x[[src[2]]], ""))))))
  set(x, j = out[4], value = norm_zip(x[[src[5]]]))
  set(x, j = out[3], value = norm_state(x[[src[4]]]))
  cn <- norm_city(x[[src[3]]])
  sw <- do_city_swap(cn, x[[out[3]]], x[[out[4]]])
  set(x, j = out[2], value = do_refine(sw, x[[out[3]]], x[[out[4]]]))
  invisible(x)
}


# The whole build for one side: `rename` = named vector new = old source name; `cols` = the output names of the
# date, amount, year, filer name and counterparty name; `party` = clean-column spec; one output file.
build_ut <- function(path, type, rename, cols, party, layout, stem, out_dir) {
  x <- read_ut(path, type)
  x <- x[, ..rename]; setnames(x, names(rename))
  src <- copy(names(x))            # copy: data.table names() grows by reference as columns are added
  set(x, j = cols[["date"]], value = parse_ut_date(x[[cols[["date"]]]]))
  set(x, j = cols[["amount"]], value = parse_amount(x[[cols[["amount"]]]]))
  x[, na_flag := is.na(get(cols[["date"]])) | is.na(get(cols[["amount"]])) | is.na(get(cols[["name"]])) | is.na(get(cols[["filer"]]))]
  x[, dupe_flag := duplicated(x, by = setdiff(src, cols[["id"]])) | duplicated(x, by = setdiff(src, cols[["id"]]), fromLast = TRUE)]
  set(x, j = cols[["year"]], value = year(x[[cols[["date"]]]]))
  clean_party(x, party$src, party$out)
  stopifnot(all(layout %in% names(x)))
  setorderv(x, c(cols[["date"]], cols[["id"]]))
  cat("rows", nrow(x), " na_flag", sum(x$na_flag), " dupe_flag", sum(x$dupe_flag), " date missing", sum(is.na(x[[cols[["date"]]]])), "\n")
  print(x[, .N, keyby = c(cols[["year"]])], nrows = 200)
  ry <- range(as.integer(x[[cols[["report_year"]]]]), na.rm = TRUE)
  f <- path(out_dir, sprintf("%s_%d-%d.csv", stem, ry[1], ry[2]))
  fwrite(x[, ..layout], f, na = "", dateTimeAs = "ISO")
  cat("wrote", f, nrow(x), "rows,", length(layout), "columns, report years", ry[1], "to", ry[2], "\n")
  invisible(x)
}
