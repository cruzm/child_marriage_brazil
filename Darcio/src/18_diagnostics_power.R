#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
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
cfg <- read_yaml(file.path(root, "config", "analysis.yml"))

registry <- fread(file.path(data_dir, "REGISTRY_QUARTERLY_PANEL_REGION.csv"))
registry_brazil <- fread(file.path(data_dir, "REGISTRY_QUARTERLY_PANEL_BRAZIL.csv"))
union <- fread(file.path(data_dir, "PNADC_UNION_ANALYTIC_CELLS.csv"))
union_denom <- fread(file.path(data_dir, "QUARTERLY_DENOMINATORS_AGE_SEX.csv"))[
  geography_level == "Brazil",
  .(year, quarter, geography_value, age, sex, population)
]
union <- merge(union, union_denom,
               by = c("year", "quarter", "geography_value", "age", "sex"),
               all.x = TRUE)

extract <- function(model, vcov_spec = ~period) {
  ct <- coeftable(model, vcov = vcov_spec)
  beta <- unname(ct["treat_post", "Estimate"])
  se <- unname(ct["treat_post", "Std. Error"])
  data.table(
    estimate = beta, std_error = se, p_value = 2 * pnorm(-abs(beta / se)),
    ci_lower = beta - qnorm(0.975) * se,
    ci_upper = beta + qnorm(0.975) * se
  )
}

# Pre-window sensitivity fixed before interpreting results.
registry_pre_windows <- rbindlist(lapply(2013:2015, function(start_year) {
  d <- copy(registry[
    sex == "combined" & age %in% c(15L, 17:19) & year >= start_year &
      (year <= 2018L | (year == 2019L & quarter >= 2L))
  ])
  d[, `:=`(
    treat_post = treated_age * post_full,
    trend_age_15 = trend_2018q4 * as.integer(age == 15L),
    trend_age_17 = trend_2018q4 * as.integer(age == 17L),
    trend_age_18 = trend_2018q4 * as.integer(age == 18L)
  )]
  model <- fepois(
    persons_married ~ treat_post + trend_age_15 + trend_age_17 + trend_age_18 |
      geography_value^age + geography_value^period + age^quarter,
    offset = ~offset_log_population, data = d, warn = FALSE
  )
  out <- extract(model)
  out[, `:=`(
    outcome = "formal marriage registration age 15",
    pre_start_year = start_year, pre_end = "2018Q4", post = "2019Q2-Q4",
    rate_ratio = exp(estimate), percent_change = 100 * (exp(estimate) - 1),
    periods = uniqueN(d$period), model = "PPML with age-specific trends"
  )]
  out
}), use.names = TRUE)
fwrite(registry_pre_windows, file.path(table_dir, "REGISTRY_PREWINDOW_SENSITIVITY.csv"))

union_pre_windows <- rbindlist(lapply(2013:2015, function(start_year) {
  d <- copy(union[
    geography_level == "Brazil" & sex == "combined" &
      age %in% c(15L, 17:19) & year >= start_year &
      (year <= 2018L | (year == 2019L & quarter >= 2L))
  ])
  d[, `:=`(
    treat_post = treated_age * post_full,
    trend_age_15 = trend_2018q4 * as.integer(age == 15L),
    trend_age_17 = trend_2018q4 * as.integer(age == 17L),
    trend_age_18 = trend_2018q4 * as.integer(age == 18L)
  )]
  variance <- d$union_conservative_se^2
  inverse <- 1 / variance
  bounds <- quantile(inverse[is.finite(inverse)], c(0.05, 0.95))
  d[, meta_weight := pmin(pmax(inverse, bounds[1L]), bounds[2L])]
  model <- feols(
    union_conservative ~ treat_post + trend_age_15 + trend_age_17 + trend_age_18 |
      age^quarter + period,
    weights = ~meta_weight, data = d, warn = FALSE
  )
  out <- extract(model)
  out[, `:=`(
    outcome = "union_conservative age 15",
    pre_start_year = start_year, pre_end = "2018Q4", post = "2019Q2-Q4",
    effect_percentage_points = 100 * estimate,
    periods = uniqueN(d$period), model = "inverse-design-variance cell LPM with age trends"
  )]
  out
}), use.names = TRUE)
fwrite(union_pre_windows, file.path(table_dir, "PNADC_UNION_PREWINDOW_SENSITIVITY.csv"))

