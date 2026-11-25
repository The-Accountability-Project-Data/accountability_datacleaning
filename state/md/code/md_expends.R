# Maryland campaign expenditures (TAP dataset 328), November 2026: every transaction in the MDCRIS "Expenditures &
# Outstanding Obligations" files (filing years 2021-2026), plus the earlier builds' expenditures dated before
# 2020-12-01 (the new system matches them from December 2020; for January-November 2020 it has only part).
# New expenditures dated before 2020-12-01 that match an earlier row (same date and amount, and the new payee or
# vendor equals the earlier payee, or the committee names are equal; case and punctuation ignored) are left out; the
# rest are kept (mostly January-June 2020, filed after the earlier build was made in July 2020). Earlier rows keep their clean address columns; their payee address is
# one field (in payee_address1). See md_common.R.
#   Rscript state/md/code/md_expends.R   (from the accountability_datacleaning root)
source(here::here("state", "md", "code", "md_common.R"))
out_dir <- dir_create(here("state", "md", "expends", "data", "clean"))
OLD <- here("state", "md", "data", "old")   # the earlier build files
CUT <- as.IDate("2020-12-01")
x <- fread(here("state", "md", "data", "parsed", "md_expenditures.csv"), colClasses = "character", na.strings = "", encoding = "UTF-8")
blank_na(x); cat("new:", nrow(x), "rows\n")
setnames(x, c("payee_mailing_address1", "payee_mailing_address2", "payee_zip_code", "vendor_mailing_address1",
              "vendor_mailing_address2", "vendor_zip_code", "transaction_date", "transaction_amount"),
         c("payee_address1", "payee_address2", "payee_zip", "vendor_address1", "vendor_address2", "vendor_zip", "date", "amount"))
x[, payee_name := name_of(payee_company_name, payee_last_name, payee_first_name, payee_middle_name)]
x[, source := "2026"]
o <- rbind(fread(path(OLD, "md_expends_clean.csv"), colClasses = "character", na.strings = ""),
           fread(path(OLD, "md_expends_clean_202007-202306.csv"), colClasses = "character", na.strings = ""))
blank_na(o)
o[, d := parse_md_date(date)]
cat("earlier:", nrow(o), "rows;", o[d < CUT, .N], "dated before", format(CUT), "kept;", o[is.na(d), .N], "undated kept;",
    o[d >= CUT, .N], "later (dropped)\n")
o <- o[is.na(d) | d < CUT]
setnames(o, c("payee", "address", "type", "committee", "vendor", "fundtype", "comments", "addr_clean", "toward", "method"),
         c("payee_name", "payee_address1", "payee_type", "committee_name", "vendor_name", "fund_type", "description",
           "address_clean", "earlier_toward", "earlier_method"))
o[, source := "earlier"]
dn <- parse_md_date(x$date)
k <- function(n, d, a) paste(U(n), d, round(as.numeric(gsub("[$,]", "", a)), 2))
po <- k(o$payee_name, o$d, o$amount); co <- k(o$committee_name, o$d, o$amount)
pre <- !is.na(dn) & dn < CUT
hit <- pre & (k(x$payee_name, dn, x$amount) %chin% po | k(x$vendor_name, dn, x$amount) %chin% po |
              k(x$committee_name, dn, x$amount) %chin% co)
cat("new dated before", format(CUT), ":", sum(pre), "; match an earlier row (left out):", sum(hit), "; kept:", sum(pre & !hit), "\n")
x <- x[!hit]
# new rows: parse, flag, clean
src <- copy(names(x))
x[, date := parse_md_date(date)]; x[, amount := parse_amount(amount)]
x[, na_flag := is.na(date) | is.na(amount) | is.na(payee_name) | is.na(committee_name)]
x[, dupe_flag := duplicated(x, by = src) | duplicated(x, by = src, fromLast = TRUE)]
clean_party(x, c("payee_address1", "payee_address2", "payee_city", "payee_state", "payee_zip"),
            c("address_clean", "city_clean", "state_clean", "zip_clean"))
# earlier rows: as published then, with their clean columns
o[, date := d][, d := NULL]; o[, amount := as.numeric(amount)]
o[, na_flag := is.na(date) | is.na(amount) | is.na(payee_name) | is.na(committee_name)]
o[, dupe_flag := dupe_flag == "TRUE"]
o[, year := NULL]
x <- rbind(x, o, fill = TRUE)
x[, year := year(date)]
LAYOUT <- c(setdiff(src, "source"), "earlier_toward", "earlier_method", "source", "na_flag", "dupe_flag", "year",
            "address_clean", "city_clean", "state_clean", "zip_clean")
stopifnot(all(LAYOUT %in% names(x)))
setorder(x, date)
cat("rows", nrow(x), " na_flag", sum(x$na_flag), " dupe_flag", sum(x$dupe_flag), "\n")
print(x[, .N, keyby = .(year, source)][year >= 2017 & year <= 2022])
f <- path(out_dir, sprintf("md_expends_%d-%d.csv", min(x[, .N, by = year][N >= 100, year]), max(x$year, na.rm = TRUE)))
fwrite(x[, ..LAYOUT], f, na = "", dateTimeAs = "ISO")
cat("wrote", f, nrow(x), "rows,", length(LAYOUT), "columns, dates", format(min(x$date, na.rm = TRUE)), "to", format(max(x$date, na.rm = TRUE)), "\n")
