#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(arrow)
  library(yaml)
})

started <- Sys.time()
set.seed(13811)
setFixest_nthreads(1)
setFixest_notes(FALSE)
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
audit_dir <- file.path(root, "outputs", "audit")
log_dir <- file.path(root, "outputs", "logs")

region <- fread(file.path(data_dir, "REGISTRY_QUARTERLY_PANEL_REGION.csv"))
brazil <- fread(file.path(data_dir, "REGISTRY_QUARTERLY_PANEL_BRAZIL.csv"))
annual <- fread(file.path(data_dir, "REGISTRY_ANNUAL_PANEL_UF.csv"))
exposure <- fread(file.path(data_dir, "PRELAW_EXPOSURE_UF.csv"))
secondary <- fread(file.path(data_dir, "REGISTRY_ANNUAL_SECONDARY_OUTCOMES.csv"))

fit_age_model <- function(focal_age, controls) {
  ages <- sort(unique(c(focal_age, controls)))
  d <- copy(region[
    sex == "combined" & age %in% ages &
      (year <= 2018L | (year == 2019L & quarter >= 2L))
  ])
  d[, treat_post := as.integer(age == focal_age) * post_full]
  trend_names <- character()
  for (a in setdiff(ages, max(controls))) {
    nm <- paste0("trend_age_", a)
    d[, (nm) := trend_2018q4 * as.integer(age == a)]
    trend_names <- c(trend_names, nm)
  }
  f <- as.formula(paste(
    "persons_married ~ treat_post +", paste(trend_names, collapse = " + "),
    "| geography_value^age + geography_value^period + age^quarter"
  ))
  model <- fepois(f, offset = ~offset_log_population, data = d, warn = FALSE)
  ct <- coeftable(model, vcov = ~period)
  beta <- unname(ct["treat_post", "Estimate"])
  se <- unname(ct["treat_post", "Std. Error"])
  d[, fitted := as.numeric(predict(model, type = "response"))]
  focal_post <- d[age == focal_age & post_full == 1L]
  fitted_with <- sum(focal_post$fitted)
  fitted_without <- fitted_with / exp(beta)
  list(
    focal_age = focal_age, controls = controls, data = d, model = model,
    beta = beta, se = se, fitted_with = fitted_with,
    fitted_without = fitted_without,
    event_effect = fitted_with - fitted_without
  )
}

age_controls <- list(`15` = 17:19, `16` = 18:19, `17` = 18:19)
age_fits <- lapply(names(age_controls), function(a) fit_age_model(as.integer(a), age_controls[[a]]))
names(age_fits) <- names(age_controls)

# Aligned Brazil time-series residuals provide joint temporal block uncertainty.
make_gap <- function(focal_age, controls) {
  source <- brazil[
    sex == "combined" & age %in% c(focal_age, controls) &
      !(year == 2019L & quarter == 1L)
  ]
  focal <- source[age == focal_age, .(
    year, quarter, period, trend_2018q4,
    focal_rate = formal_marriage_rate_100k
  )]
  control <- source[age %in% controls, .(
    control_count = sum(persons_married),
    control_population = sum(population)
  ), by = .(year, quarter, period)]
  x <- merge(focal, control, by = c("year", "quarter", "period"))
  x[, control_rate := 100000 * control_count / control_population]
  if (any(x$focal_rate <= 0 | x$control_rate <= 0)) stop("Zero rate in delay gap")
  x[, `:=`(
    gap = log(focal_rate) - log(control_rate),
    quarter_factor = factor(quarter, levels = 1:4)
  )]
  setorder(x, year, quarter)
  pre <- x[year <= 2018L]
  model <- lm(gap ~ trend_2018q4 + quarter_factor, data = pre)
  x[, predicted := as.numeric(predict(model, newdata = x))]
  residual <- residuals(model) - mean(residuals(model))
  list(data = x, residual = residual)
}
age_gaps <- lapply(names(age_controls), function(a) make_gap(as.integer(a), age_controls[[a]]))
names(age_gaps) <- names(age_controls)
if (!all(vapply(age_gaps, function(x) identical(x$data$period, age_gaps[[1L]]$data$period), logical(1L)))) {
  stop("Age-gap periods are not aligned")
}

