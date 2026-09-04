#!/usr/bin/env Rscript
# 31_sinasc_daily_gate_g2.R — implement only Gate G2 of the frozen SINASC
# exact-age protocol. Permitted scope: the pre-law temporal placebo, placebo
# cutoffs at ages 15/17/19, annual age-16 jumps, and nine leave-one-year-out
# stability diagnostics. Prohibited: the full primary age-16 policy estimate,
# DELAY90, secondary outcomes, sensitivities, and every G3 classification.

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
  library(fixest)
  library(ggplot2)
  library(yaml)
})

started <- Sys.time()
set.seed(13811)
setFixest_nthreads(min(4L, parallel::detectCores()))

sinasc_dir <- file.path(root, "data", "raw_external", "sinasc")
audit_dir <- file.path(root, "outputs", "audit")
analysis_dir <- file.path(root, "outputs", "analysis")
table_dir <- file.path(root, "outputs", "tables")
figure_dir <- file.path(root, "outputs", "figures")
log_dir <- file.path(root, "outputs", "logs")
for (d in c(audit_dir, analysis_dir, table_dir, figure_dir, log_dir)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

log_file <- file.path(log_dir, "31_sinasc_daily_gate_g2.log")
writeLines(character(), log_file)

log_line <- function(...) {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S%z"),
                 paste0(...))
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
  max_day[ok_month & month == 2L & leap] <- 29L
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
  list(day = day, month = month, year = year, valid = valid)
}

idate_from_parts <- function(parts, valid = parts$valid) {
  out <- rep.int(NA_character_, length(parts$day))
  idx <- which(valid)
  if (length(idx)) {
    out[idx] <- sprintf("%04d-%02d-%02d", parts$year[idx],
                        parts$month[idx], parts$day[idx])
  }
  as.IDate(out)
}

fmt_num <- function(x, digits = 4L) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_p <- function(x) {
  ifelse(is.na(x), "NA", formatC(x, digits = 6L, format = "g"))
}

fmt_int <- function(x) {
  ifelse(is.na(x), "NA", format(x, big.mark = ",", scientific = FALSE,
                                 trim = TRUE))
}

year_string <- function(x) paste(sort(as.integer(x)), collapse = ",")

extract_ci <- function(fit, coefficient, level) {
  ans <- tryCatch(confint(fit, parm = coefficient, level = level),
                  error = function(e) NULL)
  if (is.null(ans)) return(c(NA_real_, NA_real_))
  as.numeric(ans[1, 1:2])
}

empty_fit <- function(n, n_married, n_municipalities, n_dates, error,
                      warnings = "") {
  list(
    identified = FALSE,
    n = as.numeric(n),
    n_married = as.numeric(n_married),
    n_municipality_clusters = as.numeric(n_municipalities),
    n_date_clusters = as.numeric(n_dates),
    estimate_pp = NA_real_,
    std_error_pp = NA_real_,
    ci90_low_pp = NA_real_,
    ci90_high_pp = NA_real_,
    ci95_low_pp = NA_real_,
    ci95_high_pp = NA_real_,
    p_value = NA_real_,
    error_message = error,
    warnings = warnings
  )
}

extract_fit <- function(fit, coefficient, z, error_message, captured_warnings) {
  base <- empty_fit(
    nrow(z), sum(z$married), uniqueN(z$municipality),
    uniqueN(z$child_date_id), error_message,
    paste(unique(captured_warnings), collapse = " | ")
  )
  if (is.null(fit) || !coefficient %in% names(coef(fit))) {
    if (is.na(base$error_message)) {
      base$error_message <- paste(coefficient, "coefficient not identified")
    }
    return(base)
  }
  ct <- coeftable(fit)
  p_col <- grep("^Pr\\(", colnames(ct), value = TRUE)
  ci90 <- extract_ci(fit, coefficient, 0.90)
  ci95 <- extract_ci(fit, coefficient, 0.95)
  vals <- c(
    estimate = unname(coef(fit)[coefficient]),
    se = unname(ct[coefficient, "Std. Error"]),
    p = if (length(p_col)) unname(ct[coefficient, p_col[1]]) else NA_real_,
    ci90, ci95
  )
  base$identified <- all(is.finite(vals))
  base$n <- as.numeric(nobs(fit))
  base$estimate_pp <- vals["estimate"]
  base$std_error_pp <- vals["se"]
  base$p_value <- vals["p"]
  base$ci90_low_pp <- vals[4]
  base$ci90_high_pp <- vals[5]
  base$ci95_low_pp <- vals[6]
  base$ci95_high_pp <- vals[7]
  base
}

