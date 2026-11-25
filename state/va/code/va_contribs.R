# Virginia campaign contributions -- rebuild 2012-2026, November 2026 (replaces va_contribs_clean.csv and
# va_contribs_clean_202011-202302.csv).
#   Rscript state/va/code/va_contribs.R from the repo root. Put the monthly folders (data/raw/<YYYY_MM>/Report.csv,
#   ScheduleA.csv, ScheduleB.csv) in state/va/contribs/data/raw/ and the previous published files in data/old/; run
#   python3 state/va/code/reparse.py state/va/contribs first. Output: state/va/contribs/data/clean/.
#
# Follows state/va/contribs/docs/va_contribs_diary.Rmd ("Update: November 2026"):
# - Source: https://apps.elections.virginia.gov/SBE_CSV/CF/, every monthly folder 2012_03 to 2026_11, retrieved
#   2026-11-14/15. The state regenerates every month's files daily, so this is a full re-download, not an increment.
# - Schedule A (direct contributions) and B (in-kind), joined to Report on ReportId.
# - Changes from the 2023 run: transactions on superseded (amended) reports are dropped (see va_common.R); quotes
#   inside fields are kept as published (the diary turned them into apostrophes); the files are read as
#   windows-1252.
#   The city swap keeps the normalized city when the ZIP code has no match (the diary's condition blanked those
#   cities: 5-10% of rows in the earlier contributions files).
# - Unchanged: column names; con_id = Schedule A or B ID; con_name = prefix, first, middle, last, suffix;
#   dupe_flag on every column but con_id; na_flag (con_name, date, amount, fil_name); year = year(date); addresses with
#   normal_address(); ZIPs with normal_zip(); cities normalized, swapped with the ZIP code's city, and (contributors
#   only) refined where the refined city/state/ZIP is valid.
# - Output: the columns of va_contribs_clean_202011-202302.csv, in its order.
# Superseded records (2026-11-15 run): 38,738 superseded report versions; dropped 1,177,060 Schedule A and 38,583
# Schedule B rows. Output 4,507,303 rows.
library(here)
here::i_am("state/va/code/va_contribs.R")
va_dataset <- "contribs"
source(here("state", "va", "code", "va_common.R"))
file_delete(path(out_dir, "superseded_dropped.tsv")[file_exists(path(out_dir, "superseded_dropped.tsv"))])
write_lines("schedule\trows\tsuperseded_dropped", path(out_dir, "superseded_dropped.tsv"))

sa <- drop_superseded(read_parsed("va_schedulea.csv"), "ScheduleA")
sb <- drop_superseded(read_parsed("va_scheduleb.csv"), "ScheduleB")
vac <- bind_rows(sa, sb)
rm(sa, sb); gc()

vac <- vac %>%
  clean_names("snake") %>%
  rename(
    rpt_id = report_id, last_name = last_or_company_name, fil_id = committee_contact_id,
    emp_name = name_of_employer, occupation = occupation_or_type_of_business,
    emp_place = primary_city_and_state_of_employment_or_business, state = state_code, zip = zip_code,
    addr1 = address_line1, addr2 = address_line2, date = transaction_date, total = total_to_date,
    sched_a = schedule_a_id, sched_b = schedule_b_id, valuation = valuation_basis, product = product_or_service
  ) %>%
  select(-report_uid, -schedule_id) %>%
  mutate(
    is_individual = is_individual == "True",
    date = parse_txn_date(date),
    amount = as.numeric(amount),
    total = as.numeric(total),
    con_id = coalesce(sched_a, sched_b)
  )
stopifnot(!any(duplicated(na.omit(vac$sched_a))), !any(duplicated(na.omit(vac$sched_b))),
          all(is.na(vac$sched_a) != is.na(vac$sched_b)))
vac <- vac %>%
  select(-sched_a, -sched_b)
# Schedule A and B IDs are separate sequences, so con_id is unique within a schedule, not across them.
stopifnot(!anyNA(vac$con_id))
cat("con_id values shared by an A and a B row:", sum(duplicated(vac$con_id)), "\n")

vac <- flag_dupes(vac, -con_id)
cat("dupe_flag:", sum(vac$dupe_flag), "\n")

