# Hawaii campaign contributions (TAP dataset 407), November 2026: contributions received by candidates (jexd-xbcg)
# and by noncandidate committees (rajm-32md), reports from 2015 on, plus the earlier build's contributions dated
# before 2015 (the open data no longer has the reports filed before 2015). New contributions dated before 2015 that
# match an earlier-build row (same recipient, contributor, date and amount, ignoring letter case) are left out; the rest are kept.
# See hi_common.R.   Rscript state/hi/code/hi_contribs.R   (from the accountability_datacleaning root)
source(here::here("state", "hi", "code", "hi_common.R"))
out_dir <- dir_create(here("state", "hi", "contribs", "data", "clean"))
W <- here("state", "hi", "data")   # raw/ (downloads) and old/ (earlier build)
SRC <- c("candidate_name", "committee_name", "contributor_type", "contributor_name", "date", "amount", "aggregate",
         "employer", "occupation", "address_1", "address_2", "city", "state", "zip_code", "non_resident_yes_or_no",
         "non_monetary_yes_or_no", "non_monetary_category", "non_monetary_description", "office", "district", "county",
         "party", "reg_no", "election_period", "mapping_address", "inoutstate", "range")
cand <- read_csv_text(path(W, "raw", "jexd-xbcg.csv")); print(names(cand))
comm <- read_csv_text(path(W, "raw", "rajm-32md.csv")); print(names(comm))
setnames(comm, c("noncandidate_committee_name", "mapping_location"), c("committee_name", "mapping_address"), skip_absent = TRUE)
setnames(cand, "mapping_location", "mapping_address", skip_absent = TRUE)
new <- rbind(cand, comm, fill = TRUE)
stopifnot(all(names(new) %in% SRC))
new[, source := "2026"]
old <- fread(path(W, "old", "hi_contribs_clean.csv"), colClasses = "character", na.strings = "")
old <- old[, ..SRC]
for (j in names(old)) { v <- old[[j]]; i <- which(!is.na(v) & trimws(v) == ""); if (length(i)) set(old, i = i, j = j, value = NA_character_) }
for (j in names(old)) { v <- old[[j]]; i <- which(grepl("[\r\n]", v)); if (length(i)) set(old, i = i, j = j, value = str_squish(v[i])) }   # line breaks in fields -> space
old[, source := "earlier"]
d_new <- parse_hi_date(new$date); d_old <- parse_hi_date(old$date)
cut <- as.IDate("2015-01-01")
U <- function(v) toupper(str_squish(v))   # the earlier expenditures build upper-cased names
key <- function(x, d) paste(U(fcoalesce(x$candidate_name, x$committee_name)), U(x$contributor_name), d,
                            round(as.numeric(x$amount), 2), sep = "\r")
old_pre <- old[!is.na(d_old) & d_old < cut]
k_old <- key(old_pre, d_old[!is.na(d_old) & d_old < cut])
new_pre <- !is.na(d_new) & d_new < cut
matched <- new_pre & key(new, d_new) %chin% k_old
cat("earlier build: ", nrow(old), "rows;", nrow(old_pre), "dated before 2015 kept;", sum(is.na(d_old)), "undated (not kept)\n")
cat("new: ", nrow(new), "rows;", sum(new_pre), "dated before 2015, of which", sum(matched), "match an earlier-build row (left out),",
    sum(new_pre & !matched), "kept\n")
x <- rbind(old_pre, new[!matched], fill = TRUE)
setcolorder(x, c(SRC, "source"))
print(x[, .N, keyby = .(source, y = substr(fifelse(grepl("^\\d{4}-", date), date, sub("^\\d\\d/\\d\\d/", "", date)), 1, 4))][, dcast(.SD, y ~ source, value.var = "N")])
LAYOUT <- c(SRC, "source", "recipient_name", "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")
x[, recipient_name := fcoalesce(committee_name, candidate_name)]
build_hi(x, "date", "amount", "contributor_name", "recipient_name",
         c("address_1", "address_2", "city", "state", "zip_code"), LAYOUT, "hi_contribs", out_dir)
