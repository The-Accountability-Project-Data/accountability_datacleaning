# Iowa campaign expenditures (TAP dataset 174), November 2026: every row of the Iowa Data Hub's "Iowa Campaign
# Expenditures" (expenditures EXP, loan repayments LOANREP). 19 rows with no date and no committee are left out:
# pieces of records split in the source. See ia_common.R.
#   Rscript state/ia/code/ia_expends.R   (from the accountability_datacleaning root)
source(here::here("state", "ia", "code", "ia_common.R"))
out_dir <- dir_create(here("state", "ia", "expends", "data", "clean"))
RAW <- here("state", "ia", "data", "raw", "918")
x <- fread(dir_ls(RAW, glob = "*.csv")[1], colClasses = "character", na.strings = "", encoding = "UTF-8", showProgress = FALSE)
cat("read:", nrow(x), "rows\n")
for (j in names(x)) { v <- x[[j]]; i <- which(!is.na(v) & trimws(v) == ""); if (length(i)) set(x, i = i, j = j, value = NA_character_) }
setnames(x, c("calendar_date", "state_cd"), c("date", "state"))
frag <- is.na(x$date) & is.na(x$committee_cd)
cat("fragments left out:", sum(frag), "\n"); x <- x[!frag]
x[, payee_name := fifelse(!is.na(organization_nm), organization_nm,
                          na_blank(str_squish(paste0(fcoalesce(last_nm, ""), fifelse(is.na(first_nm), "", paste0(", ", first_nm))))))]
SRC <- c("date", "transaction_type", "committee_cd", "committee_type", "committee_nm", "organization_nm", "first_nm",
         "last_nm", "address_line_1", "address_line_2", "city", "state", "zip_code", "amount", "check_number",
         "rec_committee_cd")
stopifnot(all(SRC %in% names(x)))
LAYOUT <- c(SRC, "payee_name", "na_flag", "dupe_flag", "year", "address_clean", "city_clean", "state_clean", "zip_clean")
build_ia(x, "date", "amount", "payee_name", "committee_nm",
         c("address_line_1", "address_line_2", "city", "state", "zip_code"), LAYOUT, "ia_expends", out_dir)