sample_block_indices <- function(n_source, target_n, block_length = 4L) {
  starts <- sample.int(n_source, ceiling(target_n / block_length), replace = TRUE)
  out <- unlist(lapply(starts, function(s) ((s - 1L + 0:(block_length - 1L)) %% n_source) + 1L))
  out[seq_len(target_n)]
}

beta_draws <- matrix(NA_real_, nrow = 999L, ncol = 3L,
                     dimnames = list(NULL, names(age_controls)))
dynamic_errors_by_age <- lapply(age_gaps, function(g) {
  matrix(NA_real_, nrow = 999L, ncol = nrow(g$data))
})
for (b in seq_len(999L)) {
  idx <- sample_block_indices(24L, nrow(age_gaps[[1L]]$data), 4L)
  for (a in names(age_controls)) {
    g <- age_gaps[[a]]
    null_y <- g$data$predicted + g$residual[idx]
    boot_pre <- copy(g$data[year <= 2018L])
    boot_pre[, null_y := null_y[seq_len(.N)]]
    boot_model <- lm(null_y ~ trend_2018q4 + quarter_factor, data = boot_pre)
    boot_pred <- as.numeric(predict(boot_model, newdata = g$data))
    short_idx <- which(g$data$year == 2019L & g$data$quarter %in% 2:4)
    period_error <- null_y - boot_pred
    dynamic_errors_by_age[[a]][b, ] <- period_error
    forecast_error <- mean(period_error[short_idx])
    beta_draws[b, a] <- age_fits[[a]]$beta - forecast_error
  }
}

event_draws <- copy(as.data.table(beta_draws))
for (a in names(age_controls)) {
  fitted_with <- age_fits[[a]]$fitted_with
  event_draws[, (paste0("events_age", a)) := fitted_with * (1 - exp(-get(a)))]
}
event_draws[, deficit_age15 := -events_age15]
event_draws[, excess_age16_17 := events_age16 + events_age17]
event_draws[, recapture := fifelse(deficit_age15 > 1e-10,
                                   excess_age16_17 / deficit_age15, NA_real_)]

point_events <- sapply(names(age_controls), function(a) age_fits[[a]]$event_effect)
point_deficit <- -point_events["15"]
point_excess <- point_events["16"] + point_events["17"]
point_recapture <- if (point_deficit > 1e-10) point_excess / point_deficit else NA_real_
valid_recapture <- event_draws$recapture[is.finite(event_draws$recapture)]

delay_events <- rbindlist(lapply(names(age_controls), function(a) {
  draws <- event_draws[[paste0("events_age", a)]]
  fit <- age_fits[[a]]
  data.table(
    age = as.integer(a), controls = paste(age_controls[[a]], collapse = "-"),
    beta_log_rate_ratio = fit$beta, period_cluster_se = fit$se,
    rate_ratio = exp(fit$beta), percent_change = 100 * (exp(fit$beta) - 1),
    fitted_events_with_treatment = fit$fitted_with,
    fitted_events_without_treatment = fit$fitted_without,
    estimated_event_effect = fit$event_effect,
    event_effect_ci_lower = quantile(draws, 0.025),
    event_effect_ci_upper = quantile(draws, 0.975),
    temporal_block_replications = 999L
  )
}), use.names = TRUE)
fwrite(delay_events, file.path(table_dir, "REGISTRY_DELAY_EVENT_COUNTS.csv"))

