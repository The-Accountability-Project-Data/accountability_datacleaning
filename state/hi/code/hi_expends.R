# Hawaii campaign expenditures (TAP dataset 136), November 2026: expenditures by candidates (3maa-4fgr) and by
# noncandidate committees (riiu-7d4b; new in this dataset), reports from 2015 on, plus the earlier build's candidate
# expenditures dated before 2015. The earlier build kept only normalized street and ZIP code (address_norm,
# zip_norm) and the city as published (city_raw); for its rows those are address_1, zip_code and city here. New
# expenditures dated before 2015 that match an earlier-build row (same candidate, vendor, date and amount, ignoring letter case) are left
# out; the rest are kept. See hi_common.R.
#   Rscript state/hi/code/hi_expends.R   (from the accountability_datacleaning root)
source(here::here("state", "hi", "code", "hi_common.R"))
out_dir <- dir_create(here("state", "hi", "expends", "data", "clean"))
W <- here("state", "hi", "data")   # raw/ (downloads) and old/ (earlier build)
SRC <- c("candidate_name", "committee_name", "vendor_type", "vendor_name", "date", "amount", "authorized_use",
         "expenditure_category", "purpose_of_expenditure", "independent_expenditure", "candidates_named",
         "support_oppose", "address_1", "address_2", "city", "state", "zip_code", "office", "district", "county",
         "party", "reg_no", "election_period", "mapping_location", "inoutstate")
cand <- read_csv_text(path(W, "raw", "3maa-4fgr.csv")); print(names(cand))
comm <- read_csv_text(path(W, "raw", "riiu-7d4b.csv")); print(names(comm))
setnames(comm, c("noncandidate_committee_name", "candidate_name_s"), c("committee_name", "candidates_named"), skip_absent = TRUE)
setnames(cand, "location_1", "mapping_location", skip_absent = TRUE); setnames(comm, "location_1", "mapping_location", skip_absent = TRUE)
new <- rbind(cand, comm, fill = TRUE)
if (!all(names(new) %in% SRC)) stop("unexpected columns: ", paste(setdiff(names(new), SRC), collapse = ", "))
new[, source := "2026"]
old <- fread(path(W, "old", "hi_expends_clean.csv"), colClasses = "character", na.strings = "")
setnames(old, c("address_norm", "zip_norm", "city_raw", "in_out_state"), c("address_1", "zip_code", "city", "inoutstate"))
old <- old[, intersect(SRC, names(old)), with = FALSE]
for (j in names(old)) { v <- old[[j]]; i <- which(!is.na(v) & trimws(v) == ""); if (length(i)) set(old, i = i, j = j, value = NA_character_) }
for (j in names(old)) { v <- old[[j]]; i <- which(grepl("[\r\n]", v)); if (length(i)) set(old, i = i, j = j, value = str_squish(v[i])) }   # line breaks in fields -> space
old[, source := "earlier"]; for (j in setdiff(SRC, names(old))) set(old, j = j, value = NA_character_)
d_new <- parse_hi_date(new$date); d_old <- parse_hi_date(old$date)
cut <- as.IDate("2015-01-01")
U <- function(v) toupper(str_squish(v))   # the earlier expenditures build upper-cased names
key <- function(x, d) paste(U(fcoalesce(x$candidate_name, x$committee_name)), U(x$vendor_name), d, round(as.numeric(x$amount), 2), sep = "\r")
keep_old <- !is.na(d_old) & d_old < cut
old_pre <- old[keep_old]; k_old <- key(old_pre, d_old[keep_old])
new_pre <- !is.na(d_new) & d_new < cut
matched <- new_pre & key(new, d_new) %chin% k_old
cat("earlier build:", nrow(old), "rows;", nrow(old_pre), "dated before 2015 kept;", sum(is.na(d_old)), "undated (not kept)\n")
cat("new:", nrow(new), "rows (candidates", nrow(cand), ", noncandidate committees", nrow(comm), ");", sum(new_pre),
    "dated before 2015, of which", sum(matched), "match an earlier-build row (left out),", sum(new_pre & !matched), "kept\n")
x <- rbind(old_pre, new[!matched], fill = TRUE)
setcolorder(x, c(SRC, "source"))
LAYOUT <- c(SRC, "source", "spender_name", "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")
x[, spender_name := fcoalesce(committee_name, candidate_name)]
build_hi(x, "date", "amount", "vendor_name", "spender_name",
         c("address_1", "address_2", "city", "state", "zip_code"), LAYOUT, "hi_expends", out_dir)
