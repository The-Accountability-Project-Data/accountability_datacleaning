# Copied 2026-10-30 from the datacleaning_agents repo (datasets/442-443-ne-campaign-finance/ne_common.R): the script that built the October 2026 file.
# Its paths follow that repo's layout (here::i_am / work/<dataset>/raw and out); point them at your own
# raw and output folders before running it from here.
#
# Shared helpers for the Nebraska 442/443 combined rebuild (Oct 2026). Sourced by ne_contribs.R / ne_expends.R.
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr); library(purrr); library(tidyr); library(lubridate)
  library(campfin); library(refinr); library(fs); library(here); library(tibble)
})
comma <- function(x) format(x, big.mark = ",", scientific = FALSE)

base     <- here("work", "442-443-ne-campaign-finance")
raw_dir  <- path(base, "raw", "2026-10-28", "csv")
old_dir  <- path(base, "old")
out_dir  <- dir_create(path(base, "out"))

# Read one NADC e-filing extract (windows-1252, CRLF). Every field is wrapped in double quotes but quotes inside a
# value are NOT escaped (2022 contributions, Receipt ID 1818: "7441 "O" STREET, SUITE 203"), and some values hold a
# CRLF line break. So instead of a CSV quote parser (the diary's regex fix), a record is: physical lines joined (with a
# space, replacing the in-value line break) until it starts and ends with `"` and has exactly ncol-1 `","`
# separators; then the outer quotes are stripped and it is split on `","`. Values are otherwise kept as published.
# Returns list(df, log).
read_nadc <- function(f) {
  txt <- read_file(f, locale = locale(encoding = "windows-1252"))
  x <- str_split(txt, fixed("\r\n"))[[1]]
  if (x[length(x)] == "") x <- x[-length(x)]
  hdr <- str_split(str_sub(x[1], 2, -2), fixed('","'))[[1]]
  n_sep <- length(hdr) - 1
  k <- str_count(x, fixed('","'))
  out <- vector("character", length(x)); j <- 0; i <- 2; joined <- 0; recs_joined <- 0
  while (i <= length(x)) {
    buf <- x[i]; kk <- k[i]; start <- i
    while (!(kk == n_sep && str_ends(buf, '"') && str_starts(buf, '"')) && i < length(x) && kk <= n_sep) {
      i <- i + 1; buf <- paste(buf, x[i]); kk <- kk + k[i]
    }
    if (!(kk == n_sep && str_starts(buf, '"') && str_ends(buf, '"')))
      stop(sprintf("%s: can't assemble record from lines %d-%d (%d separators)", basename(f), start, i, kk))
    if (i > start) { joined <- joined + (i - start + 1); recs_joined <- recs_joined + 1 }
    j <- j + 1; out[j] <- buf; i <- i + 1
  }
  recs <- out[seq_len(j)]
  m <- str_split_fixed(str_sub(recs, 2, -2), fixed('","'), length(hdr))
  colnames(m) <- hdr
  df <- as_tibble(m) %>% mutate(across(everything(), ~ na_if(.x, ""))) %>% mutate(across(everything(), ~ na_if(.x, " ")))
  list(df = df, log = tibble(file = basename(f), fields = length(hdr), raw_lines = length(x) - 1, records = j,
                             lines_joined = joined, records_rejoined = recs_joined,
                             values_with_quote = sum(str_detect(m, fixed('"')))))
}

read_all_years <- function(kind, years = 2021:2026) {
  files <- path(raw_dir, sprintf("%d_%sExtract.csv", years, kind))
  stopifnot(all(file_exists(files)))
  parts <- map(files, read_nadc)
  log <- bind_rows(map(parts, "log"))
  df <- map2_dfr(parts, basename(files), ~ mutate(.x$df, source_file = .y))
  list(df = df, log = log)
}

# old file, read exactly as published: every column character, only "" is NA, no whitespace trimming
read_old <- function(f) {
  read_csv(f, col_types = cols(.default = col_character()), na = "", trim_ws = FALSE, quote = '"',
           progress = FALSE, lazy = FALSE)
}

alnum <- function(x) str_remove_all(str_to_upper(coalesce(x, "")), "[^A-Z0-9]")
amt2  <- function(x) sprintf("%.2f", suppressWarnings(as.numeric(x)))