recapture <- data.table(
  age15_estimated_deficit = point_deficit,
  age16_17_estimated_excess = point_excess,
  aggregate_recapture = point_recapture,
  recapture_ci_lower = if (length(valid_recapture)) quantile(valid_recapture, 0.025) else NA_real_,
  recapture_ci_upper = if (length(valid_recapture)) quantile(valid_recapture, 0.975) else NA_real_,
  valid_bootstrap_draws = length(valid_recapture),
  invalid_draws_nonpositive_deficit = 999L - length(valid_recapture),
  valid_draw_share = length(valid_recapture) / 999,
  point_ratio_defined = is.finite(point_recapture),
  label = "aggregate recapture; does not track the same people",
  window = "2019Q2-2019Q4",
  temporal_block_length = 4L,
  temporal_block_replications = 999L
)
fwrite(recapture, file.path(table_dir, "REGISTRY_AGGREGATE_RECAPTURE.csv"))
fwrite(cbind(data.table(draw = seq_len(999L)), event_draws),
       file.path(audit_dir, "REGISTRY_RECAPTURE_BOOTSTRAP_DRAWS.csv"))

delay_dynamic <- rbindlist(lapply(names(age_controls), function(a) {
  g <- age_gaps[[a]]
  errors <- dynamic_errors_by_age[[a]]
  effect <- g$data$gap - g$data$predicted
  se <- apply(errors, 2L, sd)
  valid <- se > 0 & is.finite(se)
  maximum <- apply(abs(sweep(errors[, valid, drop = FALSE], 2L, se[valid], "/")), 1L, max)
  critical <- quantile(maximum, 0.95)
  out <- copy(g$data)
  out[, `:=`(
    focal_age = as.integer(a),
    controls = paste(age_controls[[a]], collapse = "-"),
    event_time = fifelse(
      year < 2019L,
      (year - 2018L) * 4L + quarter - 5L,
      (year - 2019L) * 4L + quarter - 2L
    ),
    dynamic_log_effect = effect,
    bootstrap_se = se,
    simultaneous_ci_lower = effect - critical * se,
    simultaneous_ci_upper = effect + critical * se,
    simultaneous_critical_value = critical,
    bootstrap_replications = 999L,
    block_length = 4L
  )]
  out
}), use.names = TRUE, fill = TRUE)
fwrite(delay_dynamic, file.path(table_dir, "REGISTRY_DELAY_DYNAMIC_EVENT_STUDIES.csv"))

# Complementary exposure-gradient DDD, using annual UF cells and no 2019/2020-2021.
ddd <- annual[
  sex == "combined" & age %in% c(15L, 17:19) & year != 2019L
]
ddd <- merge(
  ddd,
  exposure[, .(uf_code, prelaw_affected_marriage_share_raw,
               prelaw_affected_marriage_share_eb, exposure_raw_z, exposure_eb_z)],
  by = "uf_code",
  all.x = TRUE
)
if (anyNA(ddd$exposure_eb_z)) stop("Exposure join failed")
ddd[, `:=`(
  treated = as.integer(age == 15L),
  post = as.integer(year >= 2020L)
)]

