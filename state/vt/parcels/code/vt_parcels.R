# Copied 2026-10-30 from the datacleaning_agents repo (datasets/410-vt-parcels/vt_parcels.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Vermont Parcels 2026: a NEW dataset whose predecessor is 410 (Vermont parcels). Built 2026-10-28; 410 is untouched.
# Follows accountability_datacleaning/state/vt/parcels/docs/vt_parcels_diary.Rmd (Kiernan Nicholls, 2021).
#
# Input: work/410-vt-parcels/raw/2026-10-28/vt_parcels_hubv1_2026-10-28.csv
#   - A fresh ArcGIS Hub v1 CSV export of the VCGI layer FS_VCGI_OPENDATA_Cadastral_VTPARCELS_poly_standardized_parcels_SP_v1/0.
#   - The diary's Hub v3 URL now serves a stale 2022 cache, so it is not used.
#   - See datasets/410-vt-parcels.md and retrievals.jsonl.
#
# Output: one row per published record, with exactly the 63 columns of csv/vt_parcels_2017-20211011.csv, in the same order.
#
# Changes from the diary:
#   - The v1 export's header has field ALIASES, so columns are named by position from the layer's field list (the same
#     57 names as 2021), then clean_names() as before.
#   - Read with readr's default quote escaping (escape_double = TRUE). The diary's escape_double = FALSE misparses the 28
#     lines with "" inside quoted fields. All columns are read as character and trim_ws = FALSE, so values stay exactly
#     as published (no float artifacts, leading zeros kept).
#   - CAT: the source now publishes codes (R1, M, MHL, ...). User decision 2026-10-28: map them back to the 2021 labels.
#     The code-to-label pairs come from the old file, joined on SPAN, and must agree with the fixed table below. A code
#     with no label stops the build.
#   - The Google check_city() step is removed (no API calls). In the diary it only extended the list of known-valid
#     cities used for the progress table; it never changed city_clean. city_clean is still normal_city -> swap
#     (zipcodes) -> refine (refinr), all offline with campfin's data.
#   - The refine join uses objectid, which is unique, instead of all columns. The result is the same and the join is faster.
#   - Shapes come out as shape_length then shape_area (the 2021 order). The v1 export has Shape__Area first.
#   - Kept as the agency published it: road, rail, trail and water rows with no owner (user, 2026-10-28), YEAR 0 rows,
#     and the lowercase rescode "c". No amended or superseded flag exists in this source.
# year = the source's YEAR (the GIS / parcel-map year), as dataset 410 uses (user decision 2026-10-28).
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(fs); library(jsonlite)
  library(campfin); library(refinr); library(janitor)
})

agents <- path_expand("~/uc_berkeley/datacleaning_agents")
base <- path(agents, "work", "410-vt-parcels")
raw_csv <- path(base, "raw", "2026-10-28", "vt_parcels_hubv1_2026-10-28.csv")
old_csv <- path(base, "old", "vt_parcels_2017-20211011.csv")
out_dir <- dir_create(path(base, "out"))

# Layer field names, in order. These are the same as the layer's ?f=json on 2026-10-28 and the 2021 dictionary.
field_names <- c("OBJECTID", "SPAN", "GLIST_SPAN", "MAPID", "PARCID", "PROPTYPE", "YEAR", "GLYEAR", "TOWN", "TNAME",
  "SOURCENAME", "SOURCETYPE", "SOURCEDATE", "EDITMETHOD", "EDITOR", "EDITDATE", "MATCHSTAT", "EDITNOTE", "OWNER1",
  "OWNER2", "ADDRGL1", "ADDRGL2", "CITYGL", "STGL", "ZIPGL", "DESCPROP", "LOCAPROP", "CAT", "RESCODE", "ACRESGL",
  "REAL_FLV", "HSTED_FLV", "NRES_FLV", "LAND_LV", "IMPRV_LV", "EQUIPVAL", "EQUIPCODE", "INVENVAL", "HSDECL",
  "HSITEVAL", "VETEXAMT", "EXPDESC", "ENDDATE", "STATUTE", "EXAMT_HS", "EXAMT_NR", "UVREDUC_HS", "UVREDUC_NR",
  "GLVAL_HS", "GLVAL_NR", "CRHOUSPCT", "MUNGL1PCT", "AOEGL_HS", "AOEGL_NR", "E911ADDR", "Shape__Area", "Shape__Length")
alias_hdr <- names(read_csv(raw_csv, n_max = 0, show_col_types = FALSE))
stopifnot(length(alias_hdr) == 57, alias_hdr[1] == "OBJECTID", alias_hdr[56] == "Shape__Area",
          alias_hdr[2] == "GIS SPAN", alias_hdr[8] == "Grand List Year", alias_hdr[19] == "Owner Name 1")

vtp <- read_delim(raw_csv, delim = ",", skip = 1, col_names = field_names,
                  col_types = cols(.default = col_character()), na = "", trim_ws = FALSE,
                  escape_backslash = FALSE, progress = FALSE)
stopifnot(nrow(vtp) == 344138, ncol(vtp) == 57, nrow(problems(vtp)) == 0)
vtp <- clean_names(vtp, case = "snake")   # shape__area -> shape_area, shape__length -> shape_length
message("read ", format(nrow(vtp), big.mark = ","), " rows")

