# Copied 2026-10-30 from the datacleaning_agents repo (datasets/369-417-mn-campaign-finance/mn_contribs.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Dataset 369, Minnesota campaign contributions -- rebuild 2015-2026, 2026-10-28 (NOT uploaded; would replace DataFile
# 1210 mn_contribs_clean.csv). Run from the datacleaning_agents repo root:
#   Rscript datasets/369-417-mn-campaign-finance/mn_contribs.R
#
# Follows accountability_datacleaning state/mn/contribs/docs/mn_contribs_diary.Rmd ("Update: October 2026"):
# - Source: CFB "Contributions received by all entities - 2015 to present"
#   (https://cfb.mn.gov/reports-and-data/self-help/data-downloads/campaign-finance/?download=-2113865252), retrieved
#   2026-10-28 (retrievals.jsonl), UTF-8, full history regenerated from the board's database at each download.
# - Changes from the 2023 run: Receipt date is now ISO (was m/d/Y); reader read_cfb() in mn_common.R (RFC quoting
#   plus the export's backslash-quotes, kept as published -- see there); **year = calendar year of the receipt date** (user decision
#   2026-10-28; the diary kept the source's report Year).
# - Unchanged: clean_names, receipt_date -> date, in_kind "Yes" -> TRUE, na_flag (date, contributor, amount,
#   recipient), dupe_flag (all columns), ZIP -> city/state join (contrib_city_match / contrib_state_match). The
#   source has no street address (never did).
# - Output: same 19 columns, same order as the old file.
# Superseded records: the download has no amendment flag; the board's database keeps only current versions of
# amended reports, so 0 rows are dropped as superseded.
here::i_am("datasets/369-417-mn-campaign-finance/mn_contribs.R")
source(here::here("datasets", "369-417-mn-campaign-finance", "mn_common.R"))
raw_csv <- path(raw_dir, "download_-2113865252_contribs_all.csv")

mnc <- read_cfb(raw_csv, expected_records = 654449, col_types = cols(
  .default = col_character(),
  `Recipient reg num` = col_integer(),
  `Amount` = col_double(),
  `Receipt date` = col_date("%Y-%m-%d"),
  `Year` = col_integer(),
  `Contrib Reg Num` = col_integer()
))

mnc <- mnc %>%
  clean_names(case = "snake") %>%
  rename(date = receipt_date, source_year = year) %>%
  mutate(in_kind = (in_kind == "Yes"))
stopifnot(!anyNA(mnc$date))

# year = calendar year of the receipt date (was the source's report Year)
mnc <- mutate(mnc, year = as.integer(year(date)))
chg <- mnc %>% filter(year != source_year)
cat("rows whose year changes (source Year != year(date)):", nrow(chg), "\n")
print(count(chg, source_year, year), n = 50)
write_csv(chg %>% count(source_year, year, month = month(date)), path(out_dir, "mn_contribs_year_changes.csv"))
mnc <- mnc %>% select(-source_year) %>% relocate(year, .after = date)

key_vars <- c("date", "contributor", "amount", "recipient")
mnc <- flag_na(mnc, all_of(key_vars))
mnc <- flag_dupes(mnc, everything())
cat("na_flag:", sum(mnc$na_flag), " dupe_flag:", sum(mnc$dupe_flag), "\n")

pre_names <- names(mnc)
n0 <- nrow(mnc)
mnc <- mnc %>%
  left_join(zipcodes, by = c("contrib_zip" = "zip")) %>%
  rename_with(.fn = ~glue("contrib_{.}_match"), .cols = setdiff(names(.), pre_names))
stopifnot(nrow(mnc) == n0)

old_hdr <- names(read_csv(path(base, "old", "mn_contribs_clean.csv"), n_max = 0, col_types = cols(.default = "c")))
stopifnot(identical(names(mnc), old_hdr))
cat("dates", format(min(mnc$date)), "..", format(max(mnc$date)), "\n")
print(count(mnc, year), n = 50)

clean_csv <- path(out_dir, "mn_contribs_2015-2026.csv")
write_csv(mnc, clean_csv, na = "")
cat("wrote", clean_csv, file_size(clean_csv), "\n")