# 2021 overlap: the old (legacy) system also holds some reports that were e-filed or re-entered in the new system.
# An old row is dropped when ALL hold: it was received in 2021 (old date_received year 2021 -- the legacy system's
# last year), same transaction date, same amount (to the cent), same committee name (letters + digits only), and the
# new row's last/organization name (letters + digits only) occurs inside the old full name. (Without the committee
# condition 18 extra contribution pairs matched, nearly all different recipients -- chance matches.) Matching is one-to-one, in new-row order (file year, then file order),
# each new row taking the first unmatched old row (old file order). Returns the matched pairs.
match_overlap <- function(old, new, o_date, o_amt, o_name, n_date, n_amt, n_last, n_id) {
  o <- old %>% mutate(.oi = row_number()) %>% filter(str_sub(date_received, 1, 4) == "2021") %>%
    transmute(.oi, d = .data[[o_date]], a = amt2(.data[[o_amt]]), on = alnum(.data[[o_name]]),
              o_committee = committee_name, o_name = .data[[o_name]], o_form = source_form)
  n <- new %>% mutate(.ni = row_number()) %>%
    transmute(.ni, d = as.character(.data[[n_date]]), a = amt2(.data[[n_amt]]), ln = alnum(.data[[n_last]]),
              n_id = .data[[n_id]], n_committee = committee_name, n_last = .data[[n_last]], n_file = source_file) %>%
    filter(ln != "")
  cand <- inner_join(n, o, by = c("d", "a"), relationship = "many-to-many") %>%
    filter(str_detect(on, fixed(ln)), alnum(o_committee) == alnum(n_committee)) %>% arrange(.ni, .oi)
  used_o <- integer(0); keep <- logical(nrow(cand)); seen_n <- integer(0)
  for (r in seq_len(nrow(cand))) {
    if (cand$.ni[r] %in% seen_n || cand$.oi[r] %in% used_o) next
    keep[r] <- TRUE; used_o <- c(used_o, cand$.oi[r]); seen_n <- c(seen_n, cand$.ni[r])
  }
  cand[keep, ] %>% mutate(same_committee_name = alnum(o_committee) == alnum(n_committee))
}

# campfin city normalization exactly as the after_2021 diaries (normal_city -> zipcodes swap -> refine)
clean_city <- function(df, city, state, zip_norm) {
  norm_city <- df %>%
    distinct(city_raw = .data[[city]], st = .data[[state]], zip_norm = .data[[zip_norm]]) %>%
    mutate(city_norm = normal_city(city = city_raw, abbs = usps_city, states = c("NE", "DC", "NEBRASKA"),
                                   na = invalid_city, na_rep = TRUE)) %>%
    left_join(zipcodes, by = c("st" = "state", "zip_norm" = "zip")) %>%
    rename(city_match = city) %>%
    mutate(match_abb = is_abbrev(city_norm, city_match), match_dist = str_dist(city_norm, city_match),
           city_swap = if_else(!is.na(match_dist) & (match_abb | match_dist == 1), city_match, city_norm)) %>%
    select(city_raw, st, zip_norm, city_norm, city_swap)
  df <- df %>% left_join(norm_city, by = setNames(c("city_raw", "st", "zip_norm"), c(city, state, zip_norm)))
  # refine over all rows (cluster frequencies as in the diary), keep only refinements that are a valid city/state/zip
  good_refine <- df %>%
    transmute(st = .data[[state]], zip_norm = .data[[zip_norm]], city_swap) %>%
    mutate(city_refine = city_swap %>% key_collision_merge() %>% n_gram_merge(numgram = 1)) %>%
    filter(city_refine != city_swap) %>%
    inner_join(zipcodes, by = c("city_refine" = "city", "st" = "state", "zip_norm" = "zip")) %>%
    distinct(st, zip_norm, city_swap, city_refine)
  stopifnot(!anyDuplicated(good_refine[c("st", "zip_norm", "city_swap")]))
  df %>% left_join(good_refine, by = setNames(c("st", "zip_norm", "city_swap"), c(state, zip_norm, "city_swap"))) %>%
    mutate(city_clean = coalesce(city_refine, city_swap)) %>% select(-city_norm, -city_swap, -city_refine)
}

full_name <- function(first, middle, last, suffix) {
  str_squish(paste(coalesce(first, ""), coalesce(middle, ""), coalesce(last, ""), coalesce(suffix, ""))) %>% na_if("")
}

write_out <- function(df, name) {
  f <- path(out_dir, name)
  write_csv(df, f, na = "")
  f
}
