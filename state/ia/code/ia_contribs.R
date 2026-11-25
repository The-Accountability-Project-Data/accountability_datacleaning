# Iowa campaign contributions (TAP dataset 348), November 2026: every row of the Iowa Data Hub's "Iowa Campaign
# Contributions Received" (contributions CON, in-kind INK, loans received LOANREC). 20 rows with no date and no
# committee are left out: pieces of records split in the source (the values sit in the wrong columns). Contributions
# with no contributor name are left out too, as for New Hampshire and Vermont. See ia_common.R.
#   Rscript state/ia/code/ia_contribs.R   (from the accountability_datacleaning root)
source(here::here("state", "ia", "code", "ia_common.R"))
out_dir <- dir_create(here("state", "ia", "contribs", "data", "clean"))
RAW <- here("state", "ia", "data", "raw", "917")
files <- sort(dir_ls(RAW, glob = "*.csv"))
x <- rbindlist(lapply(files, function(f) fread(f, colClasses = "character", na.strings = "", encoding = "UTF-8", showProgress = FALSE)))
cat("read", length(files), "parts:", nrow(x), "rows\n")
for (j in names(x)) { v <- x[[j]]; i <- which(!is.na(v) & trimws(v) == ""); if (length(i)) set(x, i = i, j = j, value = NA_character_) }
setnames(x, "contribution_received_date", "date")
frag <- is.na(x$date) & is.na(x$committee_cd)
cat("fragments left out:", sum(frag), "\n"); x <- x[!frag]
x[, contributor_name := fifelse(!is.na(organization_nm), organization_nm,
                                na_blank(str_squish(paste0(fcoalesce(last_nm, ""), fifelse(is.na(first_nm), "", paste0(", ", first_nm))))))]
noname <- is.na(x$contributor_name)
cat("no contributor name, left out:", sum(noname), "\n"); print(x[noname, .N, keyby = .(transaction_type, has_address = !is.na(address_line_1))])
x <- x[!noname]
SRC <- c("date", "committee_cd", "committee_type", "committee_nm", "transaction_type", "first_nm", "last_nm",
         "address_line_1", "address_line_2", "city", "state", "zip_code", "amount", "check_number", "contr_committee_cd",
         "organization_nm")
stopifnot(all(SRC %in% names(x)))
LAYOUT <- c(SRC, "contributor_name", "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")
build_ia(x, "date", "amount", "contributor_name", "committee_nm",
         c("address_line_1", "address_line_2", "city", "state", "zip_code"), LAYOUT, "ia_contribs", out_dir)