# Economic-relevance diagnostics from simultaneous dynamic bands.
registry_dynamic <- fread(file.path(table_dir, "REGISTRY_DYNAMIC_FORECAST_EVENT_STUDY.csv"))
registry_leads <- registry_dynamic[year <= 2018L]
registry_bound <- log(1.10)
registry_pretrend <- data.table(
  outcome = "Registry log-rate gap",
  leads = nrow(registry_leads),
  joint_lead_p_value = fread(file.path(table_dir, "REGISTRY_DYNAMIC_FORECAST_SUMMARY.csv"))$joint_lead_p_value,
  economic_bound = registry_bound,
  economic_bound_interpretation = "+/-10% rate-ratio deviation",
  maximum_absolute_lead_point = max(abs(registry_leads$dynamic_log_effect)),
  all_simultaneous_intervals_inside_bound = all(
    registry_leads$simultaneous_ci_lower > -registry_bound &
      registry_leads$simultaneous_ci_upper < registry_bound
  ),
  leads_with_interval_inside_bound = sum(
    registry_leads$simultaneous_ci_lower > -registry_bound &
      registry_leads$simultaneous_ci_upper < registry_bound
  ),
  interpretation = "failure to reject is not proof of parallel trends"
)

union_dynamic <- fread(file.path(table_dir, "PNADC_UNION_DYNAMIC_FORECAST_EVENT_STUDY.csv"))
union_leads <- union_dynamic[year <= 2018L]
union_bound <- 0.005
union_pretrend <- data.table(
  outcome = "PNADC union prevalence gap",
  leads = nrow(union_leads),
  joint_lead_p_value = fread(file.path(table_dir, "PNADC_UNION_DYNAMIC_FORECAST_SUMMARY.csv"))$joint_lead_p_value,
  economic_bound = union_bound,
  economic_bound_interpretation = "+/-0.50 percentage point",
  maximum_absolute_lead_point = max(abs(union_leads$dynamic_effect)),
  all_simultaneous_intervals_inside_bound = all(
    union_leads$simultaneous_ci_lower > -union_bound &
      union_leads$simultaneous_ci_upper < union_bound
  ),
  leads_with_interval_inside_bound = sum(
    union_leads$simultaneous_ci_lower > -union_bound &
      union_leads$simultaneous_ci_upper < union_bound
  ),
  interpretation = "failure to reject is not proof of parallel trends"
)
pretrend <- rbindlist(list(registry_pretrend, union_pretrend), use.names = TRUE)
fwrite(pretrend, file.path(table_dir, "PRETREND_DIAGNOSTICS.csv"))

# Pre-period seasonality, shown rather than assumed away.
registry_seasonality <- registry_brazil[
  sex == "combined" & year <= 2018L & age %in% 15:19,
  .(
    mean_rate_100k = mean(formal_marriage_rate_100k),
    sd_rate_100k = sd(formal_marriage_rate_100k),
    minimum_rate_100k = min(formal_marriage_rate_100k),
    maximum_rate_100k = max(formal_marriage_rate_100k),
    quarters_observed = .N
  ), by = .(age, quarter)
]
fwrite(registry_seasonality, file.path(table_dir, "REGISTRY_PRELAW_SEASONALITY.csv"))
union_seasonality <- union[
  geography_level == "Brazil" & sex == "combined" & year <= 2018L & age %in% 14:19,
  .(
    mean_prevalence = mean(union_conservative),
    sd_prevalence = sd(union_conservative),
    mean_design_se = mean(union_conservative_se),
    quarters_observed = .N
  ), by = .(age, quarter)
]
fwrite(union_seasonality, file.path(table_dir, "PNADC_UNION_PRELAW_SEASONALITY.csv"))

# Power and MDE. These quantify detectability, not evidence of an effect.
registry_primary <- fread(file.path(table_dir, "REGISTRY_PRIMARY_EFFECT.csv"))
registry_se <- registry_primary$beta_se_period_cluster
zcrit <- qnorm(0.975)
zpower <- qnorm(0.80)
power_two_sided <- function(beta, se) {
  delta <- beta / se
  pnorm(-zcrit - delta) + 1 - pnorm(zcrit - delta)
}
declines <- c(0.10, 0.20, 0.30, 0.40)
registry_power <- data.table(
  outcome = "formal marriage age 15",
  target_decline_percent = 100 * declines,
  target_log_rate_ratio = log(1 - declines),
  approximate_power = vapply(log(1 - declines), power_two_sided, numeric(1L), se = registry_se),
  standard_error = registry_se,
  mde_log_scale = (zcrit + zpower) * registry_se,
  mde_decline_percent = 100 * (1 - exp(-(zcrit + zpower) * registry_se)),
  alpha = 0.05, target_power = 0.80,
  caveat = "normal approximation with period-cluster SE and only three treated post quarters"
)
union_primary <- fread(file.path(table_dir, "PNADC_UNION_PRIMARY_EFFECT.csv"))
union_power <- data.table(
  outcome = "union_conservative age 15",
  target_decline_percent = NA_real_, target_log_rate_ratio = NA_real_,
  approximate_power = 0.80,
  standard_error = union_primary$combined_se_quadrature,
  mde_log_scale = NA_real_,
  mde_decline_percent = NA_real_,
  alpha = 0.05, target_power = 0.80,
  caveat = sprintf("MDE %.3f percentage points using temporal plus marginal design variance",
                   union_primary$mde_80_power_percentage_points)
)
power_table <- rbindlist(list(registry_power, union_power), use.names = TRUE, fill = TRUE)
power_table[outcome == "union_conservative age 15",
            mde_percentage_points := union_primary$mde_80_power_percentage_points]
