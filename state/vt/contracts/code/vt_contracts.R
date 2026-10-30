# Copied 2026-10-30 from the datacleaning_agents repo (datasets/333-vermont-contracts/vt_contracts.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Dataset 333, Vermont contracts (Vermont Vendor Payments) — full rebuild 2026-10-14 (not uploaded).
# Follows accountability_datacleaning/state/vt/contracts/docs/vt_contracts_diary.Rmd, with these changes:
#   - source read as the full current export (data.vermont.gov 786x-sbp3 rows.tsv, 2,588,462 rows, quarters
#     2009-09-30 .. 2026-06-30), read as the diary did (default quoting: some values are CSV-quoted inside the TSV,
#     e.g. "Montpelier Broadcasting-WRJT ""The Point""", and come out unquoted; row count checked = 2,588,462);
#   - the diary's "Update" step (anti_join against the 2020 file to keep only new rows) is NOT run: this is a full
#     replacement of both current files (vt_contracts_clean.csv + vt_contracts_20200611-20230209.csv);
#   - Canadian province abbreviations are listed inline instead of scraped from ncbi.nlm.nih.gov (NBK7254);
#   - the export's trailing grand-total line is dropped; 1 payment without a quarter is kept (year blank) and the
#     diary's na_flag column is not added (positional mapping, 19 columns);
#   - 25 vendor names whose accented letter is U+FFFD in the current export are restored from the current files;
#   - campfin 1.0.11 from CRAN (the diary installed it from GitHub); no plots.
# The source has no amendment / superseded flag. Output columns = the current files' 19-column header, same order
# (the mapping is positional).
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(lubridate); library(fs)
  library(campfin); library(janitor)
})
base <- path_expand("~/uc_berkeley/datacleaning_agents/work/333-vermont-contracts")
raw_tsv <- path(base, "raw", "rows.tsv")

vtc <- read_delim(raw_tsv, delim = "\t", name_repair = make_clean_names,
                  locale = locale(date_format = "%m/%d/%Y"), progress = FALSE,
                  col_types = cols(.default = col_character(), quarter_ending = col_date(), amount = col_number()))
stopifnot(nrow(vtc) == 2588462)
message("read ", format(nrow(vtc), big.mark = ","), " rows x ", ncol(vtc), " cols: ", paste(names(vtc), collapse = ", "))
# The export ends with a grand-total line (only an amount, $1,445,153,228.60): not a payment, dropped.
total_line <- is.na(vtc$quarter_ending) & is.na(vtc$department) & is.na(vtc$vendor)
message("grand-total line(s) dropped: ", sum(total_line), " (amount ", paste(vtc$amount[total_line], collapse = ", "), ")")
vtc <- vtc[!total_line, ]

# The current export has U+FFFD (replacement character) where some vendor names had accented letters
# ("Belle's Caf\uFFFD"; the 2020/2023 files have "Belle's Caf\u00e9"). Restore them from the current files: same
# vendor_number, and the old name equals the new one with each U+FFFD standing for one character. Only exact,
# unambiguous matches are used.
old_names <- bind_rows(lapply(dir_ls(path(base, "old"), glob = "*.csv"), function(f)
  read_csv(f, col_types = cols(.default = col_character()), col_select = c(vendor_number, vendor), progress = FALSE))) %>%
  distinct() %>% filter(!str_detect(vendor, "^[\\x01-\\x7f]*$"))
bad <- which(str_detect(vtc$vendor, "\uFFFD"))
fixed <- 0
for (i in bad) {
  pat <- paste0("^", str_replace_all(str_escape(vtc$vendor[i]), "\uFFFD", "."), "$")
  cand <- unique(old_names$vendor[old_names$vendor_number == vtc$vendor_number[i] & str_detect(old_names$vendor, pat)])
  if (length(cand) == 1) { vtc$vendor[i] <- cand; fixed <- fixed + 1 }
}
message("vendor names with U+FFFD: ", length(bad), "; restored from the current files: ", fixed)

key_vars <- c("quarter_ending", "department", "amount", "vendor")
vtc <- flag_na(vtc, all_of(key_vars))
message("na_flag: ", sum(vtc$na_flag))
# The diary keeps na_flag when it is non-zero, but the mapping is positional and the current files have no na_flag
# column, so the row(s) are kept (year blank) and the flag column is not added.
if (sum(vtc$na_flag) > 0) print(select(filter(vtc, na_flag), all_of(key_vars)))
vtc <- select(vtc, -na_flag)

vtc <- flag_dupes(vtc, everything())
message("dupe_flag: ", sum(vtc$dupe_flag), sprintf(" (%.2f%%)", 100 * mean(vtc$dupe_flag)))

vtc$amount <- round(vtc$amount, digits = 2)
vtc <- mutate(vtc, year = year(quarter_ending))
vtc <- mutate(vtc, dept_state = "VT", .after = department)

ca_prov <- c("AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT")
valid_state2 <- unique(c(ca_prov, valid_state))
vtc <- mutate(vtc, state_norm = normal_state(state = state, abbreviate = TRUE, na_rep = TRUE, valid = valid_state2))

usps_city2 <- tibble::add_row(usps_city, abb = "ST", full = "SAINT")
vtc <- mutate(vtc, city_norm = city %>% str_replace("(?<=\\w)\\.(?=\\w)", " ") %>%
                normal_city(abbs = usps_city2, states = c("VT", "DC", "VERMONT"), na = invalid_city, na_rep = TRUE))

vtc <- vtc %>% rename_all(~str_replace(., "_norm", "_clean")) %>% rename_all(~str_remove(., "_raw"))
want <- c("quarter_ending", "department", "dept_state", "unit_no", "vendor_number", "vendor", "city", "state",
          "dept_id_description", "dept_id", "amount", "account", "acct_no", "fund_description", "fund", "dupe_flag",
          "year", "state_clean", "city_clean")
stopifnot(setequal(names(vtc), want))
vtc <- vtc[want]

out <- path(base, "clean", sprintf("vt_contracts_%d-%d.csv", min(vtc$year, na.rm = TRUE), max(vtc$year, na.rm = TRUE)))
write_csv(vtc, out, na = "")
message("wrote ", out, ": ", format(nrow(vtc), big.mark = ","), " rows")
print(count(vtc, year), n = Inf)
