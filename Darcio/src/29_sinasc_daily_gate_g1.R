#!/usr/bin/env Rscript
# 29_sinasc_daily_gate_g1.R — implement only Gate G1 of the frozen SINASC
# exact-age protocol. Permitted scope: density/heaping, predetermined-covariate
# continuity, non-hard composition diagnostics, and status missingness.
# Prohibited here: married-status outcomes, G2 placebos, and G3 effects.

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
  library(rddensity)
  library(yaml)
})

started <- Sys.time()
set.seed(13811)
setFixest_nthreads(min(4L, parallel::detectCores()))

sinasc_dir <- file.path(root, "data", "raw_external", "sinasc")
audit_dir <- file.path(root, "outputs", "audit")
analysis_dir <- file.path(root, "outputs", "analysis")
figure_dir <- file.path(root, "outputs", "figures")
log_dir <- file.path(root, "outputs", "logs")
for (d in c(audit_dir, analysis_dir, figure_dir, log_dir)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

log_file <- file.path(log_dir, "29_sinasc_daily_gate_g1.log")
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
    out[idx] <- sprintf("%04d-%02d-%02d",
                        parts$year[idx], parts$month[idx], parts$day[idx])
  }
  as.IDate(out)
}

fmt_num <- function(x, digits = 4L) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_int <- function(x) {
  ifelse(is.na(x), "NA", format(x, big.mark = ",", scientific = FALSE,
                                 trim = TRUE))
}

weighted_sd_population <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (!any(ok)) return(NA_real_)
  mu <- weighted.mean(x[ok], w[ok])
  sqrt(sum(w[ok] * (x[ok] - mu)^2) / sum(w[ok]))
}

# Outcome-free unit checks.
test_dates <- date_parts(c("29022000", "29022001", "01012000", "1012000", NA))
stopifnot(identical(test_dates$valid, c(TRUE, FALSE, TRUE, FALSE, FALSE)))
stopifnot(as.integer(as.IDate("2016-09-03") - as.IDate("2016-09-04")) == -1L)
stopifnot(as.integer(as.IDate("2016-09-04") - as.IDate("2016-09-04")) == 0L)

lock_path <- file.path(root, "config", "sinasc_daily_lock.yml")
hash_path <- file.path(root, "paper", "ledgers", "SINASC_DAILY_LOCK_SHA256.txt")
g0_gate_path <- file.path(audit_dir, "SINASC_DAILY_GATE_STATUS.csv")
g0_annual_path <- file.path(audit_dir, "SINASC_DAILY_G0_ANNUAL.csv")
g0_side_path <- file.path(audit_dir, "SINASC_DAILY_G0_SIDE_QUALITY.csv")
g0_manifest_path <- file.path(audit_dir, "SINASC_DAILY_G0_OUTPUT_MANIFEST.csv")
needed_inputs <- c(lock_path, hash_path, g0_gate_path, g0_annual_path,
                   g0_side_path, g0_manifest_path)
if (!all(file.exists(needed_inputs))) {
  stop("Missing G1 precondition(s): ",
       paste(needed_inputs[!file.exists(needed_inputs)], collapse = ", "))
}

# Revalidate the frozen lock and current prospective amendment ledger.
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
if (anyNA(frozen_expected) ||
    !identical(unname(frozen_actual), unname(frozen_expected))) {
  stop("Frozen SINASC daily protocol hash check failed")
}

lock <- read_yaml(lock_path)
if (!identical(lock$protocol$version, "1.0.0")) {
  stop("Unexpected SINASC daily protocol version")
}

# G1 is allowed only after a clean, internally unchanged G0 pass.
g0_gate <- fread(g0_gate_path)
g0_overall <- g0_gate[criterion == "G0_OVERALL", status]
if (!identical(g0_overall, "PASS")) {
  stop("G1 requires G0_OVERALL=PASS; observed: ", paste(g0_overall, collapse = ","))
}
g0_manifest <- fread(g0_manifest_path)
g0_manifest_files <- file.path(root, g0_manifest$artifact)
if (!all(file.exists(g0_manifest_files))) stop("A listed G0 artifact is missing")
g0_actual_hashes <- vapply(g0_manifest_files, digest, character(1),
                           algo = "sha256", file = TRUE)
if (!identical(unname(g0_actual_hashes), unname(g0_manifest$sha256))) {
  stop("G0 output-manifest hash check failed")
}
g0_annual <- fread(g0_annual_path)
g0_side <- fread(g0_side_path)

pre_years <- as.integer(unlist(lock$periods$primary_pre_years))
post_years <- as.integer(unlist(lock$periods$primary_post_years))
years <- c(pre_years, post_years)
bands <- sort(unique(c(
  as.integer(lock$primary_estimator$bandwidth_days),
  as.integer(unlist(lock$frozen_sensitivity_set$bandwidths_days))
)))
stopifnot(identical(years, c(2016:2018, 2022:2024)))
stopifnot(identical(bands, c(30L, 60L, 90L, 180L)))

