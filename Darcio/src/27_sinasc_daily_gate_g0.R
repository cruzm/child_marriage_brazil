#!/usr/bin/env Rscript
# 27_sinasc_daily_gate_g0.R — implement only Gate G0 of the frozen SINASC
# exact-age protocol. This script performs data-integrity checks and aggregated
# feasibility counts. It deliberately does not estimate an outcome contrast,
# discontinuity, density, continuity, placebo, regression, or causal effect.

options(stringsAsFactors = FALSE)

cwd <- normalizePath(getwd(), mustWork = TRUE)
root <- if (file.exists(file.path(cwd, "config", "sinasc_daily_lock.yml"))) {
  cwd
} else {
  file.path(cwd, "Darcio")
}
if (!dir.exists(root)) stop("Cannot locate the Darcio project directory")

.libPaths(c(file.path(root, "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(digest)
  library(yaml)
})

started <- Sys.time()
set.seed(13811)

sinasc_dir <- file.path(root, "data", "raw_external", "sinasc")
audit_dir <- file.path(root, "outputs", "audit")
analysis_dir <- file.path(root, "outputs", "analysis")
log_dir <- file.path(root, "outputs", "logs")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(analysis_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

log_file <- file.path(log_dir, "27_sinasc_daily_gate_g0.log")
writeLines(character(), log_file)

log_line <- function(...) {
  msg <- sprintf(
    "[%s] %s",
    format(Sys.time(), "%Y-%m-%d %H:%M:%S%z"),
    paste0(...)
  )
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

rss_mb <- function() {
  x <- readLines("/proc/self/status", warn = FALSE)
  hit <- grep("^VmRSS:", x, value = TRUE)
  if (!length(hit)) return(NA_real_)
  as.numeric(strsplit(trimws(hit), "[[:space:]]+")[[1]][2]) / 1024
}

free_mem_gib <- function() {
  x <- readLines("/proc/meminfo", warn = FALSE)
  hit <- grep("^MemAvailable:", x, value = TRUE)
  if (!length(hit)) return(NA_real_)
  as.numeric(strsplit(trimws(hit), "[[:space:]]+")[[1]][2]) / 1024^2
}

clean_text <- function(x) {
  x <- trimws(as.character(x))
  x[x == ""] <- NA_character_
  x
}

gregorian_valid <- function(day, month, year) {
  leap <- !is.na(year) & year %% 4L == 0L &
    (year %% 100L != 0L | year %% 400L == 0L)
  max_day <- rep.int(NA_integer_, length(day))
  ok_month <- !is.na(month) & month >= 1L & month <= 12L
  max_day[ok_month] <- c(31L, 28L, 31L, 30L, 31L, 30L,
                         31L, 31L, 30L, 31L, 30L, 31L)[month[ok_month]]
  feb_leap <- ok_month & month == 2L & leap
  max_day[feb_leap] <- 29L
  ans <- !is.na(day) & !is.na(year) & year >= 1L & year <= 9999L &
    ok_month & day >= 1L & day <= max_day
  ans[is.na(ans)] <- FALSE
  ans
}

date_parts <- function(x) {
  x <- clean_text(x)
  shape <- !is.na(x) & grepl("^[0-9]{8}$", x)
  day <- suppressWarnings(as.integer(substr(x, 1L, 2L)))
  month <- suppressWarnings(as.integer(substr(x, 3L, 4L)))
  year <- suppressWarnings(as.integer(substr(x, 5L, 8L)))
  valid <- shape & gregorian_valid(day, month, year)
  valid[is.na(valid)] <- FALSE
  list(raw = x, day = day, month = month, year = year,
       shape = shape, valid = valid)
}

idate_from_parts <- function(parts, valid = parts$valid) {
  out <- rep.int(NA_character_, length(parts$day))
  idx <- which(valid)
  if (length(idx)) {
    out[idx] <- sprintf("%04d-%02d-%02d",
                        parts$year[idx], parts$month[idx], parts$day[idx])
  }
  as.IDate(out)
}

safe_share <- function(numerator, denominator) {
  ifelse(denominator > 0, numerator / denominator, NA_real_)
}

fmt_int <- function(x) {
  ifelse(is.na(x), "NA", format(x, big.mark = ",", scientific = FALSE,
                                 trim = TRUE))
}

fmt_pct <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f%%"), 100 * x))
}

# Mechanical unit checks are deliberately outcome-free.
test_dates <- date_parts(c("29022000", "29022001", "01012000", "1012000", NA))
stopifnot(identical(test_dates$valid,
                    c(TRUE, FALSE, TRUE, FALSE, FALSE)))
test_mother <- as.IDate("2000-09-04")
test_birthday <- as.IDate("2016-09-04")
stopifnot(as.integer(as.IDate("2016-09-03") - test_birthday) == -1L)
stopifnot(as.integer(as.IDate("2016-09-04") - test_birthday) == 0L)
stopifnot(test_mother < test_birthday)

lock_path <- file.path(root, "config", "sinasc_daily_lock.yml")
anchor_path <- file.path(root, "config", "sinasc_daily_g0_anchors.csv")
hash_path <- file.path(root, "paper", "ledgers", "SINASC_DAILY_LOCK_SHA256.txt")
manifest_path <- file.path(sinasc_dir, "SHA256_MANIFEST.txt")
required_files <- c(lock_path, anchor_path, hash_path, manifest_path)
if (!all(file.exists(required_files))) {
  stop("Missing G0 input(s): ", paste(required_files[!file.exists(required_files)],
                                      collapse = ", "))
}

# Verify the frozen protocol and its amendment ledger before reading microdata.
hash_lines <- readLines(hash_path, warn = FALSE)
expected_frozen_hash <- function(rel_path) {
  hit <- grep(paste0(rel_path, "$"), hash_lines, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub("[[:space:]].*$", "", hit)
}
frozen_rel <- c(
  "config/sinasc_daily_lock.yml",
  "paper/ledgers/SINASC_DAILY_PROTOCOL.md",
  "paper/ledgers/SINASC_DAILY_AMENDMENTS.md"
)
frozen_actual <- vapply(
  frozen_rel,
  function(x) digest(file.path(root, x), algo = "sha256", file = TRUE),
  character(1)
)
frozen_expected <- vapply(frozen_rel, expected_frozen_hash, character(1))
if (anyNA(frozen_expected) || !identical(unname(frozen_actual),
                                         unname(frozen_expected))) {
  stop("Frozen SINASC daily protocol hash check failed")
}

lock <- read_yaml(lock_path)
if (!identical(lock$protocol$version, "1.0.0")) {
  stop("Unexpected SINASC daily protocol version")
}
if (!isTRUE(lock$protocol$frozen_before_any_daily_age_distance_outcome_contrast)) {
  stop("Protocol does not certify a pre-contrast freeze")
}

pre_years <- as.integer(unlist(lock$periods$primary_pre_years))
post_years <- as.integer(unlist(lock$periods$primary_post_years))
years <- c(pre_years, post_years)
era_for_year <- function(y) ifelse(y %in% pre_years, "pre", "post")
bands <- sort(unique(c(
  as.integer(lock$primary_estimator$bandwidth_days),
  as.integer(unlist(lock$frozen_sensitivity_set$bandwidths_days))
)))
stopifnot(identical(years, c(2016:2018, 2022:2024)))
stopifnot(identical(bands, c(30L, 60L, 90L, 180L)))

anchors <- fread(anchor_path, na.strings = c("", "NA"))
anchor_schema <- c("year", "official_total", "anchor_role", "use_for_gate",
                   "institution", "source_title", "source_url",
                   "vintage_note", "accessed_at")
if (!all(anchor_schema %in% names(anchors))) {
  stop("Anchor registry schema is incomplete")
}
anchors[, year := as.integer(year)]
anchors[, official_total := as.numeric(official_total)]
if (!is.logical(anchors$use_for_gate)) {
  anchors[, use_for_gate := toupper(as.character(use_for_gate)) == "TRUE"]
}
gate_anchors <- anchors[use_for_gate == TRUE & year %in% years]
if (gate_anchors[, .N, by = year][N != 1L, .N] > 0L ||
    !setequal(gate_anchors$year, years)) {
  stop("Exactly one gate anchor is required for every primary year")
}

manifest_lines <- readLines(manifest_path, warn = FALSE)
manifest <- data.table(
  raw_sha256_expected = sub("[[:space:]].*$", "", manifest_lines),
  zip_file = sub("^[^[:space:]]+[[:space:]]+", "", manifest_lines)
)

zip_for_year <- function(y) file.path(sinasc_dir, sprintf("SINASC_%d_csv.zip", y))
need_cols <- c("DTNASC", "DTNASCMAE", "IDADEMAE", "ESTCIVMAE",
               "GRAVIDEZ", "CODMUNRES")

annual_list <- vector("list", length(years))
monthly_list <- vector("list", length(years))
quality_status_list <- vector("list", length(years))
side_quality_list <- list()
band_year_list <- list()

log_line("start | scope=G0_only | protocol=", lock$protocol$version,
         " | R=", R.version$major, ".", R.version$minor,
         " | data.table=", as.character(packageVersion("data.table")),
         " | yaml=", as.character(packageVersion("yaml")),
         " | digest=", as.character(packageVersion("digest")),
         " | free_mem=", sprintf("%.1fGiB", free_mem_gib()))
log_line("forbidden operations not invoked: regression, discontinuity, density, ",
         "continuity, placebo, effect estimation")

for (i in seq_along(years)) {
  y <- years[i]
  era <- era_for_year(y)
  zp <- zip_for_year(y)
  if (!file.exists(zp)) stop("Missing raw archive: ", zp)
  zip_name <- basename(zp)
  expected_zip_hash <- manifest[zip_file == zip_name, raw_sha256_expected]
  if (length(expected_zip_hash) != 1L) {
    stop("Missing or duplicate manifest entry for ", zip_name)
  }
  actual_zip_hash <- digest(zp, algo = "sha256", file = TRUE)
  zip_hash_ok <- identical(actual_zip_hash, expected_zip_hash)
  if (!zip_hash_ok) stop("Raw archive hash mismatch for ", zip_name)

  listing <- unzip(zp, list = TRUE)
  inner_candidates <- listing$Name[!grepl("/$", listing$Name)]
  if (!length(inner_candidates)) stop("No file inside ", zip_name)
  inner <- inner_candidates[1]
  cmd <- sprintf("unzip -p %s %s", shQuote(zp), shQuote(inner))

  t0 <- Sys.time()
  header <- fread(cmd = cmd, sep = ";", header = TRUE, nrows = 0L,
                  fill = TRUE, quote = "\"", encoding = "Latin-1",
                  showProgress = FALSE)
  header_upper <- toupper(names(header))
  select_idx <- match(need_cols, header_upper)
  missing_cols <- need_cols[is.na(select_idx)]
  if (length(missing_cols)) {
    stop(sprintf("Year %d missing G0 columns: %s", y,
                 paste(missing_cols, collapse = ", ")))
  }

  dt <- fread(cmd = cmd, sep = ";", header = TRUE, fill = TRUE,
              quote = "\"", encoding = "Latin-1", select = select_idx,
              colClasses = "character", nThread = min(4L, getDTthreads()),
              showProgress = FALSE)
  setnames(dt, toupper(names(dt)))
  if (!identical(names(dt), need_cols)) setcolorder(dt, need_cols)
  for (v in need_cols) set(dt, j = v, value = clean_text(dt[[v]]))
  n_raw <- nrow(dt)

  child_parts <- date_parts(dt$DTNASC)
  child_valid_file <- child_parts$valid & child_parts$year == y
  child_valid_file[is.na(child_valid_file)] <- FALSE
  monthly_counts <- tabulate(child_parts$month[child_valid_file], nbins = 12L)
  monthly_list[[i]] <- rbindlist(list(
    data.table(year = y, era = era, row_type = "valid_birth_month",
               month = 1:12, n_records = as.numeric(monthly_counts)),
    data.table(year = y, era = era, row_type = "invalid_or_wrong_year_date",
               month = NA_integer_, n_records = sum(!child_valid_file))
  ))

  reported_age <- suppressWarnings(as.integer(dt$IDADEMAE))
  geo_valid <- !is.na(dt$CODMUNRES) & grepl("^[1-5]", dt$CODMUNRES)
  age_geo_idx <- which(reported_age %in% c(15L, 16L) & geo_valid)
  d <- dt[age_geo_idx]
  d[, `:=`(year = y, era = era)]
  d[, reported_age := reported_age[age_geo_idx]]
  d[, child_day := child_parts$day[age_geo_idx]]
  d[, child_month := child_parts$month[age_geo_idx]]
  d[, child_year := child_parts$year[age_geo_idx]]
  d[, child_valid_file := child_valid_file[age_geo_idx]]

  mother_parts <- date_parts(d$DTNASCMAE)
  child_subset_parts <- list(
    day = d$child_day,
    month = d$child_month,
    year = d$child_year,
    valid = d$child_valid_file
  )
  child_date <- idate_from_parts(child_subset_parts, d$child_valid_file)
  mother_date <- idate_from_parts(mother_parts)
  mother_precedes <- !is.na(child_date) & !is.na(mother_date) &
    mother_date < child_date

  age_calendar <- rep.int(NA_integer_, nrow(d))
  basic_pair <- d$child_valid_file & mother_parts$valid & mother_precedes
  birthday_not_reached <- d$child_month < mother_parts$month |
    (d$child_month == mother_parts$month & d$child_day < mother_parts$day)
  age_calendar[basic_pair] <-
    d$child_year[basic_pair] - mother_parts$year[basic_pair] -
    as.integer(birthday_not_reached[basic_pair])
  plausible_age <- !is.na(age_calendar) & age_calendar >= 8L & age_calendar <= 59L

  birthday_year <- mother_parts$year + 16L
  birthday_valid <- mother_parts$valid &
    gregorian_valid(mother_parts$day, mother_parts$month, birthday_year)
  exact_base <- basic_pair & plausible_age
  impossible_birthday <- exact_base & !birthday_valid
  if (any(impossible_birthday)) {
    stop(sprintf("Year %d has %d impossible constructed sixteenth birthdays",
                 y, sum(impossible_birthday)))
  }
  birthday_parts <- list(
    day = mother_parts$day,
    month = mother_parts$month,
    year = birthday_year,
    valid = birthday_valid
  )
  sixteenth_birthday <- idate_from_parts(birthday_parts, birthday_valid)
  exact_valid <- exact_base & birthday_valid & !is.na(sixteenth_birthday)
  x_days <- rep.int(NA_integer_, nrow(d))
  x_days[exact_valid] <- as.integer(
    child_date[exact_valid] - sixteenth_birthday[exact_valid]
  )
  if (any(x_days[exact_valid] != floor(x_days[exact_valid]))) {
    stop("Non-integer running variable detected")
  }

  d[, singleton := GRAVIDEZ == "1"]
  d[is.na(singleton), singleton := FALSE]
  d[, status_valid := ESTCIVMAE %chin% as.character(1:5)]
  d[, status_bucket := fifelse(
    is.na(ESTCIVMAE), "BLANK",
    fifelse(ESTCIVMAE %chin% c(as.character(1:5), "9"),
             ESTCIVMAE, "OTHER")
  )]
  d[, exact_valid := exact_valid]
  d[, completed_age := age_calendar]
  d[, age_agree := exact_valid & completed_age == reported_age]
  d[, x_days := x_days]
  d[, side := fifelse(is.na(x_days), NA_character_,
                      fifelse(x_days < 0L, "below", "above"))]

  candidate <- d$singleton
  n_candidate <- sum(candidate)
  n_exact_valid <- sum(candidate & d$exact_valid)
  n_age_agree <- sum(candidate & d$age_agree)
  annual_list[[i]] <- data.table(
    year = y,
    era = era,
    zip_file = zip_name,
    zip_member = inner,
    raw_sha256 = actual_zip_hash,
    manifest_sha256_match = zip_hash_ok,
    required_schema_complete = TRUE,
    n_raw = as.numeric(n_raw),
    n_strict_child_date_valid_file_year = sum(child_valid_file),
    n_pre_date_candidates = as.numeric(n_candidate),
    n_exact_date_valid = as.numeric(n_exact_valid),
    exact_date_valid_share = safe_share(n_exact_valid, n_candidate),
    n_completed_age_agree = as.numeric(n_age_agree),
    completed_age_agreement_share = safe_share(n_age_agree, n_exact_valid),
    n_candidate_child_date_invalid = sum(candidate & !d$child_valid_file),
    n_candidate_mother_date_invalid = sum(candidate & !mother_parts$valid),
    n_candidate_mother_not_before_child = sum(
      candidate & d$child_valid_file & mother_parts$valid & !mother_precedes
    ),
    n_candidate_calendar_age_implausible = sum(
      candidate & basic_pair & !plausible_age
    ),
    n_impossible_sixteenth_birthday = sum(candidate & impossible_birthday)
  )

  q <- d[singleton == TRUE, .(
    n_candidates = .N,
    n_exact_date_valid = sum(exact_valid),
    n_completed_age_agree = sum(age_agree)
  ), by = .(year, era, reported_age, status_code = status_bucket)]
  q[, exact_date_valid_share := safe_share(n_exact_date_valid, n_candidates)]
  q[, completed_age_agreement_share := safe_share(
    n_completed_age_agree, n_exact_date_valid
  )]
  q[, privacy_suppressed := n_candidates >= 1 & n_candidates <= 9]
  suppress_cols <- c("n_candidates", "n_exact_date_valid",
                     "n_completed_age_agree", "exact_date_valid_share",
                     "completed_age_agreement_share")
  for (v in suppress_cols) set(q, which(q$privacy_suppressed), v, NA)
  quality_status_list[[i]] <- q

  for (h in bands) {
    in_band <- d$exact_valid & d$age_agree & !is.na(d$x_days) &
      abs(d$x_days) < h
    s <- d[in_band, .(
      n_age_date_geo_scope = .N,
      n_singleton = sum(singleton),
      n_valid_status_singleton = sum(singleton & status_valid)
    ), by = .(year, era, side)]
    s_grid <- CJ(side = c("below", "above"), unique = TRUE)
    s <- merge(s_grid, s, by = "side", all.x = TRUE, sort = FALSE)
    s[, `:=`(year = y, era = era, bandwidth_days = h)]
    for (v in c("n_age_date_geo_scope", "n_singleton",
                "n_valid_status_singleton")) {
      set(s, which(is.na(s[[v]])), v, 0)
    }
    s[, singleton_share := safe_share(n_singleton, n_age_date_geo_scope)]
    s[, valid_status_share := safe_share(
      n_valid_status_singleton, n_singleton
    )]
    setcolorder(s, c("year", "era", "bandwidth_days", "side",
                    "n_age_date_geo_scope", "n_singleton",
                    "singleton_share", "n_valid_status_singleton",
                    "valid_status_share"))
    side_quality_list[[length(side_quality_list) + 1L]] <- s

    b <- d[in_band & singleton & status_valid, .(
      n_births = .N,
      n_married_events_internal = sum(ESTCIVMAE == "2")
    ), by = .(year, era, side)]
    b_grid <- CJ(side = c("below", "above"), unique = TRUE)
    b <- merge(b_grid, b, by = "side", all.x = TRUE, sort = FALSE)
    b[, `:=`(year = y, era = era, bandwidth_days = h)]
    for (v in c("n_births", "n_married_events_internal")) {
      set(b, which(is.na(b[[v]])), v, 0)
    }
    setcolorder(b, c("year", "era", "bandwidth_days", "side",
                    "n_births", "n_married_events_internal"))
    band_year_list[[length(band_year_list) + 1L]] <- b
  }

  log_line(sprintf(
    "year=%d | raw=%s | pre_date_candidates=%s | exact_valid=%s | age_agree=%s | %.1fs | RSS=%.0fMB",
    y, fmt_int(n_raw), fmt_int(n_candidate), fmt_int(n_exact_valid),
    fmt_int(n_age_agree), as.numeric(difftime(Sys.time(), t0, units = "secs")),
    rss_mb()
  ))

  rm(dt, d, header, child_parts, child_date, mother_parts, mother_date,
     sixteenth_birthday, reported_age, geo_valid, q)
  gc(verbose = FALSE)
}

annual <- rbindlist(annual_list, use.names = TRUE, fill = TRUE)
monthly <- rbindlist(monthly_list, use.names = TRUE, fill = TRUE)
quality_status <- rbindlist(quality_status_list, use.names = TRUE, fill = TRUE)
side_quality <- rbindlist(side_quality_list, use.names = TRUE, fill = TRUE)
band_year_internal <- rbindlist(band_year_list, use.names = TRUE, fill = TRUE)

setorder(annual, year)
setorder(monthly, year, row_type, month)
setorder(quality_status, year, reported_age, status_code)
setorder(side_quality, year, bandwidth_days, side)
setorder(band_year_internal, year, bandwidth_days, side)

anchor_reconciliation <- merge(
  anchors,
  annual[, .(year, raw_total = n_raw)],
  by = "year", all.x = TRUE, sort = FALSE
)
anchor_reconciliation[, difference_raw_minus_anchor := raw_total - official_total]
anchor_reconciliation[, exact_match :=
                        !is.na(raw_total) & raw_total == official_total]
setorder(anchor_reconciliation, year, -use_for_gate)

gate_rec <- anchor_reconciliation[use_for_gate == TRUE & year %in% years]
annual <- merge(
  annual,
  gate_rec[, .(year, official_total, anchor_role, anchor_institution = institution,
               anchor_source_title = source_title, anchor_source_url = source_url,
               anchor_vintage_note = vintage_note,
               raw_minus_official = difference_raw_minus_anchor,
               official_total_exact_match = exact_match)],
  by = "year", all.x = TRUE, sort = FALSE
)
setorder(annual, year)

side_era <- side_quality[, .(
  n_age_date_geo_scope = sum(n_age_date_geo_scope),
  n_singleton = sum(n_singleton),
  n_valid_status_singleton = sum(n_valid_status_singleton)
), by = .(era, bandwidth_days, side)]
side_era[, singleton_share := safe_share(n_singleton, n_age_date_geo_scope)]
side_era[, valid_status_share := safe_share(
  n_valid_status_singleton, n_singleton
)]
setorder(side_era, bandwidth_days, era, side)

band_era_internal <- band_year_internal[, .(
  n_births = sum(n_births),
  n_married_events_internal = sum(n_married_events_internal)
), by = .(era, bandwidth_days, side)]
setorder(band_era_internal, bandwidth_days, era, side)

thresholds <- lock$gates$G0_data$pass_requirements
min_date <- as.numeric(thresholds$exact_date_valid_share_each_primary_year_min)
min_agree <- as.numeric(thresholds$completed_age_agreement_among_valid_dates_min)
min_status <- as.numeric(thresholds$valid_status_share_each_era_side_min)
min_births <- as.numeric(thresholds$births_each_era_side_at_h90_min)
min_married <- as.numeric(thresholds$married_events_each_era_side_at_h90_min)

anchor_missing <- nrow(gate_rec) != length(years) ||
  any(is.na(gate_rec$official_total))
anchor_mismatch <- !anchor_missing && any(!gate_rec$exact_match)
anchor_status <- if (anchor_missing) {
  "QUALIFIED"
} else if (anchor_mismatch) {
  "FAIL"
} else {
  "PASS"
}

worst_date <- annual[which.min(exact_date_valid_share)]
worst_agree <- annual[which.min(completed_age_agreement_share)]
status_h90 <- side_era[bandwidth_days == 90L]
birth_h90 <- band_era_internal[bandwidth_days == 90L]
worst_status <- status_h90[which.min(valid_status_share)]
worst_birth <- birth_h90[which.min(n_births)]
worst_married <- birth_h90[which.min(n_married_events_internal)]

gate_status <- rbindlist(list(
  data.table(
    criterion = "official_annual_total_reconciliation",
    scope = "every primary year; exact match to designated independent comparable anchor",
    threshold = "6/6 exact; unavailable anchor implies QUALIFIED",
    observed = sprintf("%d/%d exact", sum(gate_rec$exact_match), length(years)),
    worst_cell = if (anchor_mismatch) paste(gate_rec[exact_match == FALSE, year],
                                            collapse = ",") else "none",
    status = anchor_status
  ),
  data.table(
    criterion = "exact_date_valid_share_each_primary_year",
    scope = "each primary year",
    threshold = sprintf(">= %.3f", min_date),
    observed = sprintf("minimum %.6f", worst_date$exact_date_valid_share),
    worst_cell = as.character(worst_date$year),
    status = ifelse(all(annual$exact_date_valid_share >= min_date),
                    "PASS", "FAIL")
  ),
  data.table(
    criterion = "completed_age_agreement_among_valid_dates",
    scope = "each primary year",
    threshold = sprintf(">= %.3f", min_agree),
    observed = sprintf("minimum %.6f", worst_agree$completed_age_agreement_share),
    worst_cell = as.character(worst_agree$year),
    status = ifelse(all(annual$completed_age_agreement_share >= min_agree),
                    "PASS", "FAIL")
  ),
  data.table(
    criterion = "valid_status_share_each_era_side",
    scope = "each era x side cell at h=90",
    threshold = sprintf(">= %.3f", min_status),
    observed = sprintf("minimum %.6f", worst_status$valid_status_share),
    worst_cell = paste(worst_status$era, worst_status$side, sep = ":"),
    status = ifelse(all(status_h90$valid_status_share >= min_status),
                    "PASS", "FAIL")
  ),
  data.table(
    criterion = "births_each_era_side_at_h90",
    scope = "each era x side cell at h=90",
    threshold = sprintf(">= %d", as.integer(min_births)),
    observed = sprintf("minimum %d", as.integer(worst_birth$n_births)),
    worst_cell = paste(worst_birth$era, worst_birth$side, sep = ":"),
    status = ifelse(all(birth_h90$n_births >= min_births), "PASS", "FAIL")
  ),
  data.table(
    criterion = "married_events_each_era_side_at_h90",
    scope = "each era x side cell at h=90",
    threshold = sprintf(">= %d", as.integer(min_married)),
    observed = if (worst_married$n_married_events_internal >= 10L) {
      sprintf("minimum %d", as.integer(worst_married$n_married_events_internal))
    } else {
      "minimum <10 (privacy-suppressed)"
    },
    worst_cell = paste(worst_married$era, worst_married$side, sep = ":"),
    status = ifelse(all(birth_h90$n_married_events_internal >= min_married),
                    "PASS", "FAIL")
  )
), use.names = TRUE)

overall_status <- if (any(gate_status$status == "FAIL")) {
  "FAIL"
} else if (any(gate_status$status == "QUALIFIED")) {
  "QUALIFIED"
} else {
  "PASS"
}
gate_status <- rbind(
  gate_status,
  data.table(
    criterion = "G0_OVERALL",
    scope = "frozen Gate G0 only",
    threshold = "all mandatory criteria pass; missing independent anchor yields QUALIFIED",
    observed = overall_status,
    worst_cell = "not_applicable",
    status = overall_status
  )
)

# Public band-count output: suppress exact outcome-event cells of size 1--9.
band_year <- copy(band_year_internal)
band_year[, privacy_suppressed_married :=
            n_married_events_internal >= 1 & n_married_events_internal <= 9]
band_year[, n_married_events := as.numeric(n_married_events_internal)]
band_year[privacy_suppressed_married == TRUE, n_married_events := NA_real_]
band_year[, n_married_events_internal := NULL]
band_year[, aggregation := "year"]

band_era <- copy(band_era_internal)
band_era[, privacy_suppressed_married :=
           n_married_events_internal >= 1 & n_married_events_internal <= 9]
band_era[, n_married_events := as.numeric(n_married_events_internal)]
band_era[privacy_suppressed_married == TRUE, n_married_events := NA_real_]
band_era[, n_married_events_internal := NULL]
band_era[, `:=`(year = NA_integer_, aggregation = "era")]

band_counts <- rbindlist(list(band_year, band_era), use.names = TRUE, fill = TRUE)
setcolorder(band_counts, c("aggregation", "year", "era", "bandwidth_days",
                          "side", "n_births", "n_married_events",
                          "privacy_suppressed_married"))
setorder(band_counts, aggregation, bandwidth_days, era, year, side)

# Guard against accidentally exporting effect-estimation fields from this stage.
forbidden_export_fields <- c("estimate", "coefficient", "std_error", "p_value",
                             "ci_low", "ci_high", "tau", "jump", "effect")
g0_objects <- list(annual, monthly, quality_status, side_quality, side_era,
                   band_counts, anchor_reconciliation, gate_status)
if (any(vapply(g0_objects, function(z) any(names(z) %chin% forbidden_export_fields),
               logical(1)))) {
  stop("Forbidden effect-estimation field reached a G0 output")
}

paths <- list(
  annual = file.path(audit_dir, "SINASC_DAILY_G0_ANNUAL.csv"),
  monthly = file.path(audit_dir, "SINASC_DAILY_G0_MONTHLY_PROFILE.csv"),
  quality_status = file.path(audit_dir, "SINASC_DAILY_G0_DATE_QUALITY_BY_STATUS.csv"),
  side_quality = file.path(audit_dir, "SINASC_DAILY_G0_SIDE_QUALITY.csv"),
  side_era = file.path(audit_dir, "SINASC_DAILY_G0_ERA_SIDE_QUALITY.csv"),
  band_counts = file.path(audit_dir, "SINASC_DAILY_G0_BAND_COUNTS.csv"),
  anchors = file.path(audit_dir, "SINASC_DAILY_G0_ANCHOR_RECONCILIATION.csv"),
  gate = file.path(audit_dir, "SINASC_DAILY_GATE_STATUS.csv"),
  report = file.path(analysis_dir, "SINASC_DAILY_GATE_G0.md")
)

fwrite(annual, paths$annual, na = "")
fwrite(monthly, paths$monthly, na = "")
fwrite(quality_status, paths$quality_status, na = "")
fwrite(side_quality, paths$side_quality, na = "")
fwrite(side_era, paths$side_era, na = "")
fwrite(band_counts, paths$band_counts, na = "")
fwrite(anchor_reconciliation, paths$anchors, na = "")
fwrite(gate_status, paths$gate, na = "")

gate_lines <- c(
  "| Criterion | Threshold | Observed | Worst cell | Status |",
  "|---|---:|---:|---|---|",
  vapply(seq_len(nrow(gate_status)), function(j) sprintf(
    "| %s | %s | %s | %s | **%s** |",
    gate_status$criterion[j], gate_status$threshold[j],
    gate_status$observed[j], gate_status$worst_cell[j],
    gate_status$status[j]
  ), character(1))
)

annual_lines <- c(
  "| Year | Era | Raw rows | Official anchor | Difference | Exact match | Exact-date valid | Age agrees |",
  "|---:|---|---:|---:|---:|---|---:|---:|",
  vapply(seq_len(nrow(annual)), function(j) sprintf(
    "| %d | %s | %s | %s | %s | %s | %s | %s |",
    annual$year[j], annual$era[j], fmt_int(annual$n_raw[j]),
    fmt_int(annual$official_total[j]), fmt_int(annual$raw_minus_official[j]),
    ifelse(annual$official_total_exact_match[j], "yes", "no"),
    fmt_pct(annual$exact_date_valid_share[j]),
    fmt_pct(annual$completed_age_agreement_share[j])
  ), character(1))
)

h90_counts <- merge(
  birth_h90,
  status_h90[, .(era, side, valid_status_share)],
  by = c("era", "side"), all = TRUE
)
setorder(h90_counts, era, side)
h90_lines <- c(
  "| Era | Side | Valid-status share | Births | Married events |",
  "|---|---|---:|---:|---:|",
  vapply(seq_len(nrow(h90_counts)), function(j) sprintf(
    "| %s | %s | %s | %s | %s |",
    h90_counts$era[j], h90_counts$side[j],
    fmt_pct(h90_counts$valid_status_share[j]),
    fmt_int(h90_counts$n_births[j]),
    ifelse(h90_counts$n_married_events_internal[j] >= 10L,
           fmt_int(h90_counts$n_married_events_internal[j]), "suppressed (<10)")
  ), character(1))
)

report_lines <- c(
  "# SINASC daily design — Gate G0",
  "",
  sprintf("**Status: %s.**", overall_status),
  "",
  sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "This artifact implements only the frozen data gate. It contains no regression,",
  "discontinuity estimate, density test, continuity test, placebo, coefficient,",
  "standard error, p-value, confidence interval, or causal-effect estimate.",
  "",
  "## Decision",
  "",
  gate_lines,
  "",
  "## Annual reconciliation and date integrity",
  "",
  annual_lines,
  "",
  "Every designated annual gate anchor is independent of the cached archive and",
  "corresponds to a comparable final/current extraction. Conflicting preliminary",
  "vintages are preserved in `SINASC_DAILY_G0_ANCHOR_RECONCILIATION.csv` and are",
  "not silently substituted for the designated anchor. Monthly raw profiles are",
  "exported without outcome fields; no independent monthly anchor was designated.",
  "",
  "## Frozen h=90 feasibility cells",
  "",
  h90_lines,
  "",
  "These are mandated event counts, not outcome rates or contrasts. The script does",
  "not subtract, divide, model, or compare married-event counts across cutoff sides.",
  "",
  "## Operational definitions",
  "",
  "The filter order and denominators follow prospective amendment A001, recorded",
  "before this first G0 run. Dates must be strict eight-digit `ddmmyyyy`; age is",
  "constructed calendar-wise; and `x=0` is assigned above the cutoff. Band audits",
  "retain positive triangular-kernel support (`abs(x)<h`). Cells containing 1--9",
  "outcome events are suppressed from public outputs.",
  "",
  "## Artifacts",
  "",
  sprintf("- `%s`", sub(paste0("^", root, "/"), "", paths$gate)),
  sprintf("- `%s`", sub(paste0("^", root, "/"), "", paths$annual)),
  sprintf("- `%s`", sub(paste0("^", root, "/"), "", paths$monthly)),
  sprintf("- `%s`", sub(paste0("^", root, "/"), "", paths$quality_status)),
  sprintf("- `%s`", sub(paste0("^", root, "/"), "", paths$side_quality)),
  sprintf("- `%s`", sub(paste0("^", root, "/"), "", paths$side_era)),
  sprintf("- `%s`", sub(paste0("^", root, "/"), "", paths$band_counts)),
  sprintf("- `%s`", sub(paste0("^", root, "/"), "", paths$anchors)),
  sprintf("- `%s`", sub(paste0("^", root, "/"), "", log_file)),
  "",
  "No later gate was run. Under the frozen protocol, a `FAIL` stops all outcome",
  "estimation; a `QUALIFIED` status prohibits an unconditional causal-core decision."
)
writeLines(report_lines, paths$report, useBytes = TRUE)

# Hash only the deterministic data/report outputs (the timestamped log is excluded).
manifest_outputs <- unlist(paths[names(paths) != "report"], use.names = TRUE)
manifest_outputs <- c(manifest_outputs, report = paths$report)
output_manifest <- data.table(
  artifact = sub(paste0("^", root, "/"), "", manifest_outputs),
  sha256 = vapply(manifest_outputs, digest, character(1),
                  algo = "sha256", file = TRUE),
  scope = "G0_only_no_effect_estimation"
)
manifest_out_path <- file.path(audit_dir, "SINASC_DAILY_G0_OUTPUT_MANIFEST.csv")
fwrite(output_manifest, manifest_out_path)

elapsed <- as.numeric(difftime(Sys.time(), started, units = "mins"))
log_line(sprintf("done | G0=%s | years=%d | outputs=%d | %.2f min | RSS=%.0fMB",
                 overall_status, length(years), nrow(output_manifest) + 1L,
                 elapsed, rss_mb()))
cat(sprintf("SINASC_DAILY_G0_STATUS=%s\n", overall_status))

if (identical(overall_status, "FAIL")) quit(save = "no", status = 2L)