fwrite(power_table, file.path(table_dir, "POWER_AND_MDE.csv"))

# Distribution/bunching summaries use people, never marriage-event counts.
distribution <- registry_brazil[
  sex == "combined" & age %in% 15:19,
  .(persons_married = sum(persons_married), population = sum(population)),
  by = .(
    window = fcase(
      year <= 2018L, "pre_2013_2018",
      year == 2019L & quarter == 1L, "partial_2019Q1",
      year == 2019L & quarter %in% 2:4, "short_2019Q2_Q4",
      year %in% c(2020L, 2021L), "pandemic_2020_2021",
      year >= 2022L, "post_pandemic_2022_2024"
    ),
    age
  )
]
distribution[, `:=`(
  share_among_ages_15_19 = persons_married / sum(persons_married),
  rate_per_100k = 100000 * persons_married / population
), by = window]
fwrite(distribution, file.path(table_dir, "REGISTRY_AGE_DISTRIBUTION_WINDOWS.csv"))

# Placebo and divergence synopsis for report routing.
placebo_dates <- fread(file.path(table_dir, "REGISTRY_PLACEBO_DATES.csv"))
placebo_ages <- fread(file.path(table_dir, "REGISTRY_AGE_SPECIFIC_EFFECTS.csv"))[
  focal_age %in% 17:19
]
robustness <- fread(file.path(table_dir, "REGISTRY_ROBUSTNESS_GRID.csv"))
trend_divergence <- robustness[
  sex == "combined" & controls == "17-18-19" & model == "PPML" &
    window == "short_run_clean",
  .(age_specific_trends, estimate, std_error, p_value, rate_ratio, percent_change)
]
trend_divergence[, conclusion_status :=
  "material specification divergence; locked trend model remains primary"]
fwrite(trend_divergence, file.path(table_dir, "REGISTRY_TREND_SPECIFICATION_DIVERGENCE.csv"))

tests <- rbindlist(list(
  data.table(test = "three Registry pre-windows estimated", passed = nrow(registry_pre_windows) == 3L, observed = as.character(nrow(registry_pre_windows))),
  data.table(test = "three PNADC pre-windows estimated", passed = nrow(union_pre_windows) == 3L, observed = as.character(nrow(union_pre_windows))),
  data.table(test = "economic pretrend bounds evaluated", passed = nrow(pretrend) == 2L, observed = as.character(nrow(pretrend))),
  data.table(test = "seasonality covers Registry ages 15-19", passed = uniqueN(registry_seasonality$age) == 5L, observed = as.character(uniqueN(registry_seasonality$age))),
  data.table(test = "seasonality covers PNADC ages 14-19", passed = uniqueN(union_seasonality$age) == 6L, observed = as.character(uniqueN(union_seasonality$age))),
  data.table(test = "Registry power includes four target effects", passed = nrow(registry_power) == 4L, observed = as.character(nrow(registry_power))),
  data.table(test = "age distribution shares sum one", passed = max(abs(distribution[, sum(share_among_ages_15_19), by = window]$V1 - 1)) < 1e-12, observed = as.character(max(abs(distribution[, sum(share_among_ages_15_19), by = window]$V1 - 1)))),
  data.table(test = "four locked date placebos available", passed = nrow(placebo_dates) == 4L, observed = as.character(nrow(placebo_dates))),
  data.table(test = "three placebo ages available", passed = nrow(placebo_ages) == 3L, observed = as.character(nrow(placebo_ages))),
  data.table(test = "trend and no-trend estimates both retained", passed = nrow(trend_divergence) == 2L, observed = as.character(nrow(trend_divergence)))
), use.names = TRUE)
fwrite(tests, file.path(audit_dir, "DIAGNOSTICS_POWER_ACCEPTANCE_TESTS.csv"))
if (!all(tests$passed)) {
  print(tests[passed == FALSE])
  stop("Diagnostics/power acceptance test failed")
}

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("registry_joint_lead_p=%.8f", registry_pretrend$joint_lead_p_value),
  sprintf("union_joint_lead_p=%.8f", union_pretrend$joint_lead_p_value),
  sprintf("registry_mde_decline_percent=%.8f", unique(registry_power$mde_decline_percent)),
  sprintf("union_mde_percentage_points=%.8f", union_primary$mde_80_power_percentage_points),
  sprintf("tests_passed=%d", sum(tests$passed)),
  sprintf("tests_total=%d", nrow(tests)),
  "gate=E_diagnostics_power"
)
writeLines(log_lines, file.path(log_dir, "18_diagnostics_power.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
