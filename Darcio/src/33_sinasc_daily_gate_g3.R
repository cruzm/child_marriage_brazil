#!/usr/bin/env Rscript
# 33_sinasc_daily_gate_g3.R — implement Gate G3 of the frozen SINASC
# exact-age protocol. This is the first script permitted to estimate the full
# age-16 policy contrast, DELAY90, secondary outcomes, and frozen sensitivities.
# It preserves the qualified G2 verdict and writes only aggregate artifacts.

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
  library(rdrobust)
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

log_file <- file.path(log_dir, "33_sinasc_daily_gate_g3.log")
writeLines(character(), log_file)

log_line <- function(...) {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S%z"),
                 paste0(...))
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

rss_mb <- function() {
  z <- readLines("/proc/self/status", warn = FALSE)
  hit <- grep("^VmRSS:", z, value = TRUE)
  if (!length(hit)) return(NA_real_)
  as.numeric(strsplit(trimws(hit), "[[:space:]]+")[[1]][2]) / 1024
}

free_mem_gib <- function() {
  z <- readLines("/proc/meminfo", warn = FALSE)
  hit <- grep("^MemAvailable:", z, value = TRUE)
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

fmt_num <- function(x, digits = 5L) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_p <- function(x) {
  ifelse(is.na(x), "NA", formatC(x, digits = 6L, format = "g"))
}

fmt_int <- function(x) {
  ifelse(is.na(x), "NA", format(x, big.mark = ",", scientific = FALSE,
                                 trim = TRUE))
}

near <- function(x, y, tolerance = 1e-8) {
  length(x) == length(y) &&
    all((is.na(x) & is.na(y)) |
          (!is.na(x) & !is.na(y) &
             abs(x - y) <= tolerance * pmax(1, abs(x), abs(y))))
}

validate_output_manifest <- function(path) {
  z <- fread(path)
  p <- file.path(root, z$artifact)
  if (!all(file.exists(p))) return(FALSE)
  actual <- vapply(p, digest, character(1), algo = "sha256", file = TRUE)
  identical(unname(actual), unname(z$sha256))
}

extract_ci <- function(fit, coefficient, level) {
  out <- tryCatch(confint(fit, parm = coefficient, level = level),
                  error = function(e) NULL)
  if (is.null(out)) return(c(NA_real_, NA_real_))
  as.numeric(out[1, 1:2])
}

empty_fixest_result <- function(model_id, outcome_id, sample_id,
                                bandwidth_days, polynomial_order, vcov_id,
                                fixed_effects, donut_days, n, n_events,
                                n_municipalities, n_dates, n_distances,
                                error_message, warnings = "") {
  data.table(
    model_id = model_id,
    outcome_id = outcome_id,
    sample_id = sample_id,
    bandwidth_days = as.numeric(bandwidth_days),
    polynomial_order = as.integer(polynomial_order),
    vcov_id = vcov_id,
    fixed_effects = fixed_effects,
    donut_days = as.integer(donut_days),
    identified = FALSE,
    n = as.numeric(n),
    n_outcome_events = as.numeric(n_events),
    n_municipality_clusters = as.numeric(n_municipalities),
    n_date_clusters = as.numeric(n_dates),
    n_distance_clusters = as.numeric(n_distances),
    estimate_pp = NA_real_,
    std_error_pp = NA_real_,
    ci90_low_pp = NA_real_,
    ci90_high_pp = NA_real_,
    ci95_low_pp = NA_real_,
    ci95_high_pp = NA_real_,
    p_value = NA_real_,
    error_message = error_message,
    warnings = warnings
  )
}

registry_rows <- list()

fit_stacked <- function(model_id, z, outcome_column, outcome_id,
                        sample_id, bandwidth_days, polynomial_order = 1L,
                        vcov_id = "two_way", covariate_fe = FALSE,
                        donut_days = 0L, delay_parameterization = FALSE) {
  z <- copy(z)
  z[, g3_y := as.numeric(get(outcome_column))]
  z[, kernel_weight := pmax(0, 1 - abs(x_days) / bandwidth_days)]
  z[, `:=`(
    above_post = above * post,
    above_x = above * x_days,
    post_x = post * x_days,
    above_post_x = above * post * x_days,
    above_post_x_center45 = above * post * (x_days - 45),
    x_days_sq = x_days^2,
    above_x_sq = above * x_days^2,
    post_x_sq = post * x_days^2,
    above_post_x_sq = above * post * x_days^2
  )]

  rhs <- if (delay_parameterization) {
    paste("above + above_post + x_days + above_x + post_x +",
          "above_post_x_center45")
  } else if (polynomial_order == 2L) {
    paste("above + above_post + x_days + above_x + post_x + above_post_x +",
          "x_days_sq + above_x_sq + post_x_sq + above_post_x_sq")
  } else {
    "above + above_post + x_days + above_x + post_x + above_post_x"
  }
  fe <- if (covariate_fe) {
    "year + birth_month + residence_region_fe + race_fe"
  } else {
    "year + birth_month"
  }
  fml <- as.formula(sprintf("g3_y ~ %s | %s", rhs, fe))
  vcov_arg <- switch(
    vcov_id,
    two_way = as.formula("~ municipality + child_date_id"),
    distance = as.formula("~ x_days"),
    hc1 = "hetero",
    stop("Unknown covariance specification: ", vcov_id)
  )

  n_events <- sum(z$g3_y > 0, na.rm = TRUE)
  out <- empty_fixest_result(
    model_id, outcome_id, sample_id, bandwidth_days, polynomial_order,
    vcov_id, fe, donut_days, nrow(z), n_events,
    uniqueN(z$municipality), uniqueN(z$child_date_id), uniqueN(z$x_days),
    NA_character_
  )
  captured_warnings <- character()
  error_message <- NA_character_
  fit <- NULL
  if (nrow(z) && uniqueN(z$post) == 2L && uniqueN(z$above) == 2L &&
      all(is.finite(z$g3_y)) && all(z$kernel_weight > 0)) {
    fit <- tryCatch(
      withCallingHandlers(
        feols(
          fml, data = z, weights = ~kernel_weight, vcov = vcov_arg,
          notes = FALSE, warn = TRUE
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
  } else {
    error_message <- "model sample lacks finite outcomes, positive weights, eras, or sides"
  }

  coefficient <- "above_post"
  if (!is.null(fit) && coefficient %in% names(coef(fit))) {
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
    out[, `:=`(
      identified = all(is.finite(vals)) && vals["se"] > 0,
      n = as.numeric(nobs(fit)),
      estimate_pp = vals["estimate"],
      std_error_pp = vals["se"],
      p_value = vals["p"],
      ci90_low_pp = vals[4],
      ci90_high_pp = vals[5],
      ci95_low_pp = vals[6],
      ci95_high_pp = vals[7],
      warnings = paste(unique(captured_warnings), collapse = " | ")
    )]
  } else {
    if (is.na(error_message)) error_message <- paste(coefficient, "not identified")
    out[, `:=`(
      error_message = error_message,
      warnings = paste(unique(captured_warnings), collapse = " | ")
    )]
  }

  registry_rows[[length(registry_rows) + 1L]] <<- data.table(
    model_id = model_id,
    model_family = if (delay_parameterization) "delay_reparameterization" else
      "stacked_fixest",
    estimator = "fixest::feols",
    package_version = as.character(packageVersion("fixest")),
    outcome_id = outcome_id,
    sample_id = sample_id,
    reference_years = "2016,2017,2018",
    comparison_years = "2022,2023,2024",
    bandwidth_days = as.numeric(bandwidth_days),
    bias_bandwidth_days = NA_real_,
    polynomial_order = as.integer(polynomial_order),
    bias_polynomial_order = NA_integer_,
    kernel = "triangular",
    fixed_effects = fe,
    covariance = vcov_id,
    donut_days = as.integer(donut_days),
    masspoints = NA_character_,
    identified = out$identified,
    n = out$n,
    error_message = out$error_message,
    warnings = out$warnings
  )
  log_line("model=", model_id, " | identified=", out$identified,
           " | n=", fmt_int(out$n), " | estimate=", fmt_num(out$estimate_pp),
           " | RSS=", sprintf("%.0fMB", rss_mb()))
  list(fit = fit, result = out)
}

empty_rdrobust_row <- function(model_id, specification_id, era, h, b,
                               auto_bandwidth, n, n_events, error, warnings) {
  data.table(
    model_id = model_id,
    specification_id = specification_id,
    row_type = "era_jump",
    era = era,
    estimator = "rdrobust::rdrobust",
    outcome_id = "MARRIED",
    sample_id = ifelse(auto_bandwidth, "primary_full_available_support",
                       "primary_fixed_bandwidth"),
    auto_bandwidth = auto_bandwidth,
    bandwidth_selector = ifelse(auto_bandwidth, "mserd", "manual"),
    requested_h_days = as.numeric(h),
    requested_b_days = as.numeric(b),
    selected_h_left_days = NA_real_,
    selected_h_right_days = NA_real_,
    selected_b_left_days = NA_real_,
    selected_b_right_days = NA_real_,
    p = 1L,
    q = 2L,
    kernel = "triangular",
    vce = "nn",
    nnmatch = 3L,
    masspoints = "adjust",
    identified = FALSE,
    n_full_left = NA_real_,
    n_full_right = NA_real_,
    n_h_left = NA_real_,
    n_h_right = NA_real_,
    n_outcome_events_h = as.numeric(n_events),
    conventional_jump_pp = NA_real_,
    bias_corrected_jump_pp = NA_real_,
    robust_std_error_pp = NA_real_,
    robust_ci95_low_pp = NA_real_,
    robust_ci95_high_pp = NA_real_,
    robust_p_value = NA_real_,
    post_minus_pre_bias_corrected_pp = NA_real_,
    difference_inference_available = FALSE,
    error_message = error,
    warnings = warnings
  )
}

fit_rdrobust_era <- function(model_id, specification_id, z, era,
                             h = NA_real_, b = NA_real_,
                             auto_bandwidth = FALSE) {
  era_value <- era
  d <- z[get("era") == era_value]
  captured_warnings <- character()
  error_message <- NA_character_
  args <- list(
    y = d$married_pp,
    x = d$x_days,
    c = 0,
    p = 1,
    q = 2,
    kernel = "triangular",
    vce = "nn",
    nnmatch = 3,
    masspoints = "adjust"
  )
  if (auto_bandwidth) {
    args$bwselect <- "mserd"
  } else {
    args$h <- c(h, h)
    args$b <- c(b, b)
  }
  fit <- tryCatch(
    withCallingHandlers(
      do.call(rdrobust, args),
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
  out <- empty_rdrobust_row(
    model_id, specification_id, era, h, b, auto_bandwidth,
    nrow(d), sum(d$married > 0), error_message,
    paste(unique(captured_warnings), collapse = " | ")
  )
  if (!is.null(fit)) {
    h_left <- as.numeric(fit$bws["h", "left"])
    h_right <- as.numeric(fit$bws["h", "right"])
    b_left <- as.numeric(fit$bws["b", "left"])
    b_right <- as.numeric(fit$bws["b", "right"])
    vals <- c(
      fit$coef["Conventional", 1],
      fit$coef["Bias-Corrected", 1],
      fit$se["Robust", 1],
      fit$ci["Robust", 1:2],
      fit$pv["Robust", 1],
      h_left, h_right, b_left, b_right
    )
    out[, `:=`(
      selected_h_left_days = h_left,
      selected_h_right_days = h_right,
      selected_b_left_days = b_left,
      selected_b_right_days = b_right,
      identified = all(is.finite(vals)) && vals[3] > 0,
      n_full_left = as.numeric(fit$N[1]),
      n_full_right = as.numeric(fit$N[2]),
      n_h_left = as.numeric(fit$N_h[1]),
      n_h_right = as.numeric(fit$N_h[2]),
      n_outcome_events_h = as.numeric(sum(
        d$married > 0 & d$x_days >= -h_left & d$x_days <= h_right
      )),
      conventional_jump_pp = as.numeric(fit$coef["Conventional", 1]),
      bias_corrected_jump_pp = as.numeric(fit$coef["Bias-Corrected", 1]),
      robust_std_error_pp = as.numeric(fit$se["Robust", 1]),
      robust_ci95_low_pp = as.numeric(fit$ci["Robust", 1]),
      robust_ci95_high_pp = as.numeric(fit$ci["Robust", 2]),
      robust_p_value = as.numeric(fit$pv["Robust", 1])
    )]
  }

  registry_rows[[length(registry_rows) + 1L]] <<- data.table(
    model_id = model_id,
    model_family = "rdrobust_era_crosscheck",
    estimator = "rdrobust::rdrobust",
    package_version = as.character(packageVersion("rdrobust")),
    outcome_id = "MARRIED",
    sample_id = out$sample_id,
    reference_years = ifelse(era == "pre", "2016,2017,2018", NA_character_),
    comparison_years = ifelse(era == "post", "2022,2023,2024", NA_character_),
    bandwidth_days = ifelse(auto_bandwidth, mean(c(out$selected_h_left_days,
                                                   out$selected_h_right_days)), h),
    bias_bandwidth_days = ifelse(auto_bandwidth,
                                mean(c(out$selected_b_left_days,
                                       out$selected_b_right_days)), b),
    polynomial_order = 1L,
    bias_polynomial_order = 2L,
    kernel = "triangular",
    fixed_effects = "none",
    covariance = "nearest_neighbor_3",
    donut_days = 0L,
    masspoints = "adjust",
    identified = out$identified,
    n = out$n_full_left + out$n_full_right,
    error_message = out$error_message,
    warnings = out$warnings
  )
  log_line("model=", model_id, " | identified=", out$identified,
           " | jump_bc=", fmt_num(out$bias_corrected_jump_pp),
           " | RSS=", sprintf("%.0fMB", rss_mb()))
  out
}

# Construction unit checks before reading outcome data.
date_test <- date_parts(c("29022000", "29022001", "01012000", NA))
stopifnot(identical(date_test$valid, c(TRUE, FALSE, TRUE, FALSE)))
stopifnot(as.integer(as.IDate("2019-03-13") - as.IDate("2019-03-13")) == 0L)
stopifnot(near(2 + 45 * 0.1, 6.5))

lock_path <- file.path(root, "config", "sinasc_daily_lock.yml")
protocol_path <- file.path(root, "paper", "ledgers",
                           "SINASC_DAILY_PROTOCOL.md")
amendment_path <- file.path(root, "paper", "ledgers",
                            "SINASC_DAILY_AMENDMENTS.md")
hash_path <- file.path(root, "paper", "ledgers",
                       "SINASC_DAILY_LOCK_SHA256.txt")
g0_gate_path <- file.path(audit_dir, "SINASC_DAILY_GATE_STATUS.csv")
g1_gate_path <- file.path(audit_dir, "SINASC_DAILY_G1_GATE_STATUS.csv")
g2_gate_path <- file.path(audit_dir, "SINASC_DAILY_G2_GATE_STATUS.csv")
g0_manifest_path <- file.path(audit_dir,
                              "SINASC_DAILY_G0_OUTPUT_MANIFEST.csv")
g1_manifest_path <- file.path(audit_dir,
                              "SINASC_DAILY_G1_OUTPUT_MANIFEST.csv")
g2_manifest_path <- file.path(audit_dir,
                              "SINASC_DAILY_G2_OUTPUT_MANIFEST.csv")
g0_side_path <- file.path(audit_dir, "SINASC_DAILY_G0_SIDE_QUALITY.csv")
g0_band_path <- file.path(audit_dir, "SINASC_DAILY_G0_BAND_COUNTS.csv")
g0_annual_path <- file.path(audit_dir, "SINASC_DAILY_G0_ANNUAL.csv")
g1_binomial_path <- file.path(audit_dir,
                              "SINASC_DAILY_G1_DENSITY_BINOMIAL.csv")
raw_manifest_path <- file.path(sinasc_dir, "SHA256_MANIFEST.txt")
needed <- c(lock_path, protocol_path, amendment_path, hash_path, g0_gate_path,
            g1_gate_path, g2_gate_path, g0_manifest_path, g1_manifest_path,
            g2_manifest_path, g0_side_path, g0_band_path, g0_annual_path,
            g1_binomial_path, raw_manifest_path)
if (!all(file.exists(needed))) {
  stop("Missing G3 precondition(s): ",
       paste(needed[!file.exists(needed)], collapse = ", "))
}

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
frozen_actual <- vapply(frozen_rel, function(rel) {
  digest(file.path(root, rel), algo = "sha256", file = TRUE)
}, character(1))
if (anyNA(frozen_expected) ||
    !identical(unname(frozen_actual), unname(frozen_expected))) {
  stop("Frozen SINASC daily protocol hash check failed")
}
amendment_text <- paste(readLines(amendment_path, warn = FALSE), collapse = "\n")
if (!grepl("## A004 — Operational implementation of Gate G3",
           amendment_text, fixed = TRUE) ||
    !grepl("before its first run", amendment_text, fixed = TRUE)) {
  stop("Prospective G3 implementation amendment A004 is absent")
}

g0_gate <- fread(g0_gate_path)
g1_gate <- fread(g1_gate_path)
g2_gate <- fread(g2_gate_path)
g0_status <- g0_gate[criterion == "G0_OVERALL", status]
g1_status <- g1_gate[criterion == "G1_OVERALL", status]
g2_status <- g2_gate[criterion == "G2_OVERALL", status]
if (!identical(g0_status, "PASS") || !identical(g1_status, "PASS")) {
  stop("G3 requires G0=PASS and G1=PASS")
}
if (!g2_status %chin% c("PASS", "QUALIFIED")) {
  stop("G3 stops when G2 fails or is unavailable; observed ", g2_status)
}
if (!validate_output_manifest(g0_manifest_path) ||
    !validate_output_manifest(g1_manifest_path) ||
    !validate_output_manifest(g2_manifest_path)) {
  stop("A prior-gate output manifest changed before G3")
}
if (!identical(as.character(packageVersion("rdrobust")), "3.0.0")) {
  stop("G3 requires frozen rdrobust version 3.0.0")
}

lock <- read_yaml(lock_path)
pre_years <- as.integer(unlist(lock$periods$primary_pre_years))
post_years <- as.integer(unlist(lock$periods$primary_post_years))
years <- c(pre_years, post_years)
bands <- sort(unique(c(as.integer(lock$primary_estimator$bandwidth_days),
                       as.integer(unlist(
                         lock$frozen_sensitivity_set$bandwidths_days
                       )))))
donuts <- as.integer(unlist(lock$frozen_sensitivity_set$donut_windows_days))
margin_pp <- as.numeric(lock$gates$G3_primary_information$policy_relevant_margin_pp)
stopifnot(identical(years, c(2016:2018, 2022:2024)))
stopifnot(identical(bands, c(30L, 60L, 90L, 180L)))
stopifnot(identical(donuts, c(1L, 3L, 7L)))
stopifnot(identical(margin_pp, 0.25))

raw_manifest_lines <- readLines(raw_manifest_path, warn = FALSE)
raw_manifest <- data.table(
  raw_sha256_expected = sub("[[:space:]].*$", "", raw_manifest_lines),
  zip_file = sub("^[^[:space:]]+[[:space:]]+", "", raw_manifest_lines)
)
g0_annual <- fread(g0_annual_path)
need_cols <- c("DTNASC", "DTNASCMAE", "IDADEMAE", "ESTCIVMAE",
               "GRAVIDEZ", "CODMUNRES", "RACACORMAE")

sample_list <- vector("list", length(years))
schema_list <- vector("list", length(years))

log_line(
  "start | scope=G3_full_frozen_analysis | G0=", g0_status,
  " | G1=", g1_status, " | G2=", g2_status,
  " | protocol=", lock$protocol$version,
  " | post_result_protocol=", lock$protocol$post_result_protocol,
  " | R=", R.version$major, ".", R.version$minor,
  " | fixest=", as.character(packageVersion("fixest")),
  " | rdrobust=", as.character(packageVersion("rdrobust")),
  " | data.table=", as.character(packageVersion("data.table")),
  " | free_mem=", sprintf("%.1fGiB", free_mem_gib())
)

for (i in seq_along(years)) {
  y <- years[i]
  era_y <- ifelse(y %in% pre_years, "pre", "post")
  t0 <- Sys.time()
  zp <- file.path(sinasc_dir, sprintf("SINASC_%d_csv.zip", y))
  if (!file.exists(zp)) stop("Missing raw archive: ", zp)
  zip_name <- basename(zp)
  expected_hash <- raw_manifest[zip_file == zip_name, raw_sha256_expected]
  g0_hash <- g0_annual[year == y, raw_sha256]
  actual_hash <- digest(zp, algo = "sha256", file = TRUE)
  if (length(expected_hash) != 1L || length(g0_hash) != 1L ||
      !identical(actual_hash, expected_hash) ||
      !identical(actual_hash, g0_hash)) {
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
    stop(sprintf("Year %d missing G3 columns: %s", y,
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
  geo_valid_all <- !is.na(dt$CODMUNRES) & grepl("^[1-5]", dt$CODMUNRES)
  candidate_idx <- which(reported_age_all %in% c(15L, 16L) & geo_valid_all)
  d <- dt[candidate_idx]
  reported_age <- reported_age_all[candidate_idx]

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
  completed_age[exact_base] <- child_parts$year[exact_base] -
    mother_parts$year[exact_base] -
    as.integer(birthday_not_reached[exact_base])
  plausible <- !is.na(completed_age) & completed_age >= 8L &
    completed_age <= 59L
  age_agree <- exact_base & plausible & completed_age == reported_age

  birthday_year <- mother_parts$year + 16L
  birthday_valid <- mother_parts$valid & gregorian_valid(
    mother_parts$day, mother_parts$month, birthday_year
  )
  if (any(age_agree & !birthday_valid)) {
    stop("Impossible sixteenth birthday in year ", y)
  }
  birthday_parts <- list(day = mother_parts$day, month = mother_parts$month,
                         year = birthday_year, valid = birthday_valid)
  sixteenth_birthday <- idate_from_parts(birthday_parts, birthday_valid)
  locatable <- age_agree & birthday_valid & !is.na(sixteenth_birthday)
  x_days <- rep.int(NA_integer_, nrow(d))
  x_days[locatable] <- as.integer(
    child_date[locatable] - sixteenth_birthday[locatable]
  )
  keep <- which(locatable)
  bad_side <- (x_days[keep] < 0L & completed_age[keep] != 15L) |
    (x_days[keep] >= 0L & completed_age[keep] != 16L)
  if (any(bad_side)) stop("Completed-age side reconciliation failed for ", y)
  if (any(x_days[keep] < -366L | x_days[keep] > 366L)) {
    stop("Age-15/16 full support exceeded calendar bounds in year ", y)
  }

  residence_region <- substr(d$CODMUNRES[keep], 1L, 1L)
  residence_region_fe <- fifelse(
    residence_region %chin% as.character(1:5),
    residence_region, "unknown_invalid"
  )
  race_code <- d$RACACORMAE[keep]
  race_fe <- fifelse(race_code %chin% as.character(1:5),
                     race_code, "unknown_invalid")
  status_valid <- d$ESTCIVMAE[keep] %chin% as.character(1:5)
  singleton <- !is.na(d$GRAVIDEZ[keep]) & d$GRAVIDEZ[keep] == "1"
  pregnancy_known <- d$GRAVIDEZ[keep] %chin% as.character(1:3)

  sample_list[[i]] <- data.table(
    year = y,
    era = era_y,
    post = as.integer(era_y == "post"),
    x_days = x_days[keep],
    above = as.integer(x_days[keep] >= 0L),
    side = ifelse(x_days[keep] < 0L, "below", "above"),
    birth_month = child_parts$month[keep],
    municipality = d$CODMUNRES[keep],
    residence_region_fe = residence_region_fe,
    race_fe = race_fe,
    child_date_id = as.integer(child_date[keep]),
    status_valid = status_valid,
    singleton = singleton,
    pregnancy_known = pregnancy_known,
    married = as.integer(!is.na(d$ESTCIVMAE[keep]) &
                           d$ESTCIVMAE[keep] == "2"),
    uniao_estavel = as.integer(!is.na(d$ESTCIVMAE[keep]) &
                                 d$ESTCIVMAE[keep] == "5"),
    any_union = as.integer(d$ESTCIVMAE[keep] %chin% c("2", "5"))
  )
  sample_list[[i]][, `:=`(
    married_pp = 100 * married,
    uniao_estavel_pp = 100 * uniao_estavel,
    any_union_pp = 100 * any_union
  )]

  schema_list[[i]] <- data.table(
    year = y,
    era = era_y,
    zip_file = zip_name,
    zip_member = inner,
    raw_sha256 = actual_hash,
    raw_manifest_sha256_match = identical(actual_hash, expected_hash),
    g0_raw_sha256_match = identical(actual_hash, g0_hash),
    required_g3_schema_complete = TRUE,
    n_raw = as.numeric(n_raw),
    n_age15_16_valid_geography_candidates = as.numeric(length(candidate_idx)),
    n_locatable_age_agree = as.numeric(length(keep)),
    n_primary_valid_h180 = as.numeric(sample_list[[i]][
      singleton & status_valid & abs(x_days) < 180L, .N
    ]),
    full_support_min_days = min(x_days[keep]),
    full_support_max_days = max(x_days[keep])
  )
  log_line(sprintf(
    "year=%d | raw=%s | locatable=%s | primary_h180=%s | %.1fs | RSS=%.0fMB",
    y, fmt_int(n_raw), fmt_int(length(keep)),
    fmt_int(schema_list[[i]]$n_primary_valid_h180),
    as.numeric(difftime(Sys.time(), t0, units = "secs")), rss_mb()
  ))
  rm(dt, d, header, child_parts, mother_parts, child_date, mother_date,
     sixteenth_birthday, reported_age_all, reported_age)
  gc(verbose = FALSE)
}

g3_all <- rbindlist(sample_list, use.names = TRUE)
schema_audit <- rbindlist(schema_list, use.names = TRUE)
setorder(g3_all, year, x_days)
setorder(schema_audit, year)

model_sample <- function(sample_id, h = NULL, donut = 0L) {
  z <- switch(
    sample_id,
    primary = g3_all[singleton & status_valid],
    include_multiple = g3_all[pregnancy_known & status_valid],
    unknown_status_not_married = g3_all[singleton == TRUE],
    stop("Unknown G3 sample: ", sample_id)
  )
  if (!is.null(h)) z <- z[abs(x_days) < h]
  if (donut > 0L) z <- z[abs(x_days) > donut]
  copy(z)
}

primary_full <- model_sample("primary")
primary_h90 <- primary_full[abs(x_days) < 90L]
primary_h90[, triangular_weight := pmax(0, 1 - abs(x_days) / 90)]

# Exact reconciliation with all 48 G0 year x bandwidth x side cells.
g0_side <- fread(g0_side_path)
g0_band <- fread(g0_band_path)
rec_list <- list()
for (h in bands) {
  current <- primary_full[abs(x_days) < h, .(
    g3_n_births = .N,
    g3_n_married_events = sum(married)
  ), by = .(year, era, side)]
  reference <- merge(
    g0_side[bandwidth_days == h, .(
      year, era, side, g0_n_births = n_valid_status_singleton
    )],
    g0_band[aggregation == "year" & bandwidth_days == h, .(
      year, era, side, g0_n_married_events = n_married_events
    )],
    by = c("year", "era", "side"), all = TRUE
  )
  z <- merge(reference, current, by = c("year", "era", "side"), all = TRUE)
  z[, `:=`(
    bandwidth_days = h,
    birth_count_match = g3_n_births == g0_n_births,
    married_count_match = g3_n_married_events == g0_n_married_events
  )]
  rec_list[[length(rec_list) + 1L]] <- z
}
sample_reconciliation <- rbindlist(rec_list, use.names = TRUE)
setcolorder(sample_reconciliation, c(
  "year", "era", "bandwidth_days", "side", "g0_n_births",
  "g3_n_births", "birth_count_match", "g0_n_married_events",
  "g3_n_married_events", "married_count_match"
))
setorder(sample_reconciliation, year, bandwidth_days, side)
if (nrow(sample_reconciliation) != 48L ||
    !all(sample_reconciliation$birth_count_match) ||
    !all(sample_reconciliation$married_count_match)) {
  stop("G3 primary sample does not reproduce all G0 cells")
}

sample_audit_list <- list()
audit_samples <- c("primary", "include_multiple", "unknown_status_not_married")
for (s in audit_samples) {
  z <- model_sample(s, 90L)
  z[, sample_id := s]
  sample_audit_list[[length(sample_audit_list) + 1L]] <- z[, .(
    n_births = .N,
    n_married_events_internal = sum(married),
    n_status_invalid = sum(!status_valid),
    n_non_singleton_known = sum(pregnancy_known & !singleton)
  ), by = .(sample_id, era, side)]
}
primary_full_audit <- copy(primary_full)
primary_full_audit[, sample_id := "primary_full_available_support"]
sample_audit_list[[length(sample_audit_list) + 1L]] <- primary_full_audit[, .(
  n_births = .N,
  n_married_events_internal = sum(married),
  n_status_invalid = 0L,
  n_non_singleton_known = 0L
), by = .(sample_id, era, side)]
sample_audit <- rbindlist(sample_audit_list, use.names = TRUE)
sample_audit[, privacy_suppressed_married :=
               n_married_events_internal >= 1 &
               n_married_events_internal <= 9]
sample_audit[, n_married_events := fifelse(
  privacy_suppressed_married, NA_real_, as.numeric(n_married_events_internal)
)]
sample_audit[, n_married_events_internal := NULL]
setorder(sample_audit, sample_id, era, side)

# Primary tau and the algebraically equivalent DELAY90 parameterization.
primary_fit <- fit_stacked(
  "G3_PRIMARY_TAU", primary_h90, "married_pp", "MARRIED", "primary",
  90L, 1L, "two_way", FALSE, 0L, FALSE
)
delay_fit <- fit_stacked(
  "G3_DELAY90", primary_h90, "married_pp", "MARRIED", "primary",
  90L, 1L, "two_way", FALSE, 0L, TRUE
)
tau <- primary_fit$result
delay <- delay_fit$result

phi_estimate <- NA_real_
phi_se <- NA_real_
phi_p <- NA_real_
if (!is.null(primary_fit$fit) && "above_post_x" %in% names(coef(primary_fit$fit))) {
  phi_ct <- coeftable(primary_fit$fit)
  phi_p_col <- grep("^Pr\\(", colnames(phi_ct), value = TRUE)
  phi_estimate <- unname(coef(primary_fit$fit)["above_post_x"])
  phi_se <- unname(phi_ct["above_post_x", "Std. Error"])
  phi_p <- if (length(phi_p_col)) {
    unname(phi_ct["above_post_x", phi_p_col[1]])
  } else NA_real_
}
if (tau$identified && delay$identified &&
    !near(delay$estimate_pp, tau$estimate_pp + 45 * phi_estimate, 1e-7)) {
  stop("DELAY90 reparameterization does not equal tau + 45*phi")
}

joint_wald <- list(stat = NA_real_, p = NA_real_, df1 = NA_real_,
                   df2 = NA_real_, vcov = NA_character_)
if (!is.null(primary_fit$fit)) {
  joint_wald <- tryCatch(
    wald(primary_fit$fit, keep = "^above_post(_x)?$", print = FALSE),
    error = function(e) joint_wald
  )
}

aux_p <- c(TAU = tau$p_value, DELAY90 = delay$p_value)
aux_holm <- p.adjust(aux_p, method = "holm")
aux_order <- order(aux_p, names(aux_p), na.last = TRUE)
aux_rank <- rep(NA_integer_, 2L)
aux_rank[aux_order] <- seq_along(aux_order)
names(aux_rank) <- names(aux_p)
aux_level <- 1 - 0.05 / (2 - aux_rank + 1)
tau_holm_ci <- extract_ci(primary_fit$fit, "above_post", aux_level["TAU"])
delay_holm_ci <- extract_ci(delay_fit$fit, "above_post",
                            aux_level["DELAY90"])

tau_equiv <- tau$identified && tau$ci90_low_pp >= -margin_pp &&
  tau$ci90_high_pp <= margin_pp
delay_equiv <- delay$identified && delay$ci90_low_pp >= -margin_pp &&
  delay$ci90_high_pp <= margin_pp
supported_positive <- tau$identified && tau$ci95_low_pp > 0 &&
  tau$estimate_pp >= margin_pp
contrary_effect <- tau$identified && tau$ci95_high_pp < 0
delayed_signal <- delay$identified && delay$estimate_pp > 0 &&
  aux_holm["DELAY90"] < 0.05 && delay_holm_ci[1] > 0 &&
  !supported_positive
informative_profile <- tau_equiv && delay_equiv
informative_no_jump <- tau_equiv
g3_classification <- if (!tau$identified || !delay$identified) {
  "INCONCLUSIVE"
} else if (supported_positive) {
  "SUPPORTED_POSITIVE_EFFECT"
} else if (contrary_effect) {
  "CONTRARY_EFFECT"
} else if (delayed_signal) {
  "DELAYED_RESPONSE_SIGNAL"
} else if (informative_profile) {
  "INFORMATIVE_NO_LOCAL_PROFILE"
} else if (informative_no_jump) {
  "INFORMATIVE_NO_JUMP"
} else {
  "INCONCLUSIVE"
}

pre_below_share <- primary_h90[era == "pre" & side == "below",
  weighted.mean(married_pp, triangular_weight)]
relative_tau <- if (is.finite(pre_below_share) && pre_below_share != 0) {
  100 * tau$estimate_pp / pre_below_share
} else NA_real_

primary_table <- rbindlist(list(
  copy(tau)[, `:=`(
    estimand = "TAU",
    estimand_role = "primary_immediate_jump_change",
    p_value_holm_auxiliary_family = aux_holm["TAU"],
    holm_rank = aux_rank["TAU"],
    holm_confidence_level = aux_level["TAU"],
    holm_ci_low_pp = tau_holm_ci[1],
    holm_ci_high_pp = tau_holm_ci[2],
    equivalent_at_90pct = tau_equiv,
    pre_below_weighted_share_percent = pre_below_share,
    estimate_relative_to_pre_below_percent = relative_tau,
    mde80_pp = 2.8 * std_error_pp
  )],
  copy(delay)[, `:=`(
    estimand = "DELAY90",
    estimand_role = "secondary_delay_sensitive_profile",
    p_value_holm_auxiliary_family = aux_holm["DELAY90"],
    holm_rank = aux_rank["DELAY90"],
    holm_confidence_level = aux_level["DELAY90"],
    holm_ci_low_pp = delay_holm_ci[1],
    holm_ci_high_pp = delay_holm_ci[2],
    equivalent_at_90pct = delay_equiv,
    pre_below_weighted_share_percent = pre_below_share,
    estimate_relative_to_pre_below_percent = NA_real_,
    mde80_pp = NA_real_
  )]
), use.names = TRUE, fill = TRUE)
primary_table[, `:=`(
  policy_relevant_margin_pp = margin_pp,
  slope_kink_phi_pp_per_day = phi_estimate,
  slope_kink_phi_std_error = phi_se,
  slope_kink_phi_p_value = phi_p,
  joint_wald_statistic = as.numeric(joint_wald$stat),
  joint_wald_p_value = as.numeric(joint_wald$p),
  joint_wald_df1 = as.numeric(joint_wald$df1),
  joint_wald_df2 = as.numeric(joint_wald$df2),
  supported_positive_condition = supported_positive,
  contrary_effect_condition = contrary_effect,
  delayed_response_condition = delayed_signal,
  informative_no_local_profile_condition = informative_profile,
  informative_no_jump_condition = informative_no_jump,
  g3_classification = g3_classification
)]
setcolorder(primary_table, c(
  "estimand", "estimand_role", "model_id", "outcome_id", "sample_id",
  "bandwidth_days", "polynomial_order", "vcov_id", "fixed_effects",
  "donut_days", "identified", "n", "n_outcome_events",
  "n_municipality_clusters", "n_date_clusters", "n_distance_clusters",
  "estimate_pp", "std_error_pp", "ci90_low_pp", "ci90_high_pp",
  "ci95_low_pp", "ci95_high_pp", "p_value",
  "p_value_holm_auxiliary_family", "holm_rank", "holm_confidence_level",
  "holm_ci_low_pp", "holm_ci_high_pp", "equivalent_at_90pct",
  "policy_relevant_margin_pp", "pre_below_weighted_share_percent",
  "estimate_relative_to_pre_below_percent", "mde80_pp",
  "slope_kink_phi_pp_per_day", "slope_kink_phi_std_error",
  "slope_kink_phi_p_value", "joint_wald_statistic", "joint_wald_p_value",
  "joint_wald_df1", "joint_wald_df2", "supported_positive_condition",
  "contrary_effect_condition", "delayed_response_condition",
  "informative_no_local_profile_condition", "informative_no_jump_condition",
  "g3_classification", "error_message", "warnings"
))

# Secondary outcome family, with Holm adjustment across exactly two outcomes.
secondary_specs <- list(
  list(id = "UNIAO_ESTAVEL", col = "uniao_estavel_pp",
       model = "G3_SECONDARY_UNIAO_ESTAVEL", sign = "negative_or_null"),
  list(id = "ANY_UNION", col = "any_union_pp",
       model = "G3_SECONDARY_ANY_UNION", sign = "null")
)
secondary_rows <- list()
for (s in secondary_specs) {
  fit <- fit_stacked(s$model, primary_h90, s$col, s$id, "primary",
                     90L, 1L, "two_way", FALSE, 0L, FALSE)
  secondary_rows[[length(secondary_rows) + 1L]] <-
    copy(fit$result)[, expected_sign := s$sign]
}
secondary_table <- rbindlist(secondary_rows, use.names = TRUE)
secondary_table[, p_value_holm := p.adjust(p_value, method = "holm")]
secondary_table[, `:=`(
  rejects_raw_at_5pct = identified & p_value < 0.05,
  rejects_holm_at_5pct = identified & p_value_holm < 0.05,
  multiplicity_family = "two_secondary_outcomes"
)]

# Complete frozen stacked-model sensitivity set.
sensitivity_rows <- list()
add_sensitivity <- function(specification_id, label, fit_result,
                            is_primary = FALSE) {
  z <- copy(fit_result)
  z[, `:=`(
    specification_id = specification_id,
    specification_label = label,
    is_primary = is_primary
  )]
  sensitivity_rows[[length(sensitivity_rows) + 1L]] <<- z
}
add_sensitivity("primary_h90", "Primary: h=90, two-way cluster", tau, TRUE)

for (h in c(30L, 60L, 180L)) {
  z <- model_sample("primary", h)
  f <- fit_stacked(sprintf("G3_SENS_BW_%03d", h), z, "married_pp",
                   "MARRIED", "primary", h, 1L, "two_way")
  add_sensitivity(sprintf("bandwidth_h%d", h),
                  sprintf("Bandwidth h=%d", h), f$result)
}

for (v in c("distance", "hc1")) {
  f <- fit_stacked(paste0("G3_SENS_VCOV_", toupper(v)), primary_h90,
                   "married_pp", "MARRIED", "primary", 90L, 1L, v)
  label <- ifelse(v == "distance", "Cluster by exact age-day",
                  "Heteroskedasticity-robust HC1")
  add_sensitivity(paste0("vcov_", v), label, f$result)
}

f_cov <- fit_stacked(
  "G3_SENS_REGION_RACE_FE", primary_h90, "married_pp", "MARRIED",
  "primary", 90L, 1L, "two_way", TRUE
)
add_sensitivity("precision_region_race_fe",
                "Precision: region and race/color FE", f_cov$result)

z180 <- model_sample("primary", 180L)
f_quad <- fit_stacked(
  "G3_SENS_QUADRATIC_H180", z180, "married_pp", "MARRIED", "primary",
  180L, 2L, "two_way"
)
add_sensitivity("quadratic_h180", "Local quadratic: h=180", f_quad$result)

g1_binomial <- fread(g1_binomial_path)
heaping_detected <- any(g1_binomial$p_value < 0.05, na.rm = TRUE)
if (heaping_detected) {
  for (d in donuts) {
    z <- model_sample("primary", 90L, d)
    f <- fit_stacked(sprintf("G3_SENS_DONUT_%02d", d), z, "married_pp",
                     "MARRIED", "primary", 90L, 1L, "two_way", FALSE, d)
    add_sensitivity(sprintf("donut_d%d", d),
                    sprintf("Donut: exclude |x| <= %d", d), f$result)
  }
}

z_multiple <- model_sample("include_multiple", 90L)
f_multiple <- fit_stacked(
  "G3_SENS_INCLUDE_MULTIPLE", z_multiple, "married_pp", "MARRIED",
  "include_multiple", 90L, 1L, "two_way"
)
add_sensitivity("sample_include_multiple", "Include multiple gestations",
                f_multiple$result)

z_unknown <- model_sample("unknown_status_not_married", 90L)
f_unknown <- fit_stacked(
  "G3_SENS_UNKNOWN_AS_NOT_MARRIED", z_unknown, "married_pp", "MARRIED",
  "unknown_status_not_married", 90L, 1L, "two_way"
)
add_sensitivity("sample_unknown_not_married",
                "Unknown status coded not married", f_unknown$result)

sensitivity_table <- rbindlist(sensitivity_rows, use.names = TRUE, fill = TRUE)
sensitivity_table[, `:=`(
  heaping_detected_in_g1 = heaping_detected,
  diagnostic_cannot_rescue_gate = specification_id %chin%
    paste0("donut_d", donuts)
)]

# rdrobust cross-checks for every frozen bandwidth plus full-support diagnostic.
rd_rows <- list()
for (h in bands) {
  for (e in c("pre", "post")) {
    rd_rows[[length(rd_rows) + 1L]] <- fit_rdrobust_era(
      sprintf("G3_RDROBUST_H%03d_%s", h, toupper(e)),
      sprintf("fixed_h%d_b%d", h, 2L * h), primary_full, e,
      h = h, b = 2L * h, auto_bandwidth = FALSE
    )
  }
}
for (e in c("pre", "post")) {
  rd_rows[[length(rd_rows) + 1L]] <- fit_rdrobust_era(
    sprintf("G3_RDROBUST_AUTO_%s", toupper(e)), "full_support_mserd",
    primary_full, e, auto_bandwidth = TRUE
  )
}
rd_era <- rbindlist(rd_rows, use.names = TRUE, fill = TRUE)

rd_diff_rows <- list()
for (spec in unique(rd_era$specification_id)) {
  z <- rd_era[specification_id == spec]
  pre_z <- z[era == "pre"]
  post_z <- z[era == "post"]
  rd_diff_rows[[length(rd_diff_rows) + 1L]] <- data.table(
    model_id = paste0("G3_RDROBUST_DIFF_", toupper(gsub("[^A-Za-z0-9]", "_", spec))),
    specification_id = spec,
    row_type = "post_minus_pre_point_only",
    era = "post_minus_pre",
    estimator = "rdrobust::rdrobust",
    outcome_id = "MARRIED",
    sample_id = pre_z$sample_id,
    auto_bandwidth = pre_z$auto_bandwidth,
    bandwidth_selector = pre_z$bandwidth_selector,
    requested_h_days = pre_z$requested_h_days,
    requested_b_days = pre_z$requested_b_days,
    selected_h_left_days = NA_real_,
    selected_h_right_days = NA_real_,
    selected_b_left_days = NA_real_,
    selected_b_right_days = NA_real_,
    p = 1L, q = 2L, kernel = "triangular", vce = "nn", nnmatch = 3L,
    masspoints = "adjust",
    identified = nrow(z) == 2L && all(z$identified),
    n_full_left = sum(z$n_full_left),
    n_full_right = sum(z$n_full_right),
    n_h_left = sum(z$n_h_left),
    n_h_right = sum(z$n_h_right),
    n_outcome_events_h = sum(z$n_outcome_events_h),
    conventional_jump_pp = NA_real_,
    bias_corrected_jump_pp = NA_real_,
    robust_std_error_pp = NA_real_,
    robust_ci95_low_pp = NA_real_,
    robust_ci95_high_pp = NA_real_,
    robust_p_value = NA_real_,
    post_minus_pre_bias_corrected_pp =
      post_z$bias_corrected_jump_pp - pre_z$bias_corrected_jump_pp,
    difference_inference_available = FALSE,
    error_message = NA_character_,
    warnings = paste(unique(z$warnings[nzchar(z$warnings)]), collapse = " | ")
  )
}
rdrobust_table <- rbindlist(c(list(rd_era), rd_diff_rows),
                            use.names = TRUE, fill = TRUE)
rdrobust_table[, era_order := match(
  era, c("pre", "post", "post_minus_pre")
)]
setorder(rdrobust_table, specification_id, era_order)
rdrobust_table[, era_order := NULL]

model_registry <- rbindlist(registry_rows, use.names = TRUE, fill = TRUE)
if (anyDuplicated(model_registry$model_id)) stop("Duplicate G3 model IDs")

# Required RD visualization: privacy-safe weekly bins plus descriptive local fits.
plot_data <- copy(primary_h90)
plot_data[, weekly_bin := fifelse(
  x_days < 0L, -ceiling(abs(x_days) / 7), floor(x_days / 7)
)]
plot_bins <- plot_data[, .(
  bin_start = min(x_days),
  bin_end = max(x_days),
  bin_midpoint = mean(range(x_days)),
  n_births = .N,
  n_married_events_internal = sum(married),
  married_share_percent_internal = mean(married_pp)
), by = .(era, weekly_bin)]
plot_bins[, privacy_suppressed := n_married_events_internal >= 1 &
            n_married_events_internal <= 9]
plot_bins[, married_share_percent := fifelse(
  privacy_suppressed, NA_real_, married_share_percent_internal
)]

fit_lines <- list()
for (e in c("pre", "post")) {
  for (s in c("below", "above")) {
    d <- plot_data[era == e & side == s]
    local_fit <- lm(married_pp ~ x_days, data = d,
                    weights = triangular_weight)
    grid_x <- if (s == "below") seq(-89, -1, by = 1) else seq(0, 89, by = 1)
    fit_lines[[length(fit_lines) + 1L]] <- data.table(
      era = e, side = s, x_days = grid_x,
      fitted_share_percent = as.numeric(predict(
        local_fit, newdata = data.frame(x_days = grid_x)
      ))
    )
  }
}
fit_lines <- rbindlist(fit_lines)
era_labels <- c(pre = "Pre-law: 2016-2018",
                post = "Mature post-law: 2022-2024")
plot_bins[, era_label := factor(era_labels[era], levels = era_labels)]
fit_lines[, era_label := factor(era_labels[era], levels = era_labels)]

p_rd <- ggplot(plot_bins,
               aes(x = bin_midpoint, y = married_share_percent)) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.4,
             colour = "grey35") +
  geom_point(aes(shape = privacy_suppressed), size = 1.7,
             colour = "#1B5E8C", na.rm = TRUE) +
  geom_line(data = fit_lines,
            aes(x = x_days, y = fitted_share_percent, group = side),
            inherit.aes = FALSE, linewidth = 0.75, colour = "#C44E52") +
  facet_wrap(~era_label, ncol = 1) +
  scale_x_continuous(breaks = seq(-90, 90, by = 30)) +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 1), guide = "none") +
  labs(
    title = "Recorded married status around the mother's 16th birthday",
    subtitle = paste0(
      "Seven-day bins and descriptive triangular local fits; ",
      "bins with 1-9 married records suppressed"
    ),
    x = "Calendar days from the 16th birthday",
    y = "Recorded married share (%)"
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank())

rd_figure_pdf <- file.path(figure_dir, "FIGURE_14_SINASC_DAILY_RD.pdf")
rd_figure_png <- file.path(figure_dir, "FIGURE_14_SINASC_DAILY_RD.png")
ggsave(rd_figure_pdf, p_rd, width = 8.2, height = 6.2, units = "in",
       device = cairo_pdf)
ggsave(rd_figure_png, p_rd, width = 8.2, height = 6.2, units = "in",
       dpi = 180)

sens_plot <- copy(sensitivity_table)
sens_plot[, specification_label := factor(
  specification_label, levels = rev(specification_label)
)]
p_sens <- ggplot(sens_plot,
                 aes(x = estimate_pp, y = specification_label,
                     colour = is_primary)) +
  geom_vline(xintercept = 0, colour = "grey35", linewidth = 0.35) +
  geom_vline(xintercept = c(-margin_pp, margin_pp), colour = "grey65",
             linetype = "dashed", linewidth = 0.35) +
  geom_errorbar(aes(xmin = ci95_low_pp, xmax = ci95_high_pp),
                width = 0.18, linewidth = 0.5) +
  geom_point(size = 2) +
  scale_colour_manual(values = c(`FALSE` = "#6B7280", `TRUE` = "#C44E52"),
                      labels = c(`FALSE` = "Sensitivity", `TRUE` = "Primary")) +
  labs(
    title = "Frozen sensitivity set for the age-16 jump change",
    subtitle = "Point estimates and 95% confidence intervals; dashed lines mark +/-0.25 pp",
    x = "Post-minus-pre change in the age-16 jump (percentage points)",
    y = NULL, colour = NULL
  ) +
  theme_minimal(base_size = 9.5) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")

sens_figure_pdf <- file.path(figure_dir,
                             "FIGURE_SINASC_DAILY_G3_SENSITIVITY.pdf")
sens_figure_png <- file.path(figure_dir,
                             "FIGURE_SINASC_DAILY_G3_SENSITIVITY.png")
ggsave(sens_figure_pdf, p_sens, width = 9.2, height = 7.4, units = "in",
       device = cairo_pdf)
ggsave(sens_figure_png, p_sens, width = 9.2, height = 7.4, units = "in",
       dpi = 180)

# Software ledger includes the exact archived package source used for G3.
rdrobust_source_sha256 <-
  "b1bcd0d6dae4ea0ceadf5fb3c2d62d787fb316c0a19c671c05b5db300d4b27a3"
software <- data.table(
  component = c("R", "data.table", "digest", "fixest", "ggplot2",
                "rdrobust", "yaml"),
  version = c(R.version.string,
              vapply(c("data.table", "digest", "fixest", "ggplot2",
                       "rdrobust", "yaml"), function(p) {
                         as.character(packageVersion(p))
                       }, character(1))),
  frozen_expected_version = c(NA_character_, NA_character_, NA_character_,
                              NA_character_, NA_character_, "3.0.0",
                              NA_character_),
  source = c("R runtime", rep("installed R package", 4L),
             "CRAN archive source tarball", "installed R package"),
  source_url = c(rep(NA_character_, 5L),
                 "https://cran.r-project.org/src/contrib/Archive/rdrobust/rdrobust_3.0.0.tar.gz",
                 NA_character_),
  source_sha256 = c(rep(NA_character_, 5L), rdrobust_source_sha256,
                    NA_character_),
  frozen_version_match = c(rep(NA, 5L),
                           as.character(packageVersion("rdrobust")) == "3.0.0",
                           NA)
)

all_sensitivity_identified <- nrow(sensitivity_table) == 13L &&
  all(sensitivity_table$identified)
all_rdrobust_identified <- rd_era[, .N] == 10L && all(rd_era$identified)
causal_core_eligible <- identical(g0_status, "PASS") &&
  identical(g1_status, "PASS") && identical(g2_status, "PASS") &&
  g3_classification %chin% c("SUPPORTED_POSITIVE_EFFECT",
                             "INFORMATIVE_NO_LOCAL_PROFILE")
paper_path_decision <- if (causal_core_eligible) {
  "ELIGIBLE_TO_ADVANCE_AS_CAUSAL_CORE"
} else {
  "DO_NOT_ADVANCE_AS_CAUSAL_CORE"
}

g3_gate <- rbindlist(list(
  data.table(
    criterion = "G0_G1_preconditions",
    threshold = "unchanged G0=PASS and G1=PASS",
    observed = paste(g0_status, g1_status, sep = ","),
    status = ifelse(g0_status == "PASS" && g1_status == "PASS", "PASS", "FAIL")
  ),
  data.table(
    criterion = "G2_counterfactual",
    threshold = "G2 must PASS for unconditional causal-core eligibility",
    observed = g2_status,
    status = g2_status
  ),
  data.table(
    criterion = "G3_primary_identification",
    threshold = "TAU and DELAY90 identified under frozen h=90 models",
    observed = sprintf("tau=%s;delay90=%s", tau$identified, delay$identified),
    status = ifelse(tau$identified && delay$identified, "PASS", "QUALIFIED")
  ),
  data.table(
    criterion = "G3_frozen_sensitivity_set",
    threshold = "all 13 stacked rows displayed and identified",
    observed = sprintf("%d/13 identified", sum(sensitivity_table$identified)),
    status = ifelse(all_sensitivity_identified, "COMPLETE", "QUALIFIED")
  ),
  data.table(
    criterion = "G3_rdrobust_crosschecks",
    threshold = "10 separate-era fits plus five point-only differences",
    observed = sprintf("%d/10 era fits identified", sum(rd_era$identified)),
    status = ifelse(all_rdrobust_identified, "COMPLETE", "QUALIFIED")
  ),
  data.table(
    criterion = "G3_OVERALL",
    threshold = paste("mechanical A004 precedence across six frozen labels;",
                      "non-identification is inconclusive"),
    observed = g3_classification,
    status = g3_classification
  ),
  data.table(
    criterion = "CAUSAL_CORE_DECISION",
    threshold = paste("G0=PASS, G1=PASS, G2=PASS, and G3 supported positive",
                      "or informative no local profile"),
    observed = paste0("G2=", g2_status, ";G3=", g3_classification),
    status = paper_path_decision
  )
), use.names = TRUE)

# Privacy guard before public outputs.
count_tables <- list(
  sample_reconciliation[, .(count = g3_n_married_events)],
  sample_audit[, .(count = n_married_events)],
  primary_table[, .(count = n_outcome_events)],
  secondary_table[, .(count = n_outcome_events)],
  sensitivity_table[, .(count = n_outcome_events)],
  rdrobust_table[, .(count = n_outcome_events_h)]
)
if (any(unlist(lapply(count_tables, function(z) {
  z$count %between% c(1, 9)
})), na.rm = TRUE)) {
  stop("Small outcome-event count reached a public G3 table")
}
if (any(!is.na(plot_bins$married_share_percent[plot_bins$privacy_suppressed]))) {
  stop("A small weekly outcome cell reached the G3 RD figure")
}

paths <- list(
  schema = file.path(audit_dir, "SINASC_DAILY_G3_SCHEMA_AUDIT.csv"),
  reconciliation = file.path(audit_dir,
                             "SINASC_DAILY_G3_SAMPLE_RECONCILIATION.csv"),
  sample_audit = file.path(audit_dir, "SINASC_DAILY_G3_SAMPLE_AUDIT.csv"),
  software = file.path(audit_dir, "SINASC_DAILY_G3_SOFTWARE.csv"),
  model_registry = file.path(audit_dir,
                             "SINASC_DAILY_G3_MODEL_REGISTRY.csv"),
  gate = file.path(audit_dir, "SINASC_DAILY_G3_GATE_STATUS.csv"),
  primary = file.path(table_dir, "SINASC_DAILY_PRIMARY.csv"),
  secondary = file.path(table_dir, "SINASC_DAILY_SECONDARY.csv"),
  sensitivity = file.path(table_dir, "SINASC_DAILY_SENSITIVITY.csv"),
  rdrobust = file.path(table_dir, "SINASC_DAILY_RDROBUST.csv"),
  report = file.path(analysis_dir, "SINASC_DAILY_RESULTS.md"),
  rd_figure_pdf = rd_figure_pdf,
  rd_figure_png = rd_figure_png,
  sensitivity_figure_pdf = sens_figure_pdf,
  sensitivity_figure_png = sens_figure_png
)

fwrite(schema_audit, paths$schema, na = "")
fwrite(sample_reconciliation, paths$reconciliation, na = "")
fwrite(sample_audit, paths$sample_audit, na = "")
fwrite(software, paths$software, na = "")
fwrite(model_registry, paths$model_registry, na = "")
fwrite(g3_gate, paths$gate, na = "")
fwrite(primary_table, paths$primary, na = "")
fwrite(secondary_table, paths$secondary, na = "")
fwrite(sensitivity_table, paths$sensitivity, na = "")
fwrite(rdrobust_table, paths$rdrobust, na = "")

tau_row <- primary_table[estimand == "TAU"]
delay_row <- primary_table[estimand == "DELAY90"]
rd_h90 <- rdrobust_table[specification_id == "fixed_h90_b180"]
secondary_lines <- vapply(seq_len(nrow(secondary_table)), function(i) {
  z <- secondary_table[i]
  sprintf("| %s | %s | [%s, %s] | %s | %s |",
          z$outcome_id, fmt_num(z$estimate_pp), fmt_num(z$ci95_low_pp),
          fmt_num(z$ci95_high_pp), fmt_p(z$p_value),
          fmt_p(z$p_value_holm))
}, character(1))
rd_lines <- vapply(seq_len(nrow(rd_h90)), function(i) {
  z <- rd_h90[i]
  if (z$row_type == "era_jump") {
    sprintf("| %s | %s | [%s, %s] | %s |",
            z$era, fmt_num(z$bias_corrected_jump_pp),
            fmt_num(z$robust_ci95_low_pp), fmt_num(z$robust_ci95_high_pp),
            fmt_p(z$robust_p_value))
  } else {
    sprintf("| post minus pre | %s | no separate-fit inference | NA |",
            fmt_num(z$post_minus_pre_bias_corrected_pp))
  }
}, character(1))

classification_sentence <- switch(
  g3_classification,
  SUPPORTED_POSITIVE_EFFECT = paste0(
    "The frozen G3 rule detects a positive immediate jump of policy-relevant size."
  ),
  CONTRARY_EFFECT = paste0(
    "The frozen G3 rule classifies the immediate jump as contrary to the predicted sign."
  ),
  DELAYED_RESPONSE_SIGNAL = paste0(
    "The immediate jump is not supported, but the Holm-adjusted delay profile is positive."
  ),
  INFORMATIVE_NO_LOCAL_PROFILE = paste0(
    "Both frozen 90% intervals fit inside the +/-0.25 pp margin, supporting a narrow local profile null."
  ),
  INFORMATIVE_NO_JUMP = paste0(
    "The immediate jump is precisely small, but the delay profile is not equivalently bounded."
  ),
  "The frozen data do not distinguish zero from policy-relevant local changes."
)

sens_identified <- sensitivity_table[identified == TRUE]
report_lines <- c(
  "# SINASC daily age-16 design — Gate G3 results",
  "",
  sprintf("**G3 classification: `%s`.**", g3_classification),
  sprintf("**Paper-path decision: `%s`.**", paper_path_decision),
  "",
  sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  classification_sentence,
  sprintf(paste0(
    "The primary post-minus-pre change in the age-16 married-status jump is ",
    "%s percentage points (SE %s; 95%% CI [%s, %s]; p=%s)."
  ), fmt_num(tau_row$estimate_pp), fmt_num(tau_row$std_error_pp),
  fmt_num(tau_row$ci95_low_pp), fmt_num(tau_row$ci95_high_pp),
  fmt_p(tau_row$p_value)),
  sprintf(paste0(
    "Its MDE80 is %s pp. The estimate equals %s%% of the triangular-weighted ",
    "pre-law below-cutoff married share (%s%%)."
  ), fmt_num(tau_row$mde80_pp),
  fmt_num(tau_row$estimate_relative_to_pre_below_percent, 2L),
  fmt_num(tau_row$pre_below_weighted_share_percent)),
  "",
  paste0(
    "G2 remains `", g2_status, "`. Therefore this post-result daily design ",
    ifelse(causal_core_eligible,
           "meets the frozen conditions for causal-core eligibility.",
           "does not meet the frozen conditions for an unconditional causal core.")
  ),
  "The estimates remain local to mothers of singleton live births near age 16 and measure recorded conjugal status at childbirth, not marriage incidence.",
  "",
  "## Primary and delay-sensitive estimands",
  "",
  "| Estimand | Estimate pp | SE | 90% CI | 95% CI | Raw p | Holm p | Holm interval |",
  "|---|---:|---:|---:|---:|---:|---:|---:|",
  sprintf("| TAU | %s | %s | [%s, %s] | [%s, %s] | %s | %s | [%s, %s] |",
          fmt_num(tau_row$estimate_pp), fmt_num(tau_row$std_error_pp),
          fmt_num(tau_row$ci90_low_pp), fmt_num(tau_row$ci90_high_pp),
          fmt_num(tau_row$ci95_low_pp), fmt_num(tau_row$ci95_high_pp),
          fmt_p(tau_row$p_value),
          fmt_p(tau_row$p_value_holm_auxiliary_family),
          fmt_num(tau_row$holm_ci_low_pp), fmt_num(tau_row$holm_ci_high_pp)),
  sprintf("| DELAY90 | %s | %s | [%s, %s] | [%s, %s] | %s | %s | [%s, %s] |",
          fmt_num(delay_row$estimate_pp), fmt_num(delay_row$std_error_pp),
          fmt_num(delay_row$ci90_low_pp), fmt_num(delay_row$ci90_high_pp),
          fmt_num(delay_row$ci95_low_pp), fmt_num(delay_row$ci95_high_pp),
          fmt_p(delay_row$p_value),
          fmt_p(delay_row$p_value_holm_auxiliary_family),
          fmt_num(delay_row$holm_ci_low_pp),
          fmt_num(delay_row$holm_ci_high_pp)),
  "",
  sprintf(paste0(
    "The slope-kink change phi is %s pp per day. The joint Wald test of ",
    "TAU=phi=0 gives F(%s,%s)=%s (p=%s)."
  ), fmt_num(phi_estimate, 7L), fmt_num(joint_wald$df1, 0L),
  fmt_num(joint_wald$df2, 0L), fmt_num(joint_wald$stat),
  fmt_p(joint_wald$p)),
  "DELAY90 equals TAU + 45*phi. Holm adjustment applies only to the auxiliary immediate-or-delayed family; the single primary TAU keeps its unadjusted inference.",
  "",
  "## Secondary outcomes",
  "",
  "| Outcome | Estimate pp | 95% CI | Raw p | Holm p |",
  "|---|---:|---:|---:|---:|",
  secondary_lines,
  "",
  "Holm adjustment covers exactly UNIAO_ESTAVEL and ANY_UNION. These recorded labels do not establish behavioral substitution and do not alter the G3 class.",
  "",
  "## Frozen sensitivity set",
  "",
  sprintf(paste0(
    "All %d stacked specifications identify. Their estimates range from %s to ",
    "%s pp; the complete table and coefficient plot retain bandwidth, covariance, ",
    "precision, functional-form, donut, and sample checks."
  ), nrow(sens_identified), fmt_num(min(sens_identified$estimate_pp)),
  fmt_num(max(sens_identified$estimate_pp))),
  sprintf("G1 heaping trigger: `%s`; donut estimates are displayed and cannot rescue a gate.",
          heaping_detected),
  "",
  "## rdrobust 3.0.0 cross-check at h=90, b=180",
  "",
  "| Era/comparison | Bias-corrected jump pp | Robust 95% CI | Robust p |",
  "|---|---:|---:|---:|",
  rd_lines,
  "",
  "The pre and post fits use disjoint era samples. Their subtraction is a point comparison only; the stacked model supplies inference for TAU because separate rdrobust fits do not retain cross-era municipal covariance.",
  "",
  "## Audit and interpretation",
  "",
  sprintf("The script streamed six annual ZIPs and retained %s primary h=90 observations.",
          fmt_int(nrow(primary_h90))),
  "All 48 year-by-bandwidth-by-side primary cells reproduce G0. No person-level derivative or municipality-by-day cell is written. Weekly figure bins with 1-9 married events are suppressed.",
  "The protocol was frozen after earlier paper results but before any daily age-distance outcome contrast. A004 fixed implementation details before this first G3 run.",
  "",
  "## Artifacts",
  "",
  paste0("- `", sub(paste0("^", root, "/"), "", unlist(paths)), "`")
)
writeLines(report_lines, paths$report)

manifest_rel <- sub(paste0("^", root, "/"), "", unlist(paths))
manifest <- data.table(
  artifact = manifest_rel,
  sha256 = vapply(unlist(paths), digest, character(1),
                  algo = "sha256", file = TRUE),
  scope = "G3_full_frozen_analysis_post_result_protocol"
)
manifest_path <- file.path(audit_dir, "SINASC_DAILY_G3_OUTPUT_MANIFEST.csv")
fwrite(manifest, manifest_path, na = "")

elapsed <- as.numeric(difftime(Sys.time(), started, units = "mins"))
log_line("complete | G3=", g3_classification, " | G2=", g2_status,
         " | paper_path=", paper_path_decision,
         " | models=", nrow(model_registry),
         " | elapsed=", sprintf("%.2fmin", elapsed),
         " | peak_current_RSS=", sprintf("%.0fMB", rss_mb()))
cat(sprintf(
  "sinasc_daily_g3_complete classification=%s paper_path=%s elapsed=%.2fmin\n",
  g3_classification, paper_path_decision, elapsed
))