# Category codes -> 2021 labels (user, 2026-10-28)
cat_labels <- c(R1 = "Residential-1", R2 = "Residential-2", M = "Miscellaneous", O = "Other", C = "Commercial",
                MHL = "Mobile Home/la", MHU = "Mobile Home/un", S1 = "Seasonal-1", S2 = "Seasonal-2", W = "Woodland",
                F = "Farm", CA = "Commercial Apt", I = "Industrial", UE = "Utilities Elec", UO = "Utilities Other")
old_cat <- read_csv(old_csv, col_types = cols(.default = col_character()), col_select = c(span, cat),
                    na = "", progress = FALSE) %>% filter(!is.na(span), !is.na(cat)) %>% distinct()
pairs <- vtp %>% filter(!is.na(span), !is.na(cat)) %>% select(span, code = cat) %>% distinct() %>%
  inner_join(old_cat, by = "span", relationship = "many-to-many") %>% count(code, cat) %>%
  group_by(code) %>% mutate(share = n / sum(n)) %>% slice_max(n, n = 1, with_ties = FALSE) %>% ungroup()
message("code -> label pairs observed via SPAN (top label per code, share of matched parcels):")
print(as.data.frame(pairs))
stopifnot(all(pairs$cat == cat_labels[pairs$code]))   # observed pairs agree with the table
unmapped <- setdiff(na.omit(unique(vtp$cat)), names(cat_labels))
if (length(unmapped)) stop("CAT codes with no 2021 label: ", paste(unmapped, collapse = ", "))
vtp <- mutate(vtp, cat = unname(cat_labels[cat]))

# Diary steps
key_vars <- c("real_flv", "year", "addrgl1", "owner1")
vtp <- flag_na(vtp, all_of(key_vars))
vtp <- flag_dupes(vtp, -objectid)
message("na_flag: ", sum(vtp$na_flag), " | dupe_flag: ", sum(vtp$dupe_flag))

vtp <- vtp %>% mutate(zip_norm = normal_zip(zip = zipgl, na_rep = TRUE))
vtp <- vtp %>% mutate(
  state_norm = stgl %>%
    str_remove_all("\\.") %>%
    str_replace("^CANADA$", "CN") %>%
    str_replace("^QUEBEC$", "QC") %>%
    str_replace("^QUE?(\\s+)?CANADA$", "QC") %>%
    str_replace("^N Y$", "NY") %>%
    str_remove("\\s+CANADA$") %>%
    normal_state(abbreviate = TRUE, na_rep = TRUE) %>%
    str_replace("^(\\w)\\s(\\w)", "\\1\\2"))
vtp <- mutate(vtp, state_prop = "VT")

norm_city <- vtp %>%
  distinct(citygl, state_norm, zip_norm) %>%
  mutate(city_norm = normal_city(city = citygl, abbs = usps_city, states = c("VT", "DC", "VERMONT"),
                                 na = invalid_city, na_rep = TRUE))
norm_city <- norm_city %>%
  left_join(zipcodes, by = c("state_norm" = "state", "zip_norm" = "zip")) %>%
  rename(city_match = city) %>%
  mutate(match_abb = is_abbrev(city_norm, city_match),
         match_dist = str_dist(city_norm, city_match),
         city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)) %>%
  select(-city_match, -match_dist, -match_abb)
# zipcodes can have several cities per zip, so keep the first swap per key. This makes the join many-to-one and keeps
# the row count unchanged.
norm_city <- distinct(norm_city, citygl, state_norm, zip_norm, .keep_all = TRUE)
n0 <- nrow(vtp)
vtp <- left_join(vtp, norm_city, by = c("citygl", "state_norm", "zip_norm"), relationship = "many-to-one")
stopifnot(nrow(vtp) == n0)

good_refine <- vtp %>%
  mutate(city_refine = city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)) %>%
  filter(city_refine != city_swap) %>%
  inner_join(zipcodes, by = c("city_refine" = "city", "state_norm" = "state", "zip_norm" = "zip")) %>%
  distinct(objectid, city_refine)
vtp <- vtp %>% left_join(good_refine, by = "objectid", relationship = "one-to-one") %>%
  mutate(city_refine = coalesce(city_refine, city_swap))
stopifnot(nrow(vtp) == n0)

many_city <- c(valid_city, extra_city, "BROWNINGTON", "WEYBRIDGE", "ST GEORGE", "GEORGIA", "PANTON")
print(progress_table(str_to_upper(vtp$citygl), vtp$city_norm, vtp$city_swap, vtp$city_refine, compare = many_city))

vtp <- vtp %>%
  select(-city_norm, -city_swap, city_clean = city_refine) %>%
  rename_all(~str_replace(., "_norm", "_clean")) %>%
  relocate(city_clean, state_clean, .before = zip_clean) %>%
  relocate(state_prop, .before = city_clean) %>%
  relocate(shape_length, .before = shape_area)

old_cols <- names(read_csv(old_csv, n_max = 0, show_col_types = FALSE))
stopifnot(identical(names(vtp), old_cols))

yrs <- suppressWarnings(as.integer(vtp$year))
yr <- range(yrs[yrs > 0], na.rm = TRUE)
out <- path(out_dir, sprintf("vt_parcels_%d-%d.csv", yr[1], yr[2]))
write_csv(vtp, out, na = "")
message("wrote ", out, ": ", format(nrow(vtp), big.mark = ","), " rows, ", ncol(vtp), " columns, ",
        format(file_size(out)))