# Report (filer) fields
dt <- function(x) floor_date(ymd_hms(x, quiet = TRUE, truncated = 3), "second")
rpt <- rpt_raw %>%
  filter(ReportId %in% current_rpt) %>%
  clean_names("snake") %>%
  rename_with(~str_replace(., "^committee_", "fil_")) %>%
  rename_with(~str_replace(., "^submitter_", "fil_")) %>%
  rename(
    rpt_id = report_id, is_stwide = is_state_wide, is_assembly = is_general_assembly, cand_name = candidate_name,
    is_final = is_final_report, addr1 = address_line1, addr2 = address_line2, state = state_code, zip = zip_code,
    is_amend = is_amendment, amend_count = amendment_count, office = office_sought,
    elect_start = election_cycle_start_date, elect_end = election_cycle_end_date,
    referendum_date = date_of_referendum
  ) %>%
  mutate(
    across(c(is_stwide, is_assembly, is_local, is_final, no_activity), ~ .x == "True"),
    across(c(filing_date, start_date, end_date, elect_start, elect_end, referendum_date, submitted_date, due_date), dt),
    amend_count = as.integer(amend_count)
  )

n0 <- nrow(vac)
vac <- left_join(vac, rpt, by = "rpt_id", suffix = c("_con", "_fil"), relationship = "many-to-one")
stopifnot(nrow(vac) == n0)
vac <- vac %>%
  rename_with(~ paste0("con_", str_remove(., "_con$")), ends_with("_con")) %>%
  rename_with(~ paste0("fil_", str_remove(., "_fil$")), ends_with("_fil"))

vac <- vac %>%
  unite(con_name, prefix, first_name, middle_name, last_name, suffix, sep = " ", na.rm = TRUE, remove = FALSE) %>%
  mutate(across(where(is.character), ~ na_if(.x, ""))) %>%
  flag_na(con_name, date, amount, fil_name) %>%
  mutate(year = year(date))
cat("na_flag:", sum(vac$na_flag), "\n")

# Wrangle
vac <- vac %>%
  mutate(
    con_addr_clean = norm_addr(vac, c("con_addr1", "con_addr2")),
    fil_addr_clean = norm_addr(vac, c("fil_addr1", "fil_addr2")),
    con_zip_clean = normal_zip(con_zip, na_rep = TRUE),
    fil_zip_clean = normal_zip(fil_zip, na_rep = TRUE),
    con_city_norm = normal_city(con_city, abbs = usps_city, states = c("VA", "DC", "VIRGINIA"), na = invalid_city,
                                na_rep = TRUE),
    fil_city_norm = normal_city(fil_city, abbs = usps_city, states = c("VA", "DC", "VIRGINIA"), na = invalid_city,
                                na_rep = TRUE),
    con_city_swap = city_swap(con_city_norm, con_state, con_zip_clean),
    fil_city_clean = city_swap(fil_city_norm, fil_state, fil_zip_clean)
  )

# refine on the full column, as the diary does (merges toward the most common spelling)
city_map <- tibble(con_city_swap = vac$con_city_swap) %>%
  mutate(con_city_refine = n_gram_merge(key_collision_merge(con_city_swap), numgram = 1)) %>%
  distinct()
good <- vac %>%
  distinct(con_city_swap, con_state, con_zip_clean) %>%
  inner_join(city_map, by = "con_city_swap", relationship = "many-to-many") %>%
  filter(con_city_refine != con_city_swap) %>%
  semi_join(zipcodes, by = c("con_city_refine" = "city", "con_state" = "state", "con_zip_clean" = "zip"))
vac <- vac %>%
  left_join(good, by = c("con_city_swap", "con_state", "con_zip_clean")) %>%
  mutate(con_city_clean = coalesce(con_city_refine, con_city_swap))
stopifnot(nrow(vac) == n0)
cat("cities refined:", sum(!is.na(vac$con_city_refine)), "\n")

many_city <- c(valid_city, extra_city)
print(progress_table(str_to_upper(vac$con_city), vac$con_city_norm, vac$con_city_swap, vac$con_city_clean,
                     compare = many_city))

print(count(vac, year), n = 40)
write_like_old(vac, "va_contribs_clean_202011-202302.csv", "va_contribs_2012-2026.csv")