zip_for_year <- function(y) file.path(sinasc_dir, sprintf("SINASC_%d_csv.zip", y))
need_cols <- c(
  "DTNASC", "DTNASCMAE", "IDADEMAE", "ESTCIVMAE", "GRAVIDEZ",
  "CODMUNRES", "RACACORMAE", "CODUFNATU", "ESCMAE2010",
  "ESCMAEAGR1", "QTDFILVIVO"
)

sample_list <- vector("list", length(years))
schema_list <- vector("list", length(years))

log_line("start | scope=G1_only | G0=PASS | protocol=", lock$protocol$version,
         " | R=", R.version$major, ".", R.version$minor,
         " | rddensity=", as.character(packageVersion("rddensity")),
         " | fixest=", as.character(packageVersion("fixest")),
         " | ggplot2=", as.character(packageVersion("ggplot2")),
         " | data.table=", as.character(packageVersion("data.table")),
         " | free_mem=", sprintf("%.1fGiB", free_mem_gib()))
log_line("prohibited operations not invoked: married-status outcome, G2 placebos, ",
         "G3 primary or delayed-response effects")

for (i in seq_along(years)) {
  y <- years[i]
  era <- ifelse(y %in% pre_years, "pre", "post")
  zp <- zip_for_year(y)
  if (!file.exists(zp)) stop("Missing raw archive: ", zp)
  g0_hash <- g0_annual[year == y, raw_sha256]
  if (length(g0_hash) != 1L) stop("Missing G0 raw hash for year ", y)
  actual_hash <- digest(zp, algo = "sha256", file = TRUE)
  if (!identical(actual_hash, g0_hash)) {
    stop("Raw archive differs from G0 for year ", y)
  }

  listing <- unzip(zp, list = TRUE)
  inner_candidates <- listing$Name[!grepl("/$", listing$Name)]
  if (!length(inner_candidates)) stop("No file inside ", basename(zp))
  inner <- inner_candidates[1]
  cmd <- sprintf("unzip -p %s %s", shQuote(zp), shQuote(inner))
  t0 <- Sys.time()

  header <- fread(cmd = cmd, sep = ";", header = TRUE, nrows = 0L,
                  fill = TRUE, quote = "\"", encoding = "Latin-1",
                  showProgress = FALSE)
  select_idx <- match(need_cols, toupper(names(header)))
  missing_cols <- need_cols[is.na(select_idx)]
  if (length(missing_cols)) {
    stop(sprintf("Year %d missing G1 columns: %s", y,
                 paste(missing_cols, collapse = ", ")))
  }

  dt <- fread(cmd = cmd, sep = ";", header = TRUE, fill = TRUE,
              quote = "\"", encoding = "Latin-1", select = select_idx,
              colClasses = "character", nThread = min(4L, getDTthreads()),
              showProgress = FALSE)
  setnames(dt, toupper(names(dt)))
  if (!identical(names(dt), need_cols)) setcolorder(dt, need_cols)
  for (v in need_cols) set(dt, j = v, value = clean_text(dt[[v]]))

  child_parts <- date_parts(dt$DTNASC)
  child_valid_file <- child_parts$valid & child_parts$year == y
  child_valid_file[is.na(child_valid_file)] <- FALSE
  reported_age <- suppressWarnings(as.integer(dt$IDADEMAE))
  geo_valid <- !is.na(dt$CODMUNRES) & grepl("^[1-5]", dt$CODMUNRES)
  age_geo_idx <- which(reported_age %in% c(15L, 16L) & geo_valid)

  d <- dt[age_geo_idx]
  d[, reported_age := reported_age[age_geo_idx]]
  d[, `:=`(
    child_day = child_parts$day[age_geo_idx],
    child_month = child_parts$month[age_geo_idx],
    child_year = child_parts$year[age_geo_idx],
    child_valid_file = child_valid_file[age_geo_idx]
  )]
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

  completed_age <- rep.int(NA_integer_, nrow(d))
  basic_pair <- d$child_valid_file & mother_parts$valid & mother_precedes
  birthday_not_reached <- d$child_month < mother_parts$month |
    (d$child_month == mother_parts$month & d$child_day < mother_parts$day)
  completed_age[basic_pair] <-
    d$child_year[basic_pair] - mother_parts$year[basic_pair] -
    as.integer(birthday_not_reached[basic_pair])
  plausible_age <- !is.na(completed_age) &
    completed_age >= 8L & completed_age <= 59L

  birthday_year <- mother_parts$year + 16L
  birthday_valid <- mother_parts$valid &
    gregorian_valid(mother_parts$day, mother_parts$month, birthday_year)
  exact_base <- basic_pair & plausible_age
  if (any(exact_base & !birthday_valid)) {
    stop("Impossible sixteenth birthday detected for year ", y)
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

  singleton <- !is.na(d$GRAVIDEZ) & d$GRAVIDEZ == "1"
  age_agree <- exact_valid & completed_age == d$reported_age
  in_density_support <- singleton & age_agree & !is.na(x_days) &
    x_days >= -180L & x_days <= 180L
  keep <- which(in_density_support)

  sample_list[[i]] <- data.table(
    year = y,
    era = era,
    post = as.integer(era == "post"),
    x_days = x_days[keep],
    above = as.integer(x_days[keep] >= 0L),
    side = ifelse(x_days[keep] < 0L, "below", "above"),
    birth_month = d$child_month[keep],
    municipality = d$CODMUNRES[keep],
    residence_region = substr(d$CODMUNRES[keep], 1L, 1L),
    child_date_id = as.integer(child_date[keep]),
    status_valid = d$ESTCIVMAE[keep] %chin% as.character(1:5),
    race_code = d$RACACORMAE[keep],
    birthplace_region = fifelse(
      !is.na(d$CODUFNATU[keep]) &
        substr(d$CODUFNATU[keep], 1L, 1L) %chin% as.character(1:5),
      substr(d$CODUFNATU[keep], 1L, 1L), NA_character_
    ),
    school_code_raw = d$ESCMAE2010[keep],
    school_aggregate_raw = d$ESCMAEAGR1[keep],
    prior_live_children_raw = d$QTDFILVIVO[keep]
  )
  sample_list[[i]][, status_missing := as.integer(!status_valid)]

  schema_list[[i]] <- data.table(
    year = y,
    era = era,
    zip_file = basename(zp),
    raw_sha256 = actual_hash,
    g0_raw_sha256_match = TRUE,
    required_g1_schema_complete = TRUE,
    n_density_support_inclusive = nrow(sample_list[[i]])
  )

  log_line(sprintf(
    "year=%d | density_support=%s | %.1fs | RSS=%.0fMB",
    y, fmt_int(nrow(sample_list[[i]])),
    as.numeric(difftime(Sys.time(), t0, units = "secs")), rss_mb()
  ))

  rm(dt, d, header, child_parts, child_date, mother_parts, mother_date,
     sixteenth_birthday, reported_age, geo_valid)
  gc(verbose = FALSE)
}

g1_sample <- rbindlist(sample_list, use.names = TRUE)
schema_audit <- rbindlist(schema_list, use.names = TRUE)
setorder(g1_sample, year, x_days)

# Reconcile every positive-kernel G1 sample cell with the already validated G0.
sample_rec_list <- list()
for (h in bands) {
  x <- g1_sample[abs(x_days) < h, .(
    g1_n_singleton = .N,
    g1_n_valid_status = sum(status_valid)
  ), by = .(year, era, side)]
  ref <- g0_side[bandwidth_days == h, .(
    year, era, side,
    g0_n_singleton = n_singleton,
    g0_n_valid_status = n_valid_status_singleton
  )]
  z <- merge(ref, x, by = c("year", "era", "side"), all = TRUE)
  z[, `:=`(
    bandwidth_days = h,
    singleton_count_match = g1_n_singleton == g0_n_singleton,
    valid_status_count_match = g1_n_valid_status == g0_n_valid_status
  )]
  sample_rec_list[[length(sample_rec_list) + 1L]] <- z
}
sample_reconciliation <- rbindlist(sample_rec_list, use.names = TRUE)
setcolorder(sample_reconciliation, c(
  "year", "era", "bandwidth_days", "side", "g0_n_singleton",
  "g1_n_singleton", "singleton_count_match", "g0_n_valid_status",
  "g1_n_valid_status", "valid_status_count_match"
))
setorder(sample_reconciliation, year, bandwidth_days, side)
if (!all(sample_reconciliation$singleton_count_match) ||
    !all(sample_reconciliation$valid_status_count_match)) {
  stop("G1 sample does not reproduce G0 counts")
}

# Exact daily counts and equal-day heaping diagnostics. No outcome is present.
daily <- g1_sample[, .(n_births = .N), by = .(era, x_days)]
daily_grid <- CJ(era = c("pre", "post"), x_days = -180:180, unique = TRUE)
daily <- merge(daily_grid, daily, by = c("era", "x_days"),
               all.x = TRUE, sort = FALSE)
daily[is.na(n_births), n_births := 0L]
daily[, side := ifelse(x_days < 0L, "below", "above")]
daily[, era_order := match(era, c("pre", "post"))]
setorder(daily, era_order, x_days)
daily[, era_order := NULL]

equal_day_list <- list()
for (e in c("pre", "post")) {
  for (k in c(7L, 14L, 30L)) {
    n_left <- daily[era == e & x_days >= -k & x_days <= -1L, sum(n_births)]
    n_right <- daily[era == e & x_days >= 0L & x_days <= k - 1L,
                     sum(n_births)]
    bt <- binom.test(n_right, n_left + n_right, p = 0.5)
    equal_day_list[[length(equal_day_list) + 1L]] <- data.table(
      era = e,
      k_days_each_side = k,
      left_window = sprintf("-%d..-1", k),
      right_window = sprintf("0..%d", k - 1L),
      n_left = as.numeric(n_left),
      n_right = as.numeric(n_right),
      right_left_ratio = n_right / n_left,
      log_right_left_ratio = log(n_right / n_left),
      exact_binomial_p_value = bt$p.value,
      diagnostic_only = TRUE
    )
  }
}
equal_day_counts <- rbindlist(equal_day_list)

daily[, weekly_bin := ifelse(
  x_days < 0L,
  -ceiling(abs(x_days) / 7),
  floor(x_days / 7)
)]
weekly <- daily[, .(
  bin_start = min(x_days),
  bin_end = max(x_days),
  bin_midpoint = mean(range(x_days)),
  n_calendar_days = .N,
  n_births = sum(n_births),
  births_per_age_day = mean(n_births)
), by = .(era, weekly_bin)]
setorder(weekly, era, bin_start)
daily[, weekly_bin := NULL]

# Frozen rddensity implementation from prospective amendment A002.
log_ratio_threshold <- abs(log(1.05))
density_rows <- list()
binomial_rows <- list()
for (e in c("pre", "post")) {
  x <- g1_sample[era == e, x_days]
  captured_warnings <- character()
  error_message <- NA_character_
  fit <- tryCatch(
    withCallingHandlers(
      rddensity(
        X = x,
        c = 0,
        p = 2,
        q = 3,
        fitselect = "unrestricted",
        kernel = "triangular",
        vce = "jackknife",
        massPoints = TRUE,
        bwselect = "comb",
        all = TRUE,
        regularize = TRUE,
        bino = TRUE
      ),
      warning = function(w) {
        captured_warnings <<- c(captured_warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e2) {
      error_message <<- conditionMessage(e2)
      NULL
    }
  )

  if (is.null(fit)) {
    density_rows[[length(density_rows) + 1L]] <- data.table(
      era = e, identified = FALSE, error_message = error_message,
      warnings = paste(unique(captured_warnings), collapse = " | ")
    )
    next
  }

  density_left <- as.numeric(fit$hat$left)
  density_right <- as.numeric(fit$hat$right)
  identified <- all(is.finite(c(density_left, density_right,
                                fit$test$p_jk))) &&
    density_left > 0 && density_right > 0
  log_ratio <- if (identified) log(density_right / density_left) else NA_real_
  rejects <- identified && fit$test$p_jk < 0.05
  exceeds <- identified && abs(log_ratio) > log_ratio_threshold
  hard_failure <- identified && rejects && exceeds
  density_rows[[length(density_rows) + 1L]] <- data.table(
    era = e,
    identified = identified,
    n_full = as.numeric(fit$N$full),
    n_left = as.numeric(fit$N$left),
    n_right = as.numeric(fit$N$right),
    bandwidth_left_days = as.numeric(fit$h$left),
    bandwidth_right_days = as.numeric(fit$h$right),
    effective_n_left = as.numeric(fit$N$eff_left),
    effective_n_right = as.numeric(fit$N$eff_right),
    robust_density_left = density_left,
    robust_density_right = density_right,
    robust_density_difference = as.numeric(fit$hat$diff),
    robust_jackknife_se_difference = as.numeric(fit$sd_jk$diff),
    robust_test_statistic = as.numeric(fit$test$t_jk),
    robust_p_value = as.numeric(fit$test$p_jk),
    log_right_left_density_ratio = log_ratio,
    abs_log_ratio_threshold = log_ratio_threshold,
    rejects_equality_at_5pct = rejects,
    exceeds_five_percent_log_threshold = exceeds,
    density_hard_failure = hard_failure,
    conventional_density_left = as.numeric(fit$hat_p$left),
    conventional_density_right = as.numeric(fit$hat_p$right),
    conventional_p_value = as.numeric(fit$test_p$p_jk),
    mass_points_adjusted = isTRUE(fit$opt$massPoints),
    polynomial_p = as.integer(fit$opt$p),
    bias_correction_q = as.integer(fit$opt$q),
    bandwidth_selector = "comb",
    error_message = error_message,
    warnings = paste(unique(captured_warnings), collapse = " | ")
  )

  if (!is.null(fit$bino) && length(fit$bino$pval)) {
    binomial_rows[[length(binomial_rows) + 1L]] <- data.table(
      era = e,
      window_index = seq_along(fit$bino$pval),
      left_window_days = as.numeric(fit$bino$LeftWindow),
      right_window_days = as.numeric(fit$bino$RightWindow),
      n_left = as.numeric(fit$bino$LeftN),
      n_right = as.numeric(fit$bino$RightN),
      p_value = as.numeric(fit$bino$pval),
      diagnostic_only = TRUE
    )
  }
}
density <- rbindlist(density_rows, use.names = TRUE, fill = TRUE)
density_binomial <- rbindlist(binomial_rows, use.names = TRUE, fill = TRUE)

# Weekly-binned density figure required by G1.
weekly_plot <- copy(weekly)
weekly_plot[, era_label := factor(
  era,
  levels = c("pre", "post"),
  labels = c("Pre-law: 2016-2018", "Mature post-law: 2022-2024")
)]
p_density <- ggplot(weekly_plot,
                    aes(x = bin_midpoint, y = births_per_age_day)) +
  geom_vline(xintercept = 0, linewidth = 0.35, linetype = "dashed",
             colour = "grey35") +
  geom_line(linewidth = 0.55, colour = "#246B8E") +
  geom_point(size = 1.15, colour = "#246B8E") +
  facet_wrap(~era_label, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(-180, 180, by = 30)) +
  labs(
    title = "SINASC births by exact distance from the mother's 16th birthday",
    subtitle = "Seven-day bins; data-quality density diagnostic only",
    x = "Calendar days from the 16th birthday",
    y = "Mean births per exact age-day"
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = "none")

figure_pdf <- file.path(figure_dir, "FIGURE_SINASC_DAILY_G1_DENSITY.pdf")
figure_png <- file.path(figure_dir, "FIGURE_SINASC_DAILY_G1_DENSITY.png")
ggsave(figure_pdf, p_density, width = 8.0, height = 6.2, units = "in",
       device = cairo_pdf)
ggsave(figure_png, p_density, width = 8.0, height = 6.2, units = "in",
       dpi = 180)

# Common h=90 stacked local-linear design. The status-valid restriction applies
# to covariates; the status-missingness outcome is fitted before that restriction.
prepare_model_data <- function(z) {
  z <- copy(z[abs(x_days) < 90L])
  z[, triangular_weight := pmax(0, 1 - abs(x_days) / 90)]
  z[, `:=`(
    above_post = above * post,
    above_x = above * x_days,
    post_x = post * x_days,
    above_post_x = above * post * x_days
  )]
  z
}
missing_model_data <- prepare_model_data(g1_sample)
continuity_data <- missing_model_data[status_valid == TRUE]

fit_stacked_binary <- function(outcome, data) {
  z <- copy(data)
  z[, g1_diagnostic_outcome := as.numeric(outcome)]
  err <- NA_character_
  warn <- character()
  fit <- tryCatch(
    withCallingHandlers(
      feols(
        g1_diagnostic_outcome ~ above + above_post + x_days + above_x +
          post_x + above_post_x | year + birth_month,
        data = z,
        weights = ~triangular_weight,
        vcov = ~municipality + child_date_id,
        notes = FALSE,
        warn = TRUE
      ),
      warning = function(w) {
        warn <<- c(warn, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      err <<- conditionMessage(e)
      NULL
    }
  )
  if (is.null(fit) || !"above_post" %in% names(coef(fit))) {
    if (is.na(err)) err <- "above_post coefficient not identified"
    return(list(identified = FALSE, estimate = NA_real_, se = NA_real_,
                p = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
                n = nrow(z), error = err,
                warnings = paste(unique(warn), collapse = " | ")))
  }
  ct <- coeftable(fit)
  p_col <- grep("^Pr\\(", colnames(ct), value = TRUE)
  ci <- tryCatch(
    confint(fit, parm = "above_post", level = 0.95),
    error = function(e) NULL
  )
  est <- unname(coef(fit)["above_post"])
  se <- unname(ct["above_post", "Std. Error"])
  pval <- if (length(p_col)) unname(ct["above_post", p_col[1]]) else NA_real_
  ci_low <- if (!is.null(ci)) as.numeric(ci[1, 1]) else est - qnorm(0.975) * se
  ci_high <- if (!is.null(ci)) as.numeric(ci[1, 2]) else est + qnorm(0.975) * se
  list(
    identified = all(is.finite(c(est, se, pval, ci_low, ci_high))),
    estimate = est,
    se = se,
    p = pval,
    ci_low = ci_low,
    ci_high = ci_high,
    n = nobs(fit),
    error = err,
    warnings = paste(unique(warn), collapse = " | ")
  )
}

feature_values <- list()
feature_meta <- list()
add_feature <- function(id, label, family, gate_role, values) {
  feature_values[[id]] <<- as.integer(values)
  feature_meta[[length(feature_meta) + 1L]] <<- data.table(
    variable_id = id,
    variable_label = label,
    family = family,
    gate_role = gate_role
  )
}

race_names <- c("white", "black", "yellow", "brown", "indigenous")
region_names <- c("north", "northeast", "southeast", "south", "center_west")
for (j in 1:5) {
  add_feature(
    paste0("race_", race_names[j]),
    paste("Maternal race/color:", race_names[j]),
    "predetermined_hard", "hard_gate",
    !is.na(continuity_data$race_code) &
      continuity_data$race_code == as.character(j)
  )
}
for (j in 1:5) {
  add_feature(
    paste0("birthplace_", region_names[j]),
    paste("Maternal birthplace region:", region_names[j]),
    "predetermined_hard", "hard_gate",
    !is.na(continuity_data$birthplace_region) &
      continuity_data$birthplace_region == as.character(j)
  )
}
add_feature(
  "race_unknown", "Maternal race/color unknown",
  "predetermined_missingness", "diagnostic_only",
  is.na(continuity_data$race_code) |
    !continuity_data$race_code %chin% as.character(1:5)
)
add_feature(
  "birthplace_unknown", "Maternal birthplace region unknown/foreign",
  "predetermined_missingness", "diagnostic_only",
  is.na(continuity_data$birthplace_region)
)

school_int <- suppressWarnings(as.integer(continuity_data$school_code_raw))
school_valid <- !is.na(school_int) & school_int %in% 0:5
school_names <- c("none", "fundamental_i", "fundamental_ii", "secondary",
                  "higher_incomplete", "higher_complete")
for (j in 0:5) {
  add_feature(
    paste0("school_", school_names[j + 1L]),
    paste("ESCMAE2010 category", j),
    "composition", "diagnostic_only",
    school_valid & school_int == j
  )
}
add_feature(
  "school_unknown", "ESCMAE2010 unknown/invalid",
  "composition", "diagnostic_only", !school_valid
)

prior_live <- suppressWarnings(as.integer(continuity_data$prior_live_children_raw))
prior_live_valid <- !is.na(prior_live) & prior_live >= 0L & prior_live <= 98L
add_feature(
  "primiparous", "No prior live-born child (QTDFILVIVO=0)",
  "composition", "diagnostic_only", prior_live_valid & prior_live == 0L
)
add_feature(
  "primiparity_unknown", "QTDFILVIVO unknown/invalid",
  "composition", "diagnostic_only", !prior_live_valid
)
for (j in 1:5) {
  add_feature(
    paste0("residence_", region_names[j]),
    paste("Residence region:", region_names[j]),
    "composition", "diagnostic_only",
    continuity_data$residence_region == as.character(j)
  )
}
feature_meta <- rbindlist(feature_meta)
stopifnot(feature_meta[family == "predetermined_hard", .N] == 10L)
stopifnot(feature_meta[family == "composition", .N] == 14L)

continuity_rows <- vector("list", nrow(feature_meta))
for (j in seq_len(nrow(feature_meta))) {
  id <- feature_meta$variable_id[j]
  values <- feature_values[[id]]
  fit <- fit_stacked_binary(values, continuity_data)
  sd_weighted <- weighted_sd_population(values,
                                        continuity_data$triangular_weight)
  estimate_pp <- 100 * fit$estimate
  continuity_rows[[j]] <- data.table(
    variable_id = id,
    variable_label = feature_meta$variable_label[j],
    family = feature_meta$family[j],
    gate_role = feature_meta$gate_role[j],
    identified = fit$identified,
    n = as.numeric(fit$n),
    weighted_mean = weighted.mean(
      values, continuity_data$triangular_weight
    ),
    weighted_sd = sd_weighted,
    above_x_post_pp = estimate_pp,
    std_error_pp = 100 * fit$se,
    ci95_low_pp = 100 * fit$ci_low,
    ci95_high_pp = 100 * fit$ci_high,
    p_value = fit$p,
    absolute_standardized_magnitude =
      ifelse(sd_weighted > 0, abs(fit$estimate) / sd_weighted, NA_real_),
    error_message = fit$error,
    warnings = fit$warnings
  )
  log_line(sprintf("continuity=%s | family=%s | identified=%s",
                   id, feature_meta$family[j], fit$identified))
}
continuity <- rbindlist(continuity_rows, use.names = TRUE, fill = TRUE)
continuity[, holm_family_size := .N, by = family]
continuity[, p_value_holm := p.adjust(p_value, method = "holm"), by = family]
continuity[, hard_failure :=
             family == "predetermined_hard" & identified &
             p_value_holm < 0.05 & absolute_standardized_magnitude >= 0.10]

status_fit <- fit_stacked_binary(missing_model_data$status_missing,
                                 missing_model_data)
status_missingness <- data.table(
  outcome = "invalid_or_missing_ESTCIVMAE",
  definition = "ESTCIVMAE outside codes 1-5",
  identified = status_fit$identified,
  n = as.numeric(status_fit$n),
  above_x_post_pp = 100 * status_fit$estimate,
  std_error_pp = 100 * status_fit$se,
  ci95_low_pp = 100 * status_fit$ci_low,
  ci95_high_pp = 100 * status_fit$ci_high,
  p_value = status_fit$p,
  magnitude_threshold_pp = 0.50,
  rejects_at_5pct = status_fit$identified && status_fit$p < 0.05,
  exceeds_magnitude_threshold = status_fit$identified &&
    abs(100 * status_fit$estimate) >= 0.50,
  hard_failure = status_fit$identified && status_fit$p < 0.05 &&
    abs(100 * status_fit$estimate) >= 0.50,
  error_message = status_fit$error,
  warnings = status_fit$warnings
)

density_status <- if (any(!density$identified)) {
  "QUALIFIED"
} else if (any(density$density_hard_failure)) {
  "FAIL"
} else {
  "PASS"
}
pred_hard <- continuity[family == "predetermined_hard"]
pred_status <- if (any(!pred_hard$identified)) {
  "QUALIFIED"
} else if (any(pred_hard$hard_failure)) {
  "FAIL"
} else {
  "PASS"
}
missing_status <- if (!status_missingness$identified) {
  "QUALIFIED"
} else if (status_missingness$hard_failure) {
  "FAIL"
} else {
  "PASS"
}
overall_status <- if (any(c(density_status, pred_status, missing_status) ==
                          "FAIL")) {
  "FAIL"
} else if (any(c(density_status, pred_status, missing_status) ==
                 "QUALIFIED")) {
  "QUALIFIED"
} else {
  "PASS"
}

g1_gate <- rbindlist(list(
  data.table(
    criterion = "G0_precondition",
    threshold = "G0_OVERALL=PASS and output hashes unchanged",
    observed = "PASS",
    hard_failures = 0L,
    status = "PASS"
  ),
  data.table(
    criterion = "density_by_primary_era",
    threshold = "hard fail if robust p<0.05 AND abs(log density ratio)>abs(log(1.05))",
    observed = sprintf("%d identified; %d hard failures",
                       sum(density$identified),
                       sum(density$density_hard_failure, na.rm = TRUE)),
    hard_failures = sum(density$density_hard_failure, na.rm = TRUE),
    status = density_status
  ),
  data.table(
    criterion = "predetermined_covariate_continuity",
    threshold = "hard fail if Holm p<0.05 AND abs standardized magnitude>=0.10",
    observed = sprintf("%d/10 identified; %d hard failures",
                       sum(pred_hard$identified),
                       sum(pred_hard$hard_failure, na.rm = TRUE)),
    hard_failures = sum(pred_hard$hard_failure, na.rm = TRUE),
    status = pred_status
  ),
  data.table(
    criterion = "status_missingness_continuity",
    threshold = "hard fail if p<0.05 AND abs coefficient>=0.50 pp",
    observed = if (status_missingness$identified) {
      sprintf("coefficient %.6f pp; p=%.6g",
              status_missingness$above_x_post_pp,
              status_missingness$p_value)
    } else {
      "not identified"
    },
    hard_failures = as.integer(status_missingness$hard_failure),
    status = missing_status
  ),
  data.table(
    criterion = "composition_family",
    threshold = "diagnostic only; Holm within 14 prespecified indicators",
    observed = sprintf("%d/14 identified; %d Holm p<0.05",
                       continuity[family == "composition", sum(identified)],
                       continuity[family == "composition",
                                  sum(p_value_holm < 0.05, na.rm = TRUE)]),
    hard_failures = 0L,
    status = "DIAGNOSTIC_ONLY"
  ),
  data.table(
    criterion = "G1_OVERALL",
    threshold = "no hard failure and no required non-identification",
    observed = overall_status,
    hard_failures = sum(c(
      density$density_hard_failure,
      pred_hard$hard_failure,
      status_missingness$hard_failure
    ), na.rm = TRUE),
    status = overall_status
  )
), use.names = TRUE)

# Defensive scope guard: no primary marriage outcome exists in the analysis data.
forbidden_names <- c("married", "MARRIED", "uniao_estavel", "any_union",
                     "tau", "delay90")
export_objects <- list(schema_audit, sample_reconciliation, daily, weekly,
                       equal_day_counts, density, density_binomial, continuity,
                       status_missingness, g1_gate)
if (any(vapply(export_objects,
               function(z) any(names(z) %chin% forbidden_names), logical(1)))) {
  stop("A prohibited marriage-effect field reached a G1 output")
}

paths <- list(
  schema = file.path(audit_dir, "SINASC_DAILY_G1_SCHEMA_AUDIT.csv"),
  sample = file.path(audit_dir, "SINASC_DAILY_G1_SAMPLE_RECONCILIATION.csv"),
  daily = file.path(audit_dir, "SINASC_DAILY_G1_DAILY_COUNTS.csv"),
  weekly = file.path(audit_dir, "SINASC_DAILY_G1_WEEKLY_COUNTS.csv"),
  equal_day = file.path(audit_dir, "SINASC_DAILY_G1_EQUAL_DAY_COUNTS.csv"),
  density = file.path(audit_dir, "SINASC_DAILY_G1_DENSITY.csv"),
  density_binomial = file.path(audit_dir, "SINASC_DAILY_G1_DENSITY_BINOMIAL.csv"),
  continuity = file.path(audit_dir, "SINASC_DAILY_G1_CONTINUITY.csv"),
  status_missingness = file.path(audit_dir, "SINASC_DAILY_G1_STATUS_MISSINGNESS.csv"),
  gate = file.path(audit_dir, "SINASC_DAILY_G1_GATE_STATUS.csv"),
  report = file.path(analysis_dir, "SINASC_DAILY_GATE_G1.md"),
  figure_pdf = figure_pdf,
  figure_png = figure_png
)

fwrite(schema_audit, paths$schema, na = "")
fwrite(sample_reconciliation, paths$sample, na = "")
fwrite(daily, paths$daily, na = "")
fwrite(weekly, paths$weekly, na = "")
fwrite(equal_day_counts, paths$equal_day, na = "")
fwrite(density, paths$density, na = "")
fwrite(density_binomial, paths$density_binomial, na = "")
fwrite(continuity, paths$continuity, na = "")
fwrite(status_missingness, paths$status_missingness, na = "")
fwrite(g1_gate, paths$gate, na = "")

gate_lines <- c(
  "| Criterion | Threshold | Observed | Status |",
  "|---|---|---:|---|",
  vapply(seq_len(nrow(g1_gate)), function(j) sprintf(
    "| %s | %s | %s | **%s** |",
    g1_gate$criterion[j], g1_gate$threshold[j],
    g1_gate$observed[j], g1_gate$status[j]
  ), character(1))
)
density_lines <- c(
  "| Era | Robust p-value | Right/left density ratio | Log ratio | Rejects 5% | Exceeds 5% | Hard failure |",
  "|---|---:|---:|---:|---|---|---|",
  vapply(seq_len(nrow(density)), function(j) sprintf(
    "| %s | %s | %s | %s | %s | %s | %s |",
    density$era[j], fmt_num(density$robust_p_value[j], 6L),
    fmt_num(density$robust_density_right[j] /
              density$robust_density_left[j], 5L),
    fmt_num(density$log_right_left_density_ratio[j], 5L),
    density$rejects_equality_at_5pct[j],
    density$exceeds_five_percent_log_threshold[j],
    density$density_hard_failure[j]
  ), character(1))
)
count_lines <- c(
  "| Era | Days per side | Below | Above | Above/below | Exact binomial p |",
  "|---|---:|---:|---:|---:|---:|",
  vapply(seq_len(nrow(equal_day_counts)), function(j) sprintf(
    "| %s | %d | %s | %s | %s | %s |",
    equal_day_counts$era[j], equal_day_counts$k_days_each_side[j],
    fmt_int(equal_day_counts$n_left[j]), fmt_int(equal_day_counts$n_right[j]),
    fmt_num(equal_day_counts$right_left_ratio[j], 5L),
    fmt_num(equal_day_counts$exact_binomial_p_value[j], 6L)
  ), character(1))
)
hard_cont <- continuity[family == "predetermined_hard"]
continuity_lines <- c(
  "| Covariate | Above x post (pp) | Holm p | Abs. standardized | Hard failure |",
  "|---|---:|---:|---:|---|",
  vapply(seq_len(nrow(hard_cont)), function(j) sprintf(
    "| %s | %s | %s | %s | %s |",
    hard_cont$variable_id[j], fmt_num(hard_cont$above_x_post_pp[j], 5L),
    fmt_num(hard_cont$p_value_holm[j], 6L),
    fmt_num(hard_cont$absolute_standardized_magnitude[j], 5L),
    hard_cont$hard_failure[j]
  ), character(1))
)

report_lines <- c(
  "# SINASC daily design — Gate G1",
  "",
  sprintf("**Status: %s.**", overall_status),
  "",
  sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "This artifact implements only density/heaping, predetermined-covariate",
  "continuity, non-hard composition, and status-missingness diagnostics. It does",
  "not construct or estimate the married-status outcome, a policy effect, G2",
  "placebos, or any G3 estimand.",
  "",
  "## Decision",
  "",
  gate_lines,
  "",
  "## Density test",
  "",
  density_lines,
  "",
  sprintf("The frozen magnitude threshold is `abs(log(1.05)) = %.6f`. A hard",
          log_ratio_threshold),
  "failure requires both robust p<0.05 and a larger absolute log ratio in either",
  "era. Exact equal-day counts below are diagnostics and cannot reverse that rule.",
  "",
  "## Equal-day count diagnostics",
  "",
  count_lines,
  "",
  "## Hard predetermined continuity family",
  "",
  continuity_lines,
  "",
  "Holm adjustment covers all ten valid race/color and maternal-birthplace-region",
  "indicators. A hard failure requires both adjusted p<0.05 and absolute",
  "standardized magnitude at least 0.10. Unknown-category tests and all 14",
  "schooling, primiparity, and residence indicators remain diagnostic only in the",
  "full continuity CSV.",
  "",
  "## Status missingness",
  "",
  sprintf("The post-minus-pre change in the age-16 missing-status discontinuity is %s pp (p=%s).",
          fmt_num(status_missingness$above_x_post_pp, 6L),
          fmt_num(status_missingness$p_value, 6L)),
  sprintf("Hard-failure threshold: p<0.05 and absolute magnitude at least 0.50 pp. Result: `%s`.",
          status_missingness$hard_failure),
  "",
  "## Artifacts",
  "",
  vapply(unlist(paths, use.names = FALSE), function(p) sprintf(
    "- `%s`", sub(paste0("^", root, "/"), "", p)
  ), character(1)),
  "",
  "The filter order and estimator details follow prospective amendment A002,",
  "recorded before the first G1 statistic. G2 and G3 were not run. A G1 hard",
  "failure restricts this design to descriptive use under the frozen protocol."
)
writeLines(report_lines, paths$report, useBytes = TRUE)

manifest_files <- unlist(paths, use.names = TRUE)
output_manifest <- data.table(
  artifact = sub(paste0("^", root, "/"), "", manifest_files),
  sha256 = vapply(manifest_files, digest, character(1),
                  algo = "sha256", file = TRUE),
  scope = "G1_only_no_marriage_effect_estimation"
)
manifest_path <- file.path(audit_dir, "SINASC_DAILY_G1_OUTPUT_MANIFEST.csv")
fwrite(output_manifest, manifest_path)

elapsed <- as.numeric(difftime(Sys.time(), started, units = "mins"))
log_line(sprintf(
  "done | G1=%s | density_hard=%d | predetermined_hard=%d | status_hard=%d | outputs=%d | %.2f min | RSS=%.0fMB",
  overall_status,
  sum(density$density_hard_failure, na.rm = TRUE),
  sum(pred_hard$hard_failure, na.rm = TRUE),
  sum(status_missingness$hard_failure, na.rm = TRUE),
  nrow(output_manifest) + 1L, elapsed, rss_mb()
))
cat(sprintf("SINASC_DAILY_G1_STATUS=%s\n", overall_status))

if (identical(overall_status, "FAIL")) quit(save = "no", status = 2L)