fit_stacked <- function(z) {
  z <- copy(z)
  if (!nrow(z) || uniqueN(z$period) != 2L || uniqueN(z$above) != 2L) {
    return(empty_fit(nrow(z), sum(z$married), uniqueN(z$municipality),
                     uniqueN(z$child_date_id),
                     "stacked model lacks both periods or cutoff sides"))
  }
  z[, `:=`(
    above_period = above * period,
    above_x = above * x_days,
    period_x = period * x_days,
    above_period_x = above * period * x_days
  )]
  captured_warnings <- character()
  error_message <- NA_character_
  fit <- tryCatch(
    withCallingHandlers(
      feols(
        married_pp ~ above + above_period + x_days + above_x + period_x +
          above_period_x | year + birth_month,
        data = z,
        weights = ~triangular_weight,
        vcov = ~municipality + child_date_id,
        notes = FALSE,
        warn = TRUE
      ),
      warning = function(w) {
        captured_warnings <<- c(captured_warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      error_message <<- conditionMessage(e)
      NULL
    }
  )
  extract_fit(fit, "above_period", z, error_message, captured_warnings)
}

fit_annual_jump <- function(z) {
  z <- copy(z)
  if (!nrow(z) || uniqueN(z$above) != 2L) {
    return(empty_fit(nrow(z), sum(z$married), uniqueN(z$municipality),
                     uniqueN(z$child_date_id),
                     "annual model lacks both cutoff sides"))
  }
  z[, above_x := above * x_days]
  captured_warnings <- character()
  error_message <- NA_character_
  fit <- tryCatch(
    withCallingHandlers(
      feols(
        married_pp ~ above + x_days + above_x | birth_month,
        data = z,
        weights = ~triangular_weight,
        vcov = ~municipality + child_date_id,
        notes = FALSE,
        warn = TRUE
      ),
      warning = function(w) {
        captured_warnings <<- c(captured_warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      error_message <<- conditionMessage(e)
      NULL
    }
  )
  extract_fit(fit, "above", z, error_message, captured_warnings)
}

fit_to_dt <- function(x) as.data.table(x)

# Pure construction checks, run before touching outcome data.
date_test <- date_parts(c("29022000", "29022001", "01012000", NA))
stopifnot(identical(date_test$valid, c(TRUE, FALSE, TRUE, FALSE)))
stopifnot(gregorian_valid(29L, 2L, 2016L))
stopifnot(!gregorian_valid(29L, 2L, 2015L))
stopifnot(as.integer(as.IDate("2019-01-01") - as.IDate("2019-01-01")) == 0L)

lock_path <- file.path(root, "config", "sinasc_daily_lock.yml")
hash_path <- file.path(root, "paper", "ledgers",
                       "SINASC_DAILY_LOCK_SHA256.txt")
amendment_path <- file.path(root, "paper", "ledgers",
                            "SINASC_DAILY_AMENDMENTS.md")
g0_gate_path <- file.path(audit_dir, "SINASC_DAILY_GATE_STATUS.csv")
g0_manifest_path <- file.path(audit_dir,
                              "SINASC_DAILY_G0_OUTPUT_MANIFEST.csv")
g0_side_path <- file.path(audit_dir,
                          "SINASC_DAILY_G0_SIDE_QUALITY.csv")
g0_band_path <- file.path(audit_dir,
                          "SINASC_DAILY_G0_BAND_COUNTS.csv")
g1_gate_path <- file.path(audit_dir,
                          "SINASC_DAILY_G1_GATE_STATUS.csv")
g1_manifest_path <- file.path(audit_dir,
                              "SINASC_DAILY_G1_OUTPUT_MANIFEST.csv")
raw_manifest_path <- file.path(sinasc_dir, "SHA256_MANIFEST.txt")
needed_inputs <- c(lock_path, hash_path, amendment_path, g0_gate_path,
                   g0_manifest_path, g0_side_path, g0_band_path,
                   g1_gate_path, g1_manifest_path, raw_manifest_path)
if (!all(file.exists(needed_inputs))) {
  stop("Missing G2 precondition(s): ",
       paste(needed_inputs[!file.exists(needed_inputs)], collapse = ", "))
}

# Revalidate the frozen lock and verify A003 preceded this execution.
hash_lines <- readLines(hash_path, warn = FALSE)
registered_hash <- function(rel) {
  hit <- grep(paste0(rel, "$"), hash_lines, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub("[[:space:]].*$", "", hit)
}
frozen_rel <- c(
  "config/sinasc_daily_lock.yml",
  "paper/ledgers/SINASC_DAILY_PROTOCOL.md",
  "paper/ledgers/SINASC_DAILY_AMENDMENTS.md"
)
frozen_expected <- vapply(frozen_rel, registered_hash, character(1))
frozen_actual <- vapply(frozen_rel, function(x) {
  digest(file.path(root, x), algo = "sha256", file = TRUE)
}, character(1))
if (anyNA(frozen_expected) ||
    !identical(unname(frozen_actual), unname(frozen_expected))) {
  stop("Frozen SINASC daily protocol hash check failed")
}
amendment_text <- paste(readLines(amendment_path, warn = FALSE), collapse = "\n")
if (!grepl("## A003 — Operational implementation of Gate G2",
           amendment_text, fixed = TRUE) ||
    !grepl("before its first run", amendment_text, fixed = TRUE)) {
  stop("Prospective G2 implementation amendment A003 is absent")
}

validate_output_manifest <- function(manifest_path) {
  z <- fread(manifest_path)
  p <- file.path(root, z$artifact)
  if (!all(file.exists(p))) return(FALSE)
  actual <- vapply(p, digest, character(1), algo = "sha256", file = TRUE)
  identical(unname(actual), unname(z$sha256))
}

g0_gate <- fread(g0_gate_path)
g1_gate <- fread(g1_gate_path)
if (!identical(g0_gate[criterion == "G0_OVERALL", status], "PASS") ||
    !validate_output_manifest(g0_manifest_path)) {
  stop("G2 requires an unchanged G0_OVERALL=PASS")
}
if (!identical(g1_gate[criterion == "G1_OVERALL", status], "PASS") ||
    !validate_output_manifest(g1_manifest_path)) {
  stop("G2 requires an unchanged G1_OVERALL=PASS")
}

lock <- read_yaml(lock_path)
if (!identical(lock$protocol$version, "1.0.0")) {
  stop("Unexpected SINASC daily protocol version")
}
margin_pp <- as.numeric(lock$gates$G2_counterfactual$equivalence_margin_pp)
if (!identical(margin_pp, 0.25)) stop("Unexpected G2 equivalence margin")

historical_years <- as.integer(unlist(
  lock$periods$historical_pre_diagnostic_years
))
primary_pre_years <- as.integer(unlist(lock$periods$primary_pre_years))
primary_post_years <- as.integer(unlist(lock$periods$primary_post_years))
transition_years <- as.integer(unlist(lock$periods$transition_years))
pandemic_years <- as.integer(unlist(lock$periods$pandemic_years))
analysis_years <- sort(unique(c(historical_years, primary_pre_years,
                                transition_years, pandemic_years,
                                primary_post_years)))
placebo_ages <- as.integer(unlist(lock$running_variable$placebo_ages))
primary_years <- c(primary_pre_years, primary_post_years)
stopifnot(identical(historical_years, 2013:2014))
stopifnot(identical(primary_pre_years, 2016:2018))
stopifnot(identical(primary_post_years, 2022:2024))
stopifnot(identical(analysis_years, c(2013:2014, 2016:2024)))
stopifnot(identical(placebo_ages, c(15L, 17L, 19L)))

zip_for_year <- function(y) {
  filename <- if (y <= 2015L) {
    sprintf("DNBR%d_csv.zip", y)
  } else {
    sprintf("SINASC_%d_csv.zip", y)
  }
  file.path(sinasc_dir, filename)
}

raw_manifest_lines <- readLines(raw_manifest_path, warn = FALSE)
raw_manifest <- data.table(
  raw_sha256_expected = sub("[[:space:]].*$", "", raw_manifest_lines),
  zip_file = sub("^[^[:space:]]+[[:space:]]+", "", raw_manifest_lines)
)
need_cols <- c("DTNASC", "DTNASCMAE", "IDADEMAE", "ESTCIVMAE",
               "GRAVIDEZ", "CODMUNRES")

sample_list <- list()
schema_list <- list()
leap_list <- list()

log_line(
  "start | scope=G2_only | G0=PASS | G1=PASS | protocol=",
  lock$protocol$version,
  " | R=", R.version$major, ".", R.version$minor,
  " | fixest=", as.character(packageVersion("fixest")),
  " | ggplot2=", as.character(packageVersion("ggplot2")),
  " | data.table=", as.character(packageVersion("data.table")),
  " | free_mem=", sprintf("%.1fGiB", free_mem_gib())
)
log_line("prohibited operations not invoked: full primary age-16 policy fit, ",
         "DELAY90, secondary outcomes, sensitivities, or G3 classification")

for (y in analysis_years) {
  t0 <- Sys.time()
  zp <- zip_for_year(y)
  if (!file.exists(zp)) stop("Missing raw archive: ", zp)
  zip_name <- basename(zp)
  expected_hash <- raw_manifest[zip_file == zip_name, raw_sha256_expected]
  if (length(expected_hash) != 1L) {
    stop("Missing or duplicate raw manifest entry for ", zip_name)
  }
  actual_hash <- digest(zp, algo = "sha256", file = TRUE)
  if (!identical(actual_hash, expected_hash)) {
    stop("Raw archive hash mismatch for ", zip_name)
  }

  listing <- unzip(zp, list = TRUE)
  members <- listing$Name[!grepl("/$", listing$Name)]
  if (!length(members)) stop("No file inside ", zip_name)
  inner <- members[1]
  cmd <- sprintf("unzip -p %s %s", shQuote(zp), shQuote(inner))

  header <- fread(cmd = cmd, sep = ";", header = TRUE, nrows = 0L,
                  fill = TRUE, quote = "\"", encoding = "Latin-1",
                  showProgress = FALSE)
  select_idx <- match(need_cols, toupper(names(header)))
  missing_cols <- need_cols[is.na(select_idx)]
  if (length(missing_cols)) {
    stop(sprintf("Year %d missing G2 columns: %s", y,
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

  reported_age_all <- suppressWarnings(as.integer(dt$IDADEMAE))
  singleton_all <- !is.na(dt$GRAVIDEZ) & dt$GRAVIDEZ == "1"
  geo_valid_all <- !is.na(dt$CODMUNRES) & grepl("^[1-5]", dt$CODMUNRES)
  status_valid_all <- dt$ESTCIVMAE %chin% as.character(1:5)
  candidate_idx <- which(
    reported_age_all %in% 14:19 & singleton_all & geo_valid_all &
      status_valid_all
  )
  d <- dt[candidate_idx]
  reported_age <- reported_age_all[candidate_idx]
  n_pre_date_candidates <- nrow(d)

  child_parts <- date_parts(d$DTNASC)
  mother_parts <- date_parts(d$DTNASCMAE)
  child_valid_file <- child_parts$valid & child_parts$year == y
  child_date <- idate_from_parts(child_parts, child_valid_file)
  mother_date <- idate_from_parts(mother_parts)
  mother_precedes <- !is.na(child_date) & !is.na(mother_date) &
    mother_date < child_date
  exact_base <- child_valid_file & mother_parts$valid & mother_precedes

  birthday_not_reached <- child_parts$month < mother_parts$month |
    (child_parts$month == mother_parts$month &
       child_parts$day < mother_parts$day)
  completed_age <- rep.int(NA_integer_, nrow(d))
  completed_age[exact_base] <-
    child_parts$year[exact_base] - mother_parts$year[exact_base] -
    as.integer(birthday_not_reached[exact_base])
  plausible <- !is.na(completed_age) & completed_age >= 8L &
    completed_age <= 59L
  exact_base <- exact_base & plausible
  age_agree <- exact_base & completed_age == reported_age

  cutoffs_y <- if (y %in% primary_years) {
    c(15L, 16L, 17L, 19L)
  } else {
    16L
  }
  n_retained_y <- 0L
  for (cutoff_age in cutoffs_y) {
    age_pair <- age_agree & reported_age %in% c(cutoff_age - 1L,
                                                cutoff_age)
    anniversary_year <- mother_parts$year + cutoff_age
    anniversary_valid <- mother_parts$valid & gregorian_valid(
      mother_parts$day, mother_parts$month, anniversary_year
    )
    impossible <- age_pair & !anniversary_valid
    explained_feb29 <- impossible & mother_parts$month == 2L &
      mother_parts$day == 29L
    unexplained <- impossible & !explained_feb29
    if (any(unexplained)) {
      stop(sprintf("Year %d cutoff %d has %d non-February-29 impossible anniversaries",
                   y, cutoff_age, sum(unexplained)))
    }
    leap_list[[length(leap_list) + 1L]] <- data.table(
      year = y,
      cutoff_age = cutoff_age,
      n_age_pair_exact_candidates = sum(age_pair),
      n_impossible_anniversary_excluded = sum(impossible),
      n_explained_feb29 = sum(explained_feb29),
      n_other_impossible = sum(unexplained)
    )

    anniversary_parts <- list(
      day = mother_parts$day,
      month = mother_parts$month,
      year = anniversary_year,
      valid = anniversary_valid
    )
    anniversary_date <- idate_from_parts(anniversary_parts,
                                         anniversary_valid)
    x_days <- rep.int(NA_integer_, nrow(d))
    locatable <- age_pair & anniversary_valid & !is.na(anniversary_date)
    x_days[locatable] <- as.integer(
      child_date[locatable] - anniversary_date[locatable]
    )
    keep <- which(locatable & abs(x_days) < 90L)
    if (length(keep)) {
      bad_side <- (x_days[keep] < 0L &
                     completed_age[keep] != cutoff_age - 1L) |
        (x_days[keep] >= 0L & completed_age[keep] != cutoff_age)
      if (any(bad_side)) {
        stop(sprintf("Year %d cutoff %d fails completed-age side reconciliation",
                     y, cutoff_age))
      }
      sample_list[[length(sample_list) + 1L]] <- data.table(
        year = y,
        cutoff_age = cutoff_age,
        x_days = x_days[keep],
        above = as.integer(x_days[keep] >= 0L),
        side = ifelse(x_days[keep] < 0L, "below", "above"),
        triangular_weight = pmax(0, 1 - abs(x_days[keep]) / 90),
        birth_month = child_parts$month[keep],
        municipality = d$CODMUNRES[keep],
        child_date_id = as.integer(child_date[keep]),
        married = as.integer(d$ESTCIVMAE[keep] == "2")
      )
      n_retained_y <- n_retained_y + length(keep)
    }
  }

  schema_list[[length(schema_list) + 1L]] <- data.table(
    year = y,
    zip_file = zip_name,
    zip_member = inner,
    raw_sha256 = actual_hash,
    raw_manifest_sha256_match = TRUE,
    required_g2_schema_complete = TRUE,
    n_raw = as.numeric(n_raw),
    n_pre_date_candidates = as.numeric(n_pre_date_candidates),
    n_retained_h90_across_required_cutoffs = as.numeric(n_retained_y)
  )
  log_line(sprintf(
    "year=%d | raw=%s | candidates=%s | retained_h90=%s | %.1fs | RSS=%.0fMB",
    y, fmt_int(n_raw), fmt_int(n_pre_date_candidates), fmt_int(n_retained_y),
    as.numeric(difftime(Sys.time(), t0, units = "secs")), rss_mb()
  ))

  rm(dt, d, child_parts, mother_parts, child_date, mother_date,
     reported_age_all, reported_age)
  gc(verbose = FALSE)
}

g2_sample <- rbindlist(sample_list, use.names = TRUE)
g2_sample[, married_pp := 100 * married]
schema_audit <- rbindlist(schema_list, use.names = TRUE)
leap_exclusions <- rbindlist(leap_list, use.names = TRUE)
setorder(g2_sample, cutoff_age, year, x_days)
setorder(schema_audit, year)
setorder(leap_exclusions, year, cutoff_age)

expected_pairs <- rbindlist(list(
  data.table(year = analysis_years, cutoff_age = 16L),
  CJ(year = primary_years, cutoff_age = placebo_ages, unique = TRUE)
), use.names = TRUE)
expected_cells <- expected_pairs[, .(side = c("below", "above")),
                                 by = .(year, cutoff_age)]
sample_counts_internal <- g2_sample[, .(
  n_births = .N,
  n_married_events_internal = sum(married),
  married_share_percent_internal = 100 * mean(married)
), by = .(year, cutoff_age, side)]
sample_counts <- merge(expected_cells, sample_counts_internal,
                       by = c("year", "cutoff_age", "side"), all.x = TRUE)
sample_counts[is.na(n_births), `:=`(
  n_births = 0L,
  n_married_events_internal = 0,
  married_share_percent_internal = NA_real_
)]

# Reconcile the 12 primary age-16 h90 cells with the already validated G0.
g0_side <- fread(g0_side_path)
g0_band <- fread(g0_band_path)
g0_ref <- merge(
  g0_side[bandwidth_days == 90L, .(
    year, side, g0_n_births = n_valid_status_singleton
  )],
  g0_band[aggregation == "year" & bandwidth_days == 90L, .(
    year, side, g0_n_married_events = n_married_events
  )],
  by = c("year", "side"), all = TRUE
)
sample_counts <- merge(sample_counts, g0_ref,
                       by = c("year", "side"), all.x = TRUE)
sample_counts[, g0_reference_applicable := cutoff_age == 16L &
                year %in% primary_years]
sample_counts[, `:=`(
  g0_birth_count_match = fifelse(
    g0_reference_applicable, n_births == g0_n_births, NA
  ),
  g0_married_count_match = fifelse(
    g0_reference_applicable,
    n_married_events_internal == g0_n_married_events, NA
  )
)]
if (!all(sample_counts[g0_reference_applicable == TRUE,
                       g0_birth_count_match & g0_married_count_match])) {
  stop("G2 primary age-16 sample does not reconcile to G0")
}
sample_counts[g0_reference_applicable == FALSE, `:=`(
  g0_n_births = NA_real_,
  g0_n_married_events = NA_real_
)]

sample_counts[, privacy_suppressed_married :=
                n_married_events_internal >= 1 &
                n_married_events_internal <= 9]
sample_counts[, n_married_events := fifelse(
  privacy_suppressed_married, NA_real_, n_married_events_internal
)]
sample_counts[, married_share_percent := fifelse(
  privacy_suppressed_married, NA_real_, married_share_percent_internal
)]
sample_counts[, c("n_married_events_internal",
                  "married_share_percent_internal") := NULL]
setorder(sample_counts, cutoff_age, year, side)

# G2 binding placebo 1: pre-law pseudo reform, age 16.
temporal_data <- g2_sample[
  cutoff_age == 16L & year %in% c(historical_years, primary_pre_years)
]
temporal_data[, period := as.integer(year %in% primary_pre_years)]
temporal_fit <- fit_stacked(temporal_data)
temporal <- cbind(data.table(
  model_id = "temporal_placebo_age16",
  test_family = "temporal_placebo",
  cutoff_age = 16L,
  reference_years = year_string(historical_years),
  comparison_years = year_string(primary_pre_years),
  bandwidth_days = 90L
), fit_to_dt(temporal_fit))
temporal[, `:=`(
  equivalence_margin_pp = margin_pp,
  equivalent_at_90pct = identified & ci90_low_pp >= -margin_pp &
    ci90_high_pp <= margin_pp,
  ci95_excludes_zero = identified &
    (ci95_low_pp > 0 | ci95_high_pp < 0),
  magnitude_at_least_margin = identified & abs(estimate_pp) >= margin_pp
)]
temporal[, binding_failure := identified & ci95_excludes_zero &
           magnitude_at_least_margin]
temporal[, status := fifelse(
  equivalent_at_90pct, "PASS",
  fifelse(binding_failure, "FAIL", "QUALIFIED")
)]
log_line(sprintf(
  "model=temporal_placebo_age16 | identified=%s | estimate=%s | p=%s | status=%s",
  temporal$identified, fmt_num(temporal$estimate_pp, 6L),
  fmt_p(temporal$p_value), temporal$status
))

# G2 binding placebo 2: ages 15, 17, and 19 in primary eras.
age_placebo_list <- list()
for (age_c in placebo_ages) {
  z <- g2_sample[cutoff_age == age_c & year %in% primary_years]
  z[, period := as.integer(year %in% primary_post_years)]
  fit <- fit_stacked(z)
  age_placebo_list[[length(age_placebo_list) + 1L]] <- cbind(data.table(
    model_id = sprintf("age_placebo_%d", age_c),
    test_family = "age_placebo",
    cutoff_age = age_c,
    reference_years = year_string(primary_pre_years),
    comparison_years = year_string(primary_post_years),
    bandwidth_days = 90L
  ), fit_to_dt(fit))
  log_line(sprintf("model=age_placebo_%d | identified=%s",
                   age_c, fit$identified))
}
age_placebos <- rbindlist(age_placebo_list, use.names = TRUE, fill = TRUE)
age_placebos[, p_value_holm := p.adjust(p_value, method = "holm")]
age_placebos[, `:=`(
  equivalence_margin_pp = margin_pp,
  equivalent_at_90pct = identified & ci90_low_pp >= -margin_pp &
    ci90_high_pp <= margin_pp,
  rejects_raw_at_5pct = identified & p_value < 0.05,
  rejects_holm_at_5pct = identified & p_value_holm < 0.05,
  magnitude_at_least_margin = identified & abs(estimate_pp) >= margin_pp
)]
age_fail_large <- any(age_placebos$rejects_holm_at_5pct &
                        age_placebos$magnitude_at_least_margin)
age_fail_two <- sum(age_placebos$rejects_holm_at_5pct) >= 2L
age_family_failure <- age_fail_large || age_fail_two
age_family_pass <- all(age_placebos$identified) &&
  all(age_placebos$equivalent_at_90pct)
age_family_status <- if (age_family_failure) {
  "FAIL"
} else if (age_family_pass) {
  "PASS"
} else {
  "QUALIFIED"
}
age_placebos[, `:=`(
  binding_failure_large = rejects_holm_at_5pct &
    magnitude_at_least_margin,
  age_family_two_rejections = age_fail_two,
  family_status = age_family_status
)]

# Mandatory annual age-16 jumps. These are descriptive stability diagnostics,
# not post-minus-pre policy effects.
annual_list <- list()
for (y in analysis_years) {
  z <- g2_sample[cutoff_age == 16L & year == y]
  fit <- fit_annual_jump(z)
  period_label <- fifelse(
    y %in% historical_years, "historical_pre",
    fifelse(y %in% primary_pre_years, "primary_pre",
            fifelse(y %in% transition_years, "transition",
                    fifelse(y %in% pandemic_years, "pandemic",
                            "mature_post")))
  )
  annual_list[[length(annual_list) + 1L]] <- cbind(data.table(
    model_id = sprintf("annual_age16_%d", y),
    test_family = "annual_jump_diagnostic",
    year = y,
    period_label = period_label,
    cutoff_age = 16L,
    bandwidth_days = 90L
  ), fit_to_dt(fit))
  log_line(sprintf("model=annual_age16_%d | identified=%s",
                   y, fit$identified))
}
annual_jumps <- rbindlist(annual_list, use.names = TRUE, fill = TRUE)

# Mandatory nine leave-one-pre-year x leave-one-post-year combinations.
loo_list <- list()
for (omit_pre in primary_pre_years) {
  for (omit_post in primary_post_years) {
    keep_pre <- setdiff(primary_pre_years, omit_pre)
    keep_post <- setdiff(primary_post_years, omit_post)
    z <- g2_sample[
      cutoff_age == 16L & year %in% c(keep_pre, keep_post)
    ]
    z[, period := as.integer(year %in% keep_post)]
    fit <- fit_stacked(z)
    loo_list[[length(loo_list) + 1L]] <- cbind(data.table(
      model_id = sprintf("loo_pre%d_post%d", omit_pre, omit_post),
      test_family = "leave_one_out_diagnostic",
      cutoff_age = 16L,
      omitted_pre_year = omit_pre,
      omitted_post_year = omit_post,
      reference_years = year_string(keep_pre),
      comparison_years = year_string(keep_post),
      bandwidth_days = 90L
    ), fit_to_dt(fit))
    log_line(sprintf("model=loo_pre%d_post%d | identified=%s",
                     omit_pre, omit_post, fit$identified))
  }
}
leave_one_out <- rbindlist(loo_list, use.names = TRUE, fill = TRUE)

# Explicit execution registry makes the G2/G3 boundary machine-auditable.
model_registry <- rbindlist(list(
  temporal[, .(model_id, test_family, cutoff_age, reference_years,
               comparison_years, identified)],
  age_placebos[, .(model_id, test_family, cutoff_age, reference_years,
                   comparison_years, identified)],
  annual_jumps[, .(
    model_id, test_family, cutoff_age,
    reference_years = as.character(year),
    comparison_years = "",
    identified
  )],
  leave_one_out[, .(model_id, test_family, cutoff_age, reference_years,
                    comparison_years, identified)]
), use.names = TRUE, fill = TRUE)
model_registry[, `:=`(
  full_primary_age16_policy_model = FALSE,
  g3_estimand = FALSE
)]
if (nrow(model_registry) != 24L ||
    any(model_registry$full_primary_age16_policy_model) ||
    any(model_registry$g3_estimand)) {
  stop("G2 model registry violates the frozen scope")
}

suppress_small_model_counts <- function(z) {
  z <- copy(z)
  z[, privacy_suppressed_n_married := n_married >= 1 & n_married <= 9]
  z[privacy_suppressed_n_married == TRUE, n_married := NA_real_]
  z
}
temporal <- suppress_small_model_counts(temporal)
age_placebos <- suppress_small_model_counts(age_placebos)
annual_jumps <- suppress_small_model_counts(annual_jumps)
leave_one_out <- suppress_small_model_counts(leave_one_out)

stability_identified <- all(annual_jumps$identified) &&
  all(leave_one_out$identified)
overall_status <- if (temporal$status == "FAIL" ||
                      age_family_status == "FAIL") {
  "FAIL"
} else if (temporal$status == "PASS" &&
           age_family_status == "PASS" && stability_identified) {
  "PASS"
} else {
  "QUALIFIED"
}

g2_gate <- rbindlist(list(
  data.table(
    criterion = "G0_G1_preconditions",
    threshold = "unchanged G0_OVERALL=PASS and G1_OVERALL=PASS",
    observed = "PASS",
    binding_failures = 0L,
    status = "PASS"
  ),
  data.table(
    criterion = "temporal_placebo_age16",
    threshold = paste0(
      "PASS if IC90 inside +/-0.25 pp; FAIL if IC95 excludes zero and ",
      "abs(point)>=0.25 pp"
    ),
    observed = sprintf("estimate %.6f pp; IC90 [%.6f, %.6f]",
                       temporal$estimate_pp, temporal$ci90_low_pp,
                       temporal$ci90_high_pp),
    binding_failures = as.integer(temporal$binding_failure),
    status = temporal$status
  ),
  data.table(
    criterion = "placebo_age_family",
    threshold = paste0(
      "PASS if all IC90 inside +/-0.25 pp; FAIL under either frozen ",
      "Holm rejection clause"
    ),
    observed = sprintf("%d/3 equivalent; %d Holm rejections",
                       sum(age_placebos$equivalent_at_90pct),
                       sum(age_placebos$rejects_holm_at_5pct)),
    binding_failures = as.integer(age_family_failure),
    status = age_family_status
  ),
  data.table(
    criterion = "annual_jump_diagnostics",
    threshold = "all 11 required annual age-16 jumps identified; diagnostic only",
    observed = sprintf("%d/11 identified", sum(annual_jumps$identified)),
    binding_failures = 0L,
    status = ifelse(all(annual_jumps$identified),
                    "DIAGNOSTIC_COMPLETE", "QUALIFIED")
  ),
  data.table(
    criterion = "leave_one_out_diagnostics",
    threshold = "all 9 omitted-pre x omitted-post combinations identified; diagnostic only",
    observed = sprintf("%d/9 identified", sum(leave_one_out$identified)),
    binding_failures = 0L,
    status = ifelse(all(leave_one_out$identified),
                    "DIAGNOSTIC_COMPLETE", "QUALIFIED")
  ),
  data.table(
    criterion = "G2_OVERALL",
    threshold = "both binding components pass and required diagnostics identify",
    observed = overall_status,
    binding_failures = sum(c(temporal$binding_failure,
                             age_family_failure)),
    status = overall_status
  )
), use.names = TRUE)

# Combine only the two binding placebo families in the canonical placebo table.
placebos <- rbindlist(list(
  temporal[, .(
    model_id, test_family, cutoff_age, reference_years, comparison_years,
    bandwidth_days, identified, n, n_married, n_municipality_clusters,
    n_date_clusters, estimate_pp, std_error_pp, ci90_low_pp, ci90_high_pp,
    ci95_low_pp, ci95_high_pp, p_value,
    p_value_holm = NA_real_, equivalent_at_90pct,
    rejects_raw_at_5pct = p_value < 0.05,
    rejects_holm_at_5pct = NA,
    magnitude_at_least_margin, binding_failure, family_status = status,
    error_message, warnings
  )],
  age_placebos[, .(
    model_id, test_family, cutoff_age, reference_years, comparison_years,
    bandwidth_days, identified, n, n_married, n_municipality_clusters,
    n_date_clusters, estimate_pp, std_error_pp, ci90_low_pp, ci90_high_pp,
    ci95_low_pp, ci95_high_pp, p_value, p_value_holm,
    equivalent_at_90pct, rejects_raw_at_5pct, rejects_holm_at_5pct,
    magnitude_at_least_margin,
    binding_failure = binding_failure_large |
      age_family_two_rejections,
    family_status, error_message, warnings
  )]
), use.names = TRUE, fill = TRUE)
placebos[, equivalence_margin_pp := margin_pp]

# Weekly/annual plot required by the frozen diagnostic sequence.
plot_data <- copy(annual_jumps)
plot_data[, period_label := factor(
  period_label,
  levels = c("historical_pre", "primary_pre", "transition", "pandemic",
             "mature_post"),
  labels = c("Historical pre", "Primary pre", "Transition", "Pandemic",
             "Mature post")
)]
p_annual <- ggplot(plot_data,
                   aes(x = year, y = estimate_pp, colour = period_label)) +
  geom_hline(yintercept = 0, colour = "grey35", linewidth = 0.35) +
  geom_vline(xintercept = 2018.5, colour = "grey55", linewidth = 0.35,
             linetype = "dashed") +
  geom_line(aes(group = 1), colour = "grey65", linewidth = 0.4) +
  geom_errorbar(aes(ymin = ci95_low_pp, ymax = ci95_high_pp),
                width = 0.12, linewidth = 0.45) +
  geom_point(size = 1.8) +
  scale_x_continuous(breaks = 2013:2024) +
  scale_colour_manual(values = c(
    "Historical pre" = "#4C78A8", "Primary pre" = "#1B5E8C",
    "Transition" = "#E69F00", "Pandemic" = "#B55D9A",
    "Mature post" = "#2A9D8F"
  )) +
  labs(
    title = "Annual discontinuities in recorded married status at age 16",
    subtitle = "Local-linear estimates at h=90; 95% confidence intervals; 2015 omitted",
    x = "Birth year", y = "Right-minus-left jump (percentage points)",
    colour = "Protocol period"
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")

figure_pdf <- file.path(figure_dir,
                        "FIGURE_SINASC_DAILY_G2_ANNUAL_JUMPS.pdf")
figure_png <- file.path(figure_dir,
                        "FIGURE_SINASC_DAILY_G2_ANNUAL_JUMPS.png")
ggsave(figure_pdf, p_annual, width = 8.2, height = 5.2, units = "in",
       device = cairo_pdf)
ggsave(figure_png, p_annual, width = 8.2, height = 5.2, units = "in",
       dpi = 180)

# Defensive scope and privacy guards before any output is written.
if (any(sample_counts$n_married_events %between% c(1, 9), na.rm = TRUE) ||
    any(!is.na(sample_counts$n_married_events) &
          sample_counts$privacy_suppressed_married) ||
    any(unlist(lapply(
      list(temporal, age_placebos, annual_jumps, leave_one_out),
      function(z) z$n_married %between% c(1, 9)
    )), na.rm = TRUE)) {
  stop("Small married-event cell reached a G2 public output")
}
if (any(placebos$test_family == "primary_policy") ||
    any(model_registry$cutoff_age == 16L &
          model_registry$reference_years == year_string(primary_pre_years) &
          model_registry$comparison_years == year_string(primary_post_years))) {
  stop("A prohibited full primary age-16 policy fit reached G2")
}

paths <- list(
  schema = file.path(audit_dir, "SINASC_DAILY_G2_SCHEMA_AUDIT.csv"),
  sample_counts = file.path(audit_dir,
                            "SINASC_DAILY_G2_SAMPLE_COUNTS.csv"),
  leap_exclusions = file.path(audit_dir,
                              "SINASC_DAILY_G2_LEAP_EXCLUSIONS.csv"),
  model_registry = file.path(audit_dir,
                             "SINASC_DAILY_G2_MODEL_REGISTRY.csv"),
  placebos = file.path(table_dir, "SINASC_DAILY_PLACEBOS.csv"),
  annual = file.path(table_dir, "SINASC_DAILY_G2_ANNUAL_JUMPS.csv"),
  leave_one_out = file.path(table_dir,
                            "SINASC_DAILY_G2_LEAVE_ONE_OUT.csv"),
  gate = file.path(audit_dir, "SINASC_DAILY_G2_GATE_STATUS.csv"),
  report = file.path(analysis_dir, "SINASC_DAILY_GATE_G2.md"),
  figure_pdf = figure_pdf,
  figure_png = figure_png
)

fwrite(schema_audit, paths$schema, na = "")
fwrite(sample_counts, paths$sample_counts, na = "")
fwrite(leap_exclusions, paths$leap_exclusions, na = "")
fwrite(model_registry, paths$model_registry, na = "")
fwrite(placebos, paths$placebos, na = "")
fwrite(annual_jumps, paths$annual, na = "")
fwrite(leave_one_out, paths$leave_one_out, na = "")
fwrite(g2_gate, paths$gate, na = "")

gate_lines <- c(
  "| Criterion | Threshold | Observed | Status |",
  "|---|---|---:|---|",
  vapply(seq_len(nrow(g2_gate)), function(i) sprintf(
    "| %s | %s | %s | **%s** |",
    g2_gate$criterion[i], g2_gate$threshold[i], g2_gate$observed[i],
    g2_gate$status[i]
  ), character(1))
)
placebo_lines <- c(
  "| Test | Age | Estimate pp | IC90% | IC95% | Raw p | Holm p | Equivalent | Family status |",
  "|---|---:|---:|---:|---:|---:|---:|---|---|",
  vapply(seq_len(nrow(placebos)), function(i) sprintf(
    "| %s | %d | %s | [%s, %s] | [%s, %s] | %s | %s | %s | **%s** |",
    placebos$test_family[i], placebos$cutoff_age[i],
    fmt_num(placebos$estimate_pp[i], 5L),
    fmt_num(placebos$ci90_low_pp[i], 5L),
    fmt_num(placebos$ci90_high_pp[i], 5L),
    fmt_num(placebos$ci95_low_pp[i], 5L),
    fmt_num(placebos$ci95_high_pp[i], 5L),
    fmt_p(placebos$p_value[i]), fmt_p(placebos$p_value_holm[i]),
    placebos$equivalent_at_90pct[i], placebos$family_status[i]
  ), character(1))
)
annual_lines <- c(
  "| Year | Period | Jump pp | IC95% | p-value | N | Married events |",
  "|---:|---|---:|---:|---:|---:|---:|",
  vapply(seq_len(nrow(annual_jumps)), function(i) sprintf(
    "| %d | %s | %s | [%s, %s] | %s | %s | %s |",
    annual_jumps$year[i], annual_jumps$period_label[i],
    fmt_num(annual_jumps$estimate_pp[i], 5L),
    fmt_num(annual_jumps$ci95_low_pp[i], 5L),
    fmt_num(annual_jumps$ci95_high_pp[i], 5L),
    fmt_p(annual_jumps$p_value[i]), fmt_int(annual_jumps$n[i]),
    fmt_int(annual_jumps$n_married[i])
  ), character(1))
)
loo_lines <- c(
  "| Omitted pre | Omitted post | Estimate pp | IC95% | p-value |",
  "|---:|---:|---:|---:|---:|",
  vapply(seq_len(nrow(leave_one_out)), function(i) sprintf(
    "| %d | %d | %s | [%s, %s] | %s |",
    leave_one_out$omitted_pre_year[i],
    leave_one_out$omitted_post_year[i],
    fmt_num(leave_one_out$estimate_pp[i], 5L),
    fmt_num(leave_one_out$ci95_low_pp[i], 5L),
    fmt_num(leave_one_out$ci95_high_pp[i], 5L),
    fmt_p(leave_one_out$p_value[i])
  ), character(1))
)
scope_consequence <- switch(
  overall_status,
  PASS = paste0(
    "G2 passes the frozen counterfactual gate. This is not an effect estimate; ",
    "G3 remains necessary before any causal-core decision."
  ),
  FAIL = paste0(
    "G2 fails the frozen counterfactual gate. Under the lock, the daily design ",
    "cannot recenter the paper, regardless of any later effect estimate."
  ),
  QUALIFIED = paste0(
    "G2 is qualified rather than passed. The counterfactual evidence is ",
    "inconclusive, and an unconditional causal-core decision is prohibited."
  )
)

report_lines <- c(
  "# SINASC daily design — Gate G2",
  "",
  sprintf("**Status: %s.**", overall_status),
  "",
  sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "This artifact implements only the frozen G2 counterfactual diagnostics:",
  "the pre-law temporal placebo, placebo birthdays 15/17/19, annual age-16",
  "jumps, and leave-one-primary-year-out stability. The outcome is recorded",
  "married status among singleton live births with valid SINASC status codes.",
  "It does not estimate the full primary age-16 pre-versus-post coefficient,",
  "DELAY90, a secondary outcome, a sensitivity specification, or any G3 result.",
  "",
  "## Decision",
  "",
  gate_lines,
  "",
  scope_consequence,
  "",
  "## Binding placebo results",
  "",
  placebo_lines,
  "",
  "The equivalence margin is +/-0.25 percentage points. The temporal placebo",
  "uses 2013-2014 as reference and 2016-2018 as pseudo-post. Holm adjustment",
  "covers all three age placebos. PASS requires affirmative equivalence under",
  "prospective amendment A003; lack of rejection alone is not a pass.",
  "",
  "## Annual age-16 jump diagnostics",
  "",
  annual_lines,
  "",
  "These are separate within-year right-minus-left jumps. They are displayed to",
  "expose instability and are not post-minus-pre policy-effect estimates.",
  "",
  "## Leave-one-year-out diagnostics",
  "",
  loo_lines,
  "",
  "All nine combinations omit one primary pre year and one mature-post year.",
  "Their coefficients are mandatory stability diagnostics and cannot override",
  "the binding temporal or age-placebo verdicts.",
  "",
  "## Sample and calendar audit",
  "",
  sprintf("The build streamed %d annual ZIPs and retained %s cutoff-specific h=90 records.",
          nrow(schema_audit), fmt_int(nrow(g2_sample))),
  sprintf("It excluded %s nonexistent placebo anniversaries; all were explained by February 29 births.",
          fmt_int(sum(leap_exclusions$n_impossible_anniversary_excluded))),
  sprintf("All %d primary age-16 year-by-side cells reproduced the validated G0 birth and married-event counts.",
          sample_counts[g0_reference_applicable == TRUE, .N]),
  "Married-event cells with 1-9 events are suppressed in the public sample-count",
  "audit. No municipality-by-day cells or person-level derivatives are written.",
  "",
  "## Artifacts",
  "",
  vapply(unlist(paths, use.names = FALSE), function(p) sprintf(
    "- `%s`", sub(paste0("^", root, "/"), "", p)
  ), character(1)),
  "",
  "The classification details follow prospective amendment A003, recorded before",
  "the first G2 coefficient. No G3 model was run."
)
writeLines(report_lines, paths$report, useBytes = TRUE)

manifest_files <- unlist(paths, use.names = TRUE)
output_manifest <- data.table(
  artifact = sub(paste0("^", root, "/"), "", manifest_files),
  sha256 = vapply(manifest_files, digest, character(1), algo = "sha256",
                  file = TRUE),
  scope = "G2_only_no_full_primary_or_G3_estimation"
)
manifest_path <- file.path(audit_dir,
                           "SINASC_DAILY_G2_OUTPUT_MANIFEST.csv")
fwrite(output_manifest, manifest_path)

elapsed <- as.numeric(difftime(Sys.time(), started, units = "mins"))
log_line(sprintf(
  "done | G2=%s | temporal=%s | age_family=%s | annual=%d/11 | loo=%d/9 | models=%d | outputs=%d | %.2f min | RSS=%.0fMB",
  overall_status, temporal$status, age_family_status,
  sum(annual_jumps$identified), sum(leave_one_out$identified),
  nrow(model_registry), nrow(output_manifest) + 1L, elapsed, rss_mb()
))
cat(sprintf("SINASC_DAILY_G2_STATUS=%s\n", overall_status))

if (identical(overall_status, "FAIL")) quit(save = "no", status = 2L)
