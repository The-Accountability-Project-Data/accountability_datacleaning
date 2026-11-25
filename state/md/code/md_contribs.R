# Maryland campaign contributions (TAP dataset 355), November 2026: every transaction in the MDCRIS "Contributions &
# Loans" files (filing years 2021-2026; the new system covers transactions from January 2020), plus the earlier
# build's contributions dated before 2020-01-01 (csv/md_contribs_clean.csv). New contributions dated before 2020 that
# match an earlier row (same date and amount, and the same contributor or the same committee; case and punctuation
# ignored) are left out; the rest are kept. Earlier rows keep their clean address columns; their contributor name and
# address are one field each (contributor_name, contributor_address1). Contributions with no contributor name are
# left out, as for New Hampshire, Vermont and Iowa. The new files have no employer or occupation; the earlier rows'
# are kept. Written in two passes (new rows, then earlier rows) to keep memory down. See md_common.R.
#   Rscript state/md/code/md_contribs.R   (from the accountability_datacleaning root)
source(here::here("state", "md", "code", "md_common.R"))
out_dir <- dir_create(here("state", "md", "contribs", "data", "clean"))
OLD <- here("state", "md", "data", "old")   # the earlier build files
CUT <- as.IDate("2020-01-01")
x <- fread(here("state", "md", "data", "parsed", "md_receipts.csv"), colClasses = "character", na.strings = "", encoding = "UTF-8")
blank_na(x); cat("new:", nrow(x), "rows\n")
setnames(x, c("contributor_mailing_address1", "contributor_mailing_address2", "contributor_zipcode",
              "contributor_county_of_residence", "transaction_date", "transaction_amount",
              "number_of_people_purchasing_or_making_contributions", "price_per_person_or_average_contribution",
              "aggregate_as_of_download_date"),
         c("contributor_address1", "contributor_address2", "contributor_zip", "contributor_county", "date", "amount",
           "number_of_people", "price_per_person", "aggregate"))
x[, contributor_name := name_of(contributor_company_name, contributor_last_name, contributor_first_name, contributor_middle_name)]
x[, source := "2026"]
o <- fread(path(OLD, "md_contribs_clean.csv"), colClasses = "character", na.strings = "",
           select = c("committee", "period", "date", "name", "address", "type", "method", "amount", "employer",
                      "occupation", "office", "fund", "dupe_flag", "filing_year", "address_clean", "city_clean",
                      "state_clean", "zip_clean"))
blank_na(o)
o[, d := parse_md_date(date)]
cat("earlier:", nrow(o), "rows;", o[d < CUT, .N], "dated before", format(CUT), "kept;", o[is.na(d), .N], "undated kept;",
    o[d >= CUT, .N], "dated", format(CUT), "or later (dropped; includes", o[d > as.IDate("2026-12-31"), .N], "impossible future dates)\n")
o <- o[is.na(d) | d < CUT]
# match new pre-2020 rows
k <- function(n, d, a) paste(U(n), d, round(as.numeric(gsub("[$,]", "", a)), 2))
no <- k(o$name, o$d, o$amount); cmo <- k(o$committee, o$d, o$amount)
dn <- parse_md_date(x$date); pre <- !is.na(dn) & dn < CUT
nm_plain <- name_of(x$contributor_company_name, x$contributor_last_name, x$contributor_first_name, x$contributor_middle_name, sep = " ")
hit <- pre & (k(nm_plain, dn, x$amount) %chin% no | k(x$committee_name, dn, x$amount) %chin% cmo)
cat("new dated before", format(CUT), ":", sum(pre), "; match an earlier row (left out):", sum(hit), "; kept:", sum(pre & !hit), "\n")
x <- x[!hit]; rm(no, cmo, dn, pre, nm_plain, hit); gc()
cat("no contributor name, left out: new", x[is.na(contributor_name), .N], " earlier", o[is.na(name), .N], "\n")
x <- x[!is.na(contributor_name)]; o <- o[!is.na(name)]
# pass 1: new rows
src <- copy(names(x))
x[, date := parse_md_date(date)]; x[, amount := parse_amount(amount)]
x[, na_flag := is.na(date) | is.na(amount) | is.na(contributor_name) | is.na(committee_name)]
x[, dupe_flag := duplicated(x, by = src) | duplicated(x, by = src, fromLast = TRUE)]
x[, year := year(date)]
clean_party(x, c("contributor_address1", "contributor_address2", "contributor_city", "contributor_state", "contributor_zip"),
            c("address_clean", "city_clean", "state_clean", "zip_clean"))
LAYOUT <- c(setdiff(src, "source"), "earlier_employer", "earlier_occupation", "earlier_office", "source", "na_flag",
            "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")
for (j in setdiff(LAYOUT, names(x))) set(x, j = j, value = NA_character_)
cat("new rows", nrow(x), " na_flag", sum(x$na_flag), " dupe_flag", sum(x$dupe_flag), "\n"); print(x[, .N, keyby = year])
y0 <- 0L; tmp <- path(out_dir, "md_contribs_building.csv")
fwrite(x[, ..LAYOUT], tmp, na = "", dateTimeAs = "ISO")
n_new <- nrow(x); dmax <- max(x$date, na.rm = TRUE); rm(x); gc()
# pass 2: earlier rows
setnames(o, c("committee", "period", "name", "address", "type", "method", "fund", "employer", "occupation", "office"),
         c("committee_name", "report_name", "contributor_name", "contributor_address1", "contributor_type",
           "payment_type", "fund_type", "earlier_employer", "earlier_occupation", "earlier_office"))
o[, date := d][, d := NULL]; o[, amount := as.numeric(amount)]
o[, na_flag := is.na(date) | is.na(amount) | is.na(contributor_name) | is.na(committee_name)]
o[, dupe_flag := dupe_flag == "TRUE"]; o[, year := year(date)]; o[, source := "earlier"]
for (j in setdiff(LAYOUT, names(o))) set(o, j = j, value = NA_character_)
cat("earlier rows", nrow(o), " na_flag", sum(o$na_flag), " dupe_flag", sum(o$dupe_flag), "\n")
yrs <- o[, .N, by = year]; y0 <- min(yrs[N >= 100 & !is.na(year), year])
fwrite(o[, ..LAYOUT], tmp, na = "", dateTimeAs = "ISO", append = TRUE)
n_old <- nrow(o); dmin <- min(o$date, na.rm = TRUE); rm(o); gc()
f <- path(out_dir, sprintf("md_contribs_%d-%d.csv", y0, year(dmax)))
file_move(tmp, f)
cat("wrote", f, n_new + n_old, "rows (", n_new, "new +", n_old, "earlier ),", length(LAYOUT), "columns, dates", format(dmin), "to", format(dmax), "\n")