fit_ddd <- function(exposure_var) {
  d <- copy(ddd)
  d[, ddd_term := get(exposure_var) * treated * post]
  f <- persons_married ~ ddd_term |
    geography_value^age + geography_value^year + age^year
  model <- fepois(f, offset = ~offset_log_population, data = d, warn = FALSE)
  period_ct <- coeftable(model, vcov = ~year)
  tw_ct <- coeftable(model, vcov = ~geography_value + year)
  extract <- function(ct) {
    beta <- unname(ct["ddd_term", "Estimate"])
    se <- unname(ct["ddd_term", "Std. Error"])
    c(beta = beta, se = se, p = 2 * pnorm(-abs(beta / se)),
      lower = beta - qnorm(0.975) * se, upper = beta + qnorm(0.975) * se)
  }
  list(model = model, data = d, period = extract(period_ct), two_way = extract(tw_ct))
}
ddd_raw <- fit_ddd("exposure_raw_z")
ddd_eb <- fit_ddd("exposure_eb_z")
ddd_results <- rbindlist(lapply(list(raw = ddd_raw, empirical_bayes = ddd_eb), function(x) {
  data.table(
    exposure = if (identical(x, ddd_raw)) "raw affected-marriage share" else "empirical-Bayes affected-marriage share",
    estimate_per_preperiod_sd = x$period["beta"],
    std_error_cluster_year = x$period["se"],
    p_value_cluster_year = x$period["p"],
    ci_lower_cluster_year = x$period["lower"],
    ci_upper_cluster_year = x$period["upper"],
    rate_ratio_gradient = exp(x$period["beta"]),
    percent_gradient = 100 * (exp(x$period["beta"]) - 1),
    two_way_std_error = x$two_way["se"],
    two_way_p_value = x$two_way["p"],
    observations = nobs(x$model),
    ufs = uniqueN(x$data$uf_code),
    years = uniqueN(x$data$year),
    year_clusters = uniqueN(x$data$year),
    interpretation = "effect gradient per one pre-period SD; not national average effect"
  )
}), use.names = TRUE)
fwrite(ddd_results, file.path(table_dir, "REGISTRY_EXPOSURE_DDD.csv"))

# Annual exposure event coefficients and 2018 holdout/pretrend diagnostics.
ddd_event <- copy(ddd)
ddd_event[, exposure_treated := exposure_eb_z * treated]
event_formula <- persons_married ~ i(year, exposure_treated, ref = 2018) |
  geography_value^age + geography_value^year + age^year
event_model <- fepois(event_formula, offset = ~offset_log_population,
                      data = ddd_event, warn = FALSE)
event_ct <- as.data.table(coeftable(event_model, vcov = ~geography_value), keep.rownames = "term")
event_ct <- event_ct[grepl("^year::", term)]
setnames(event_ct, c("Estimate", "Std. Error", "z value", "Pr(>|z|)"),
         c("estimate", "std_error_uf_cluster", "statistic", "p_value_uf_cluster"))
event_ct[, year := as.integer(sub("year::([0-9]{4}):.*", "\\1", term))]
event_ct[, `:=`(
  ci_lower = estimate - qnorm(0.975) * std_error_uf_cluster,
  ci_upper = estimate + qnorm(0.975) * std_error_uf_cluster,
  inference_status = "diagnostic: annual national timing and 27 UF clusters"
)]
setorder(event_ct, year)
fwrite(event_ct, file.path(table_dir, "REGISTRY_EXPOSURE_DDD_EVENT_STUDY.csv"))

# Holdout and regression-to-the-mean diagnostics use only pre/post-boundary data.
exposure_diag <- copy(exposure)
pre_rates <- annual[
  sex == "combined" & age == 15L & year %in% 2013:2017,
  .(pre_rate_15 = weighted.mean(formal_marriage_rate_100k, population)), by = uf_code
]
holdout_rates <- annual[
  sex == "combined" & age == 15L & year == 2018L,
  .(holdout_rate_15 = formal_marriage_rate_100k), by = uf_code
]
exposure_diag <- Reduce(function(x, y) merge(x, y, by = "uf_code", all.x = TRUE),
                        list(exposure_diag, pre_rates, holdout_rates))
exposure_diag[, holdout_change := holdout_rate_15 - pre_rate_15]
exposure_diagnostics <- data.table(
  raw_eb_correlation = cor(exposure_diag$prelaw_affected_marriage_share_raw,
                           exposure_diag$prelaw_affected_marriage_share_eb),
  exposure_holdout_change_correlation = cor(exposure_diag$prelaw_affected_marriage_share_eb,
                                            exposure_diag$holdout_change),
  exposure_holdout_level_correlation = cor(exposure_diag$prelaw_affected_marriage_share_eb,
                                           exposure_diag$holdout_rate_15),
  ufs = nrow(exposure_diag),
  holdout_year = 2018L,
  training_years = "2013-2017"
)
fwrite(exposure_diag, file.path(table_dir, "REGISTRY_EXPOSURE_UF_WITH_HOLDOUT.csv"))
fwrite(exposure_diagnostics, file.path(table_dir, "REGISTRY_EXPOSURE_DIAGNOSTICS.csv"))

# National annual secondary outcomes, explicitly descriptive.
national_secondary <- secondary[geography_level == "Brazil"]
national_secondary[, `:=`(
  affected_below_16_change_from_2018 = affected_marriages_below_16 -
    affected_marriages_below_16[year == 2018L],
  causal_status = "descriptive corroboration; no untreated geographic unit"
)]
fwrite(national_secondary, file.path(table_dir, "REGISTRY_SECONDARY_OUTCOMES_BRAZIL.csv"))

tests <- rbindlist(list(
  data.table(test = "three delay ages estimated", passed = nrow(delay_events) == 3L, observed = as.character(nrow(delay_events))),
  data.table(test = "recapture bootstrap has 999 aligned draws", passed = nrow(event_draws) == 999L, observed = as.character(nrow(event_draws))),
  data.table(test = "dynamic paths cover three ages and 47 periods", passed = nrow(delay_dynamic) == 141L & uniqueN(delay_dynamic$focal_age) == 3L, observed = paste(nrow(delay_dynamic), uniqueN(delay_dynamic$focal_age), sep = ",")),
  data.table(test = "recapture point follows locked denominator rule", passed = recapture$point_ratio_defined == (recapture$age15_estimated_deficit > 1e-10), observed = as.character(recapture$point_ratio_defined)),
  data.table(test = "exposure has 27 UFs", passed = nrow(exposure) == 27L, observed = as.character(nrow(exposure))),
  data.table(test = "exposure uses 2013-2017 only", passed = all(exposure$exposure_training_years == "2013-2017"), observed = paste(unique(exposure$exposure_training_years), collapse = ",")),
  data.table(test = "2018 excluded from exposure construction", passed = all(!is.na(exposure$affected_2018)) & all(!grepl("2018", exposure$exposure_training_years)), observed = "2018 holdout columns separate"),
  data.table(test = "raw and EB DDD executed", passed = nrow(ddd_results) == 2L, observed = as.character(nrow(ddd_results))),
  data.table(test = "DDD has 27 UFs and nine years", passed = uniqueN(ddd$uf_code) == 27L & uniqueN(ddd$year) == 9L, observed = paste(uniqueN(ddd$uf_code), uniqueN(ddd$year), sep = ",")),
  data.table(test = "affected share bounded", passed = all(national_secondary$affected_share_below_16 %between% c(0, 1)), observed = paste(range(national_secondary$affected_share_below_16), collapse = ",")),
  data.table(test = "below-15 reported as counts/shares not rate", passed = !"below_15_rate" %in% names(national_secondary), observed = "no below-15 population rate")
), use.names = TRUE)
fwrite(tests, file.path(audit_dir, "DELAY_EXPOSURE_ACCEPTANCE_TESTS.csv"))
if (!all(tests$passed)) {
  print(tests[passed == FALSE])
  stop("Delay/exposure acceptance test failed")
}

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("recapture_point=%s", ifelse(is.finite(point_recapture), format(point_recapture, digits = 12), "undefined")),
  sprintf("recapture_valid_draws=%d", length(valid_recapture)),
  sprintf("ddd_eb_gradient=%.12f", ddd_eb$period["beta"]),
  sprintf("ddd_eb_period_cluster_p=%.12f", ddd_eb$period["p"]),
  sprintf("tests_passed=%d", sum(tests$passed)),
  sprintf("tests_total=%d", nrow(tests)),
  "gate=D_delay_exposure"
)
writeLines(log_lines, file.path(log_dir, "14_analyze_delay_exposure.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
