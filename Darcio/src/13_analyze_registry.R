#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(sandwich)
  library(lmtest)
  library(arrow)
  library(yaml)
  library(parallel)
})

started <- Sys.time()
set.seed(13811)
setFixest_nthreads(1)
setFixest_notes(FALSE)
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
figure_dir <- file.path(root, "outputs", "figures")
audit_dir <- file.path(root, "outputs", "audit")
log_dir <- file.path(root, "outputs", "logs")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
cfg <- read_yaml(file.path(root, "config", "analysis.yml"))
lock <- read_yaml(file.path(root, "config", "specification_lock.yml"))

region <- fread(file.path(data_dir, "REGISTRY_QUARTERLY_PANEL_REGION.csv"))
brazil <- fread(file.path(data_dir, "REGISTRY_QUARTERLY_PANEL_BRAZIL.csv"))
annual <- fread(file.path(data_dir, "REGISTRY_ANNUAL_PANEL_UF.csv"))
weights_synth <- fread(file.path(data_dir, "SYNTHETIC_AGE_WEIGHTS_PRELAW.csv"))
for (x in c("region", "brazil")) {
  get(x)[, `:=`(period = as.character(period), quarter = as.integer(quarter), age = as.integer(age))]
}

window_filter <- function(d, window) {
  switch(window,
    short_run_clean = d[year <= 2018L | (year == 2019L & quarter >= 2L)],
    full_dynamic = d[!(year == 2019L & quarter == 1L)],
    exclude_pandemic = d[!(year == 2019L & quarter == 1L) & !year %in% c(2020L, 2021L)],
    post_pandemic = d[year <= 2018L | year >= 2022L],
    stop("Unknown window: ", window)
  )
}

add_age_trends <- function(d, ages, reference_age, trend_var = "trend_2018q4") {
  trend_names <- character()
  for (a in setdiff(ages, reference_age)) {
    nm <- paste0("trend_age_", a)
    d[, (nm) := get(trend_var) * as.integer(age == a)]
    trend_names <- c(trend_names, nm)
  }
  list(data = d, names = trend_names)
}

model_formula <- function(outcome, treatment, trend_names, level = "region", annual_model = FALSE) {
  rhs <- paste(c(treatment, trend_names), collapse = " + ")
  if (annual_model) {
    fe <- "geography_value^age + geography_value^year"
  } else if (level == "region") {
    fe <- "geography_value^age + geography_value^period + age^quarter"
  } else {
    fe <- "age^quarter + period"
  }
  as.formula(paste(outcome, "~", rhs, "|", fe))
}

coefficient_stats <- function(model, coefficient = "treat_post", vcov_spec = ~period) {
  ct <- coeftable(model, vcov = vcov_spec)
  if (!coefficient %in% rownames(ct)) stop("Missing coefficient ", coefficient)
  estimate <- unname(ct[coefficient, "Estimate"])
  se <- unname(ct[coefficient, "Std. Error"])
  z <- estimate / se
  data.table(
    estimate = estimate,
    std_error = se,
    statistic = z,
    p_value = 2 * pnorm(-abs(z)),
    ci_lower = estimate - qnorm(0.975) * se,
    ci_upper = estimate + qnorm(0.975) * se
  )
}

fit_quarterly <- function(panel, sex_value, controls, window, trends = TRUE,
                          model_type = "PPML", focal_age = 15L, level = "region") {
  ages <- sort(unique(c(focal_age, controls)))
  d <- copy(panel[sex == sex_value & age %in% ages])
  d <- window_filter(d, window)
  d[, focal := as.integer(age == focal_age)]
  d[, post_indicator := if (window == "post_pandemic") as.integer(year >= 2022L) else post_full]
  d[, treat_post := focal * post_indicator]
  trend_names <- character()
  if (trends) {
    tmp <- add_age_trends(d, ages, max(controls))
    d <- tmp$data
    trend_names <- tmp$names
  }
  if (model_type == "PPML") {
    f <- model_formula("persons_married", "treat_post", trend_names, level)
    model <- fepois(f, offset = ~offset_log_population, data = d, warn = FALSE)
  } else {
    f <- model_formula("formal_marriage_rate_100k", "treat_post", trend_names, level)
    model <- feols(f, weights = ~population, data = d, warn = FALSE)
  }
  list(model = model, data = d, trend_names = trend_names)
}

summarize_fit <- function(fit, sex_value, controls, window, trends, model_type,
                          focal_age = 15L, level = "region") {
  stats <- coefficient_stats(fit$model, vcov_spec = ~period)
  stats[, `:=`(
    sex = sex_value,
    focal_age = focal_age,
    controls = paste(controls, collapse = "-"),
    window = window,
    age_specific_trends = trends,
    model = model_type,
    geography = level,
    rate_ratio = if (model_type == "PPML") exp(estimate) else NA_real_,
    percent_change = if (model_type == "PPML") 100 * (exp(estimate) - 1) else NA_real_,
    effect_points_per_100k = if (model_type == "WLS") estimate else NA_real_,
    observations = nobs(fit$model),
    source_rows = nrow(fit$data),
    regions_or_geographies = uniqueN(fit$data$geography_value),
    periods = uniqueN(fit$data$period),
    time_clusters = uniqueN(fit$data$period),
    zero_outcome_cells = sum(fit$data$persons_married == 0L),
    dropped_observations = nrow(fit$data) - nobs(fit$model),
    collinear_variables = paste(fit$model$collin.var, collapse = ";")
  )]
  stats
}

# Locked robustness grid: no specification is selected using results.
control_sets <- list(`17-19` = 17:19, `18-19` = 18:19, `16-17` = 16:17)
windows <- c("short_run_clean", "full_dynamic", "exclude_pandemic", "post_pandemic")
sexes <- c("combined", "female", "male")
trend_options <- c(TRUE, FALSE)
model_types <- c("PPML", "WLS")
grid_results <- list()
grid_index <- 1L
primary_fit <- NULL
for (control_name in names(control_sets)) {
  controls <- control_sets[[control_name]]
  for (window in windows) for (sex_value in sexes) for (trends in trend_options) for (model_type in model_types) {
    fit <- fit_quarterly(region, sex_value, controls, window, trends, model_type, level = "region")
    grid_results[[grid_index]] <- summarize_fit(
      fit, sex_value, controls, window, trends, model_type, level = "region"
    )
    if (control_name == "17-19" && window == "short_run_clean" &&
        sex_value == "combined" && trends && model_type == "PPML") primary_fit <- fit
    grid_index <- grid_index + 1L
  }
}
robustness <- rbindlist(grid_results, use.names = TRUE, fill = TRUE)
robustness[, specification_id := sprintf("REG-Q-%03d", .I)]
setcolorder(robustness, c("specification_id", setdiff(names(robustness), "specification_id")))
fwrite(robustness, file.path(table_dir, "REGISTRY_ROBUSTNESS_GRID.csv"))

if (is.null(primary_fit)) stop("Primary fit was not retained")
primary_period <- coefficient_stats(primary_fit$model, vcov_spec = ~period)
primary_tw <- coefficient_stats(primary_fit$model, vcov_spec = ~geography_value + period)
primary_geo_diagnostic <- coefficient_stats(primary_fit$model, vcov_spec = ~geography_value)
primary_beta <- primary_period$estimate
primary_post <- primary_fit$data[treat_post == 1L]
primary_predictions <- as.numeric(predict(primary_fit$model, type = "response"))
primary_fit$data[, fitted_with_treatment := primary_predictions]
primary_post <- primary_fit$data[treat_post == 1L]
rr <- exp(primary_beta)
primary_post[, fitted_without_treatment := fitted_with_treatment / rr]
primary_post[, estimated_avoided := fitted_without_treatment - fitted_with_treatment]
avoided <- sum(primary_post$estimated_avoided)
points <- -100000 * avoided / sum(primary_post$population)
avoided_from_beta <- function(beta) {
  value <- sum(primary_post$fitted_with_treatment * (exp(-beta) - 1))
  c(events = value, points = -100000 * value / sum(primary_post$population))
}
nonlinear_bounds <- rbind(
  avoided_from_beta(primary_period$ci_lower), avoided_from_beta(primary_period$ci_upper)
)
primary_effect <- data.table(
  estimand = "formal_marriage_rate_15_100k",
  sex = "combined",
  window = "2019Q2-2019Q4",
  controls = "17-19",
  trends = TRUE,
  beta_log_rate_ratio = primary_beta,
  beta_se_period_cluster = primary_period$std_error,
  beta_ci_lower = primary_period$ci_lower,
  beta_ci_upper = primary_period$ci_upper,
  p_value_period_cluster = primary_period$p_value,
  rate_ratio = rr,
  rate_ratio_ci_lower = exp(primary_period$ci_lower),
  rate_ratio_ci_upper = exp(primary_period$ci_upper),
  percent_change = 100 * (rr - 1),
  percent_change_ci_lower = 100 * (exp(primary_period$ci_lower) - 1),
  percent_change_ci_upper = 100 * (exp(primary_period$ci_upper) - 1),
  effect_points_per_100k = points,
  effect_points_ci_lower = min(nonlinear_bounds[, "points"]),
  effect_points_ci_upper = max(nonlinear_bounds[, "points"]),
  estimated_events_avoided = avoided,
  events_avoided_ci_lower = min(nonlinear_bounds[, "events"]),
  events_avoided_ci_upper = max(nonlinear_bounds[, "events"]),
  observed_events_treated_cells = sum(primary_post$persons_married),
  fitted_events_with_treatment = sum(primary_post$fitted_with_treatment),
  fitted_events_without_treatment = sum(primary_post$fitted_without_treatment),
  observations = nobs(primary_fit$model),
  regions = uniqueN(primary_fit$data$geography_value),
  periods = uniqueN(primary_fit$data$period),
  time_clusters = uniqueN(primary_fit$data$period),
  registration_timing = TRUE,
  denominator_treated_as_fixed = TRUE
)
fwrite(primary_effect, file.path(table_dir, "REGISTRY_PRIMARY_EFFECT.csv"))

# Confirmatory female/male exact primary specifications, with locked Holm adjustment.
sex_confirmatory <- robustness[
  model == "PPML" & controls == "17-18-19" & window == "short_run_clean" &
    age_specific_trends == TRUE & sex %in% c("female", "male")
]
sex_confirmatory[, p_value_holm := p.adjust(p_value, method = "holm")]
fwrite(sex_confirmatory, file.path(table_dir, "REGISTRY_PRIMARY_BY_SEX.csv"))

# Primary geographic sensitivity at Brazil, unchanged otherwise.
brazil_results <- rbindlist(lapply(sexes, function(sex_value) {
  fit <- fit_quarterly(brazil, sex_value, 17:19, "short_run_clean", TRUE, "PPML", level = "Brazil")
  summarize_fit(fit, sex_value, 17:19, "short_run_clean", TRUE, "PPML", level = "Brazil")
}), use.names = TRUE)
fwrite(brazil_results, file.path(table_dir, "REGISTRY_BRAZIL_SENSITIVITY.csv"))

# Annual UF robustness (2019 and unavailable 2020-2021 denominators omitted).
annual_results <- list()
for (sex_value in sexes) for (trends in trend_options) {
  d <- copy(annual[sex == sex_value & age %in% c(15L, 17:19) & year != 2019L])
  d[, treat_post := as.integer(age == 15L) * as.integer(year >= 2020L)]
  trend_names <- character()
  if (trends) {
    tmp <- add_age_trends(d, c(15L, 17:19), 19L, "trend_2018")
    d <- tmp$data
    trend_names <- tmp$names
  }
  f <- model_formula("persons_married", "treat_post", trend_names,
                     annual_model = TRUE)
  m <- fepois(f, offset = ~offset_log_population, data = d, warn = FALSE)
  st <- coefficient_stats(m, vcov_spec = ~year)
  st[, `:=`(
    sex = sex_value, age_specific_trends = trends, model = "PPML",
    frequency = "annual", controls = "17-19", years = paste(sort(unique(d$year)), collapse = ","),
    observations = nobs(m), year_clusters = uniqueN(d$year),
    rate_ratio = exp(estimate), percent_change = 100 * (exp(estimate) - 1),
    interpretation = "annual UF robustness; 2019 and 2020-2021 absent/omitted"
  )]
  annual_results[[length(annual_results) + 1L]] <- st
}
annual_results <- rbindlist(annual_results, use.names = TRUE)
fwrite(annual_results, file.path(table_dir, "REGISTRY_ANNUAL_UF_ROBUSTNESS.csv"))

# Marginal denominator uncertainty: 499 positive lognormal draws, refitting locked primary model.
draw_beta <- function(seed_value) {
  set.seed(seed_value)
  d <- copy(primary_fit$data)
  log_sd <- sqrt(log1p((d$population_se / d$population)^2))
  log_mean <- log(d$population) - 0.5 * log_sd^2
  d[, population_draw := rlnorm(.N, log_mean, log_sd)]
  d[, offset_log_population := log(population_draw)]
  tmp <- add_age_trends(d, c(15L, 17:19), 19L)
  f <- model_formula("persons_married", "treat_post", tmp$names, "region")
  m <- fepois(f, offset = ~offset_log_population, data = tmp$data, warn = FALSE)
  unname(coef(m)["treat_post"])
}
denominator_betas <- unlist(mclapply(
  13811L + seq_len(499L), draw_beta,
  mc.cores = min(4L, max(1L, floor(detectCores() / 2L))), mc.preschedule = TRUE
))
denominator_sensitivity <- data.table(
  draws = length(denominator_betas),
  fixed_offset_beta = primary_beta,
  draw_mean_beta = mean(denominator_betas),
  draw_sd_beta = sd(denominator_betas),
  draw_ci_lower = quantile(denominator_betas, 0.025),
  draw_ci_upper = quantile(denominator_betas, 0.975),
  draw_mean_percent_change = 100 * (mean(exp(denominator_betas)) - 1),
  marginal_design_se_only = TRUE,
  covariance_between_cells_available = FALSE,
  seed = 13811
)
fwrite(denominator_sensitivity, file.path(table_dir, "REGISTRY_DENOMINATOR_UNCERTAINTY.csv"))
fwrite(data.table(draw = seq_along(denominator_betas), beta = denominator_betas),
       file.path(audit_dir, "REGISTRY_DENOMINATOR_UNCERTAINTY_DRAWS.csv"))

# Aggregate Brazil log-rate gap and honest time-series uncertainty.
gap_source <- brazil[sex == "combined" & age %in% c(15L, 17:19)]
age15 <- gap_source[age == 15L, .(
  year, quarter, period, period_index, trend_2018q4, post_full, partial_2019q1,
  pandemic, rate15 = formal_marriage_rate_100k,
  count15 = persons_married, population15 = population
)]
control <- gap_source[age %in% 17:19, .(
  control_count = sum(persons_married), control_population = sum(population)
), by = .(year, quarter, period)]
gap <- merge(age15, control, by = c("year", "quarter", "period"))
gap[, control_rate := 100000 * control_count / control_population]
if (any(gap$rate15 <= 0 | gap$control_rate <= 0)) stop("Log-rate gap has a zero")
gap[, log_rate_gap := log(rate15) - log(control_rate)]
gap[, quarter_factor := factor(quarter, levels = 1:4)]
setorder(gap, year, quarter)

pre_gap <- gap[year <= 2018L]
forecast_model <- lm(log_rate_gap ~ trend_2018q4 + quarter_factor, data = pre_gap)
gap[, counterfactual_gap := as.numeric(predict(forecast_model, newdata = gap))]
gap[, dynamic_log_effect := log_rate_gap - counterfactual_gap]
pre_residual <- residuals(forecast_model)
pre_residual <- pre_residual - mean(pre_residual)

circular_blocks <- function(values, target_n, block_length = 4L) {
  starts <- sample.int(length(values), ceiling(target_n / block_length), replace = TRUE)
  out <- unlist(lapply(starts, function(s) values[((s - 1L + 0:(block_length - 1L)) %% length(values)) + 1L]))
  out[seq_len(target_n)]
}
bootstrap_errors <- matrix(NA_real_, nrow = 999L, ncol = nrow(gap))
for (b in seq_len(999L)) {
  e <- circular_blocks(pre_residual, nrow(gap), 4L)
  null_y <- gap$counterfactual_gap + e
  boot_pre <- copy(gap[year <= 2018L])
  boot_pre[, null_y := null_y[seq_len(.N)]]
  boot_fit <- lm(null_y ~ trend_2018q4 + quarter_factor, data = boot_pre)
  boot_pred <- as.numeric(predict(boot_fit, newdata = gap))
  bootstrap_errors[b, ] <- null_y - boot_pred
}
boot_se <- apply(bootstrap_errors, 2L, sd)
point_lower <- point_upper <- numeric(nrow(gap))
for (j in seq_len(nrow(gap))) {
  qs <- quantile(bootstrap_errors[, j], c(0.975, 0.025), na.rm = TRUE)
  point_lower[j] <- gap$dynamic_log_effect[j] - qs[1L]
  point_upper[j] <- gap$dynamic_log_effect[j] - qs[2L]
}
valid_se <- boot_se > 0 & is.finite(boot_se)
max_z_boot <- apply(abs(sweep(bootstrap_errors[, valid_se, drop = FALSE], 2L, boot_se[valid_se], "/")), 1L, max)
simultaneous_critical <- quantile(max_z_boot, 0.95)
gap[, `:=`(
  bootstrap_se = boot_se,
  pointwise_ci_lower = point_lower,
  pointwise_ci_upper = point_upper,
  simultaneous_ci_lower = dynamic_log_effect - simultaneous_critical * boot_se,
  simultaneous_ci_upper = dynamic_log_effect + simultaneous_critical * boot_se,
  effect_rate_ratio = exp(dynamic_log_effect),
  simultaneous_rate_ratio_lower = exp(dynamic_log_effect - simultaneous_critical * boot_se),
  simultaneous_rate_ratio_upper = exp(dynamic_log_effect + simultaneous_critical * boot_se)
)]
fwrite(gap, file.path(table_dir, "REGISTRY_DYNAMIC_FORECAST_EVENT_STUDY.csv"))

short_indices <- which(gap$year == 2019L & gap$quarter %in% 2:4)
short_effect <- mean(gap$dynamic_log_effect[short_indices])
short_boot_error <- rowMeans(bootstrap_errors[, short_indices, drop = FALSE])
short_ci <- short_effect - quantile(short_boot_error, c(0.975, 0.025))
short_p <- (1 + sum(abs(short_boot_error) >= abs(short_effect))) / (1 + length(short_boot_error))
lead_indices <- which(gap$year <= 2018L)
observed_lead_max <- max(abs(gap$dynamic_log_effect[lead_indices] / boot_se[lead_indices]))
boot_lead_max <- apply(abs(sweep(bootstrap_errors[, lead_indices, drop = FALSE], 2L,
                                 boot_se[lead_indices], "/")), 1L, max)
lead_p <- (1 + sum(boot_lead_max >= observed_lead_max)) / (1 + length(boot_lead_max))
forecast_summary <- data.table(
  method = "pre-period linear-seasonal forecast with moving-block residual bootstrap",
  short_run_log_effect = short_effect,
  std_error = sd(short_boot_error),
  ci_lower = short_ci[1L],
  ci_upper = short_ci[2L],
  p_value = short_p,
  rate_ratio = exp(short_effect),
  percent_change = 100 * (exp(short_effect) - 1),
  simultaneous_critical_value = simultaneous_critical,
  joint_lead_max_statistic = observed_lead_max,
  joint_lead_p_value = lead_p,
  bootstrap_replications = 999L,
  block_length = 4L,
  pre_periods = nrow(pre_gap),
  post_short_periods = length(short_indices)
)
fwrite(forecast_summary, file.path(table_dir, "REGISTRY_DYNAMIC_FORECAST_SUMMARY.csv"))

# HAC estimate for the same aggregate gap in the locked short window.
gap_short <- gap[year <= 2018L | (year == 2019L & quarter >= 2L)]
hac_model <- lm(log_rate_gap ~ post_full + trend_2018q4 + quarter_factor, data = gap_short)
hac_ct <- coeftest(hac_model, vcov. = NeweyWest(hac_model, lag = 4L, prewhite = FALSE, adjust = TRUE))
hac_beta <- unname(hac_ct["post_full", "Estimate"])
hac_se <- unname(hac_ct["post_full", "Std. Error"])
hac_result <- data.table(
  method = "Brazil age15-vs-pooled17-19 log-rate gap; Newey-West lag 4",
  estimate = hac_beta, std_error = hac_se,
  statistic = hac_beta / hac_se,
  p_value = 2 * pnorm(-abs(hac_beta / hac_se)),
  ci_lower = hac_beta - qnorm(0.975) * hac_se,
  ci_upper = hac_beta + qnorm(0.975) * hac_se,
  rate_ratio = exp(hac_beta),
  percent_change = 100 * (exp(hac_beta) - 1),
  periods = nrow(gap_short), hac_lag = 4L
)
fwrite(hac_result, file.path(table_dir, "REGISTRY_AGGREGATED_HAC.csv"))

# Saturated PPML event-study points; regional cluster uncertainty is diagnostic only (Amendment 1).
event_data <- copy(region[
  sex == "combined" & age %in% c(15L, 17:19) & full_dynamic == 1L
])
event_data[, `:=`(
  trend_age_17 = trend_2018q4 * as.integer(age == 17L),
  trend_age_18 = trend_2018q4 * as.integer(age == 18L)
)]
event_season_names <- character()
for (a in 17:18) for (q in 1:3) {
  nm <- sprintf("season_age_%d_q%d", a, q)
  event_data[, (nm) := as.integer(age == a & quarter == q)]
  event_season_names <- c(event_season_names, nm)
}
event_formula <- as.formula(paste(
  "persons_married ~ i(event_time, treated_age, ref = -1) +",
  paste(c("trend_age_17", "trend_age_18", event_season_names), collapse = " + "),
  "| geography_value^age + geography_value^period"
))
event_model <- fepois(event_formula, offset = ~offset_log_population,
                      data = event_data, warn = FALSE)
event_ct <- as.data.table(coeftable(event_model, vcov = ~geography_value), keep.rownames = "term")
event_ct <- event_ct[grepl("^event_time::", term)]
setnames(event_ct, c("Estimate", "Std. Error", "z value", "Pr(>|z|)"),
         c("estimate", "std_error_region_cluster", "statistic", "p_value_diagnostic"))
event_ct[, event_time := as.integer(sub("event_time::(-?[0-9]+):.*", "\\1", term))]
event_ct[, `:=`(
  ci_lower_diagnostic = estimate - qnorm(0.975) * std_error_region_cluster,
  ci_upper_diagnostic = estimate + qnorm(0.975) * std_error_region_cluster,
  rate_ratio = exp(estimate),
  regions = uniqueN(event_data$geography_value),
  inference_status = "diagnostic only: five region clusters; dynamic inference uses temporal forecast bootstrap"
)]
setorder(event_ct, event_time)
fwrite(event_ct, file.path(table_dir, "REGISTRY_PPML_EVENT_STUDY_POINTS.csv"))

# Locked pseudo-dates and randomization inference.
pseudo_dates <- c("2015Q2", "2016Q2", "2017Q2", "2018Q2")
placebo_dates <- rbindlist(lapply(pseudo_dates, function(label) {
  start_index <- unique(region[period == label, period_index])
  end_index <- start_index + 2L
  d <- copy(region[
    sex == "combined" & age %in% c(15L, 17:19) & period_index <= end_index
  ])
  d[, treat_post := as.integer(age == 15L) * as.integer(period_index >= start_index)]
  tmp <- add_age_trends(d, c(15L, 17:19), 19L)
  f <- model_formula("persons_married", "treat_post", tmp$names, "region")
  m <- fepois(f, offset = ~offset_log_population, data = tmp$data, warn = FALSE)
  st <- coefficient_stats(m, vcov_spec = ~period)
  st[, `:=`(
    pseudo_reform = label,
    pseudo_post_quarters = 3L,
    observations = nobs(m), periods = uniqueN(d$period),
    studentized_absolute = abs(statistic)
  )]
  st
}), use.names = TRUE)
actual_t <- abs(primary_period$statistic)
ri_p <- (1 + sum(placebo_dates$studentized_absolute >= actual_t)) /
  (1 + nrow(placebo_dates))
placebo_dates[, actual_studentized_absolute := actual_t]
placebo_dates[, randomization_p_value := ri_p]
fwrite(placebo_dates, file.path(table_dir, "REGISTRY_PLACEBO_DATES.csv"))

# Locked placebo ages and mechanism age contrasts.
age_contrasts <- list(
  `15` = 17:19,
  `16` = 18:19,
  `17` = 18:19,
  `18` = c(17L, 19L),
  `19` = 17:18
)
age_results <- rbindlist(lapply(names(age_contrasts), function(a) {
  focal <- as.integer(a)
  controls <- age_contrasts[[a]]
  fit <- fit_quarterly(region, "combined", controls, "short_run_clean", TRUE,
                       "PPML", focal_age = focal, level = "region")
  summarize_fit(fit, "combined", controls, "short_run_clean", TRUE,
                "PPML", focal_age = focal, level = "region")
}), use.names = TRUE)
age_results[, p_value_holm_ages_16_19 := NA_real_]
age_results[focal_age %in% 16:19, p_value_holm_ages_16_19 := p.adjust(p_value, method = "holm")]
age_results[, role := fifelse(focal_age == 15L, "primary", fifelse(focal_age %in% 16:17,
  "delay mechanism", "placebo/mechanism"))]
fwrite(age_results, file.path(table_dir, "REGISTRY_AGE_SPECIFIC_EFFECTS.csv"))

# Fixed pre-only synthetic age control applied without reoptimization.
synth_source <- brazil[sex == "combined" & age %in% c(15L, 17:19)]
synth_wide <- dcast(
  synth_source,
  year + quarter + period + trend_2018q4 + post_full + partial_2019q1 + pandemic ~ age,
  value.var = "formal_marriage_rate_100k"
)
weight_map <- setNames(weights_synth$weight, weights_synth$donor_age)
synth_wide[, synthetic_rate := `17` * weight_map["17"] +
             `18` * weight_map["18"] + `19` * weight_map["19"]]
synth_wide[, synthetic_gap := `15` - synthetic_rate]
synth_wide[, quarter_factor := factor(quarter, levels = 1:4)]
synth_pre_model <- lm(synthetic_gap ~ trend_2018q4 + quarter_factor,
                      data = synth_wide[year <= 2018L])
synth_wide[, predicted_no_law_gap := as.numeric(predict(synth_pre_model, newdata = synth_wide))]
synth_wide[, adjusted_gap := synthetic_gap - predicted_no_law_gap]
synth_short <- synth_wide[year == 2019L & quarter %in% 2:4, mean(adjusted_gap)]
synth_holdout <- sqrt(mean(synth_wide[year == 2018L, adjusted_gap^2]))
synthetic_summary <- data.table(
  short_run_effect_points_per_100k = synth_short,
  holdout_2018_adjusted_gap_rmspe = synth_holdout,
  weight_age17 = weight_map["17"], weight_age18 = weight_map["18"],
  weight_age19 = weight_map["19"], post_information_used_for_weights = FALSE
)
fwrite(synth_wide, file.path(table_dir, "REGISTRY_SYNTHETIC_AGE_GAPS.csv"))
fwrite(synthetic_summary, file.path(table_dir, "REGISTRY_SYNTHETIC_AGE_SUMMARY.csv"))

# Unified inference table; methods retain their estimand labels when not numerically identical.
inference <- rbindlist(list(
  data.table(
    method = "PPML cluster by period (primary)", estimand_scale = "log rate ratio",
    estimate = primary_period$estimate, std_error = primary_period$std_error,
    ci_lower = primary_period$ci_lower, ci_upper = primary_period$ci_upper,
    p_value = primary_period$p_value, clusters_or_replications = uniqueN(primary_fit$data$period),
    caveat = "three treated post-period clusters"
  ),
  data.table(
    method = "PPML two-way region and period", estimand_scale = "log rate ratio",
    estimate = primary_tw$estimate, std_error = primary_tw$std_error,
    ci_lower = primary_tw$ci_lower, ci_upper = primary_tw$ci_upper,
    p_value = primary_tw$p_value, clusters_or_replications = uniqueN(primary_fit$data$period),
    caveat = "only five region clusters; covariance required positive-semidefinite adjustment; not conclusion-supporting"
  ),
  data.table(
    method = "PPML cluster by region (diagnostic)", estimand_scale = "log rate ratio",
    estimate = primary_geo_diagnostic$estimate, std_error = primary_geo_diagnostic$std_error,
    ci_lower = primary_geo_diagnostic$ci_lower, ci_upper = primary_geo_diagnostic$ci_upper,
    p_value = primary_geo_diagnostic$p_value, clusters_or_replications = uniqueN(primary_fit$data$geography_value),
    caveat = "five clusters; not conclusion-supporting"
  ),
  data.table(
    method = hac_result$method, estimand_scale = "aggregated log-rate gap",
    estimate = hac_result$estimate, std_error = hac_result$std_error,
    ci_lower = hac_result$ci_lower, ci_upper = hac_result$ci_upper,
    p_value = hac_result$p_value, clusters_or_replications = hac_result$periods,
    caveat = "Brazil series approximation; HAC lag 4"
  ),
  data.table(
    method = forecast_summary$method, estimand_scale = "aggregated forecast log-rate gap",
    estimate = forecast_summary$short_run_log_effect, std_error = forecast_summary$std_error,
    ci_lower = forecast_summary$ci_lower, ci_upper = forecast_summary$ci_upper,
    p_value = forecast_summary$p_value, clusters_or_replications = 999L,
    caveat = "pre-period residual block bootstrap"
  ),
  data.table(
    method = "pre-specified date randomization inference", estimand_scale = "studentized PPML statistic",
    estimate = primary_period$statistic, std_error = NA_real_, ci_lower = NA_real_, ci_upper = NA_real_,
    p_value = ri_p, clusters_or_replications = length(pseudo_dates),
    caveat = "only four locked pseudo-dates; p-values are coarse"
  )
), use.names = TRUE, fill = TRUE)
inference[, `:=`(
  rate_ratio = fifelse(grepl("log-rate|log rate", estimand_scale), exp(estimate), NA_real_),
  percent_change = fifelse(grepl("log-rate|log rate", estimand_scale), 100 * (exp(estimate) - 1), NA_real_)
)]
fwrite(inference, file.path(table_dir, "REGISTRY_INFERENCE_TRIANGULATION.csv"))

# Raw rates for figures and descriptive table, including denominator-only uncertainty.
raw_rates <- copy(brazil[sex %in% sexes & age %in% 15:19])
raw_rates[, denominator_only_rate_se := formal_marriage_rate_100k * population_se / population]
raw_rates[, `:=`(
  denominator_only_ci_lower = pmax(0, formal_marriage_rate_100k - qnorm(0.975) * denominator_only_rate_se),
  denominator_only_ci_upper = formal_marriage_rate_100k + qnorm(0.975) * denominator_only_rate_se
)]
fwrite(raw_rates, file.path(table_dir, "REGISTRY_RAW_RATES_BRAZIL.csv"))

# Model/drop diagnostics.
diagnostics <- data.table(
  model = c("primary_PPML", "event_PPML"),
  input_rows = c(nrow(primary_fit$data), nrow(event_data)),
  observations_used = c(nobs(primary_fit$model), nobs(event_model)),
  dropped_observations = c(nrow(primary_fit$data) - nobs(primary_fit$model),
                           nrow(event_data) - nobs(event_model)),
  collinear_variables = c(paste(primary_fit$model$collin.var, collapse = ";"),
                          paste(event_model$collin.var, collapse = ";")),
  zero_outcome_cells = c(sum(primary_fit$data$persons_married == 0L),
                         sum(event_data$persons_married == 0L)),
  regions = c(uniqueN(primary_fit$data$geography_value), uniqueN(event_data$geography_value)),
  periods = c(uniqueN(primary_fit$data$period), uniqueN(event_data$period))
)
fwrite(diagnostics, file.path(audit_dir, "REGISTRY_MODEL_DIAGNOSTICS.csv"))

tests <- rbindlist(list(
  data.table(test = "locked robustness grid has 144 models", passed = nrow(robustness) == 144L, observed = as.character(nrow(robustness))),
  data.table(test = "primary model has treatment coefficient", passed = is.finite(primary_beta), observed = as.character(primary_beta)),
  data.table(test = "primary PPML drops no observations", passed = nrow(primary_fit$data) == nobs(primary_fit$model), observed = as.character(nrow(primary_fit$data) - nobs(primary_fit$model))),
  data.table(test = "primary has 27 periods and five regions", passed = uniqueN(primary_fit$data$period) == 27L & uniqueN(primary_fit$data$geography_value) == 5L, observed = paste(uniqueN(primary_fit$data$period), uniqueN(primary_fit$data$geography_value), sep = ",")),
  data.table(test = "denominator sensitivity has 499 finite draws", passed = length(denominator_betas) == 499L & all(is.finite(denominator_betas)), observed = as.character(sum(is.finite(denominator_betas)))),
  data.table(test = "dynamic forecast bootstrap has 999 replications", passed = nrow(bootstrap_errors) == 999L, observed = as.character(nrow(bootstrap_errors))),
  data.table(test = "event model retains all event indicators", passed = !any(grepl("event_time", event_model$collin.var)), observed = paste(event_model$collin.var, collapse = ";")),
  data.table(test = "four locked date placebos executed", passed = nrow(placebo_dates) == 4L, observed = as.character(nrow(placebo_dates))),
  data.table(test = "five age contrasts executed", passed = nrow(age_results) == 5L, observed = as.character(nrow(age_results))),
  data.table(test = "synthetic weights unchanged", passed = all.equal(sum(weights_synth$weight), 1, tolerance = 1e-10) == TRUE, observed = paste(weights_synth$weight, collapse = ",")),
  data.table(test = "no conventional RD estimated", passed = TRUE, observed = "age-based DiD/event forecast only")
), use.names = TRUE)
fwrite(tests, file.path(audit_dir, "REGISTRY_ANALYSIS_ACCEPTANCE_TESTS.csv"))
if (!all(tests$passed)) {
  print(tests[passed == FALSE])
  stop("Registry analysis acceptance test failed")
}

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("robustness_models=%d", nrow(robustness)),
  sprintf("denominator_draws=%d", length(denominator_betas)),
  sprintf("temporal_bootstrap_replications=%d", nrow(bootstrap_errors)),
  sprintf("primary_beta=%.12f", primary_beta),
  sprintf("primary_period_cluster_se=%.12f", primary_period$std_error),
  sprintf("primary_period_cluster_p=%.12f", primary_period$p_value),
  sprintf("primary_percent_change=%.8f", primary_effect$percent_change),
  sprintf("tests_passed=%d", sum(tests$passed)),
  sprintf("tests_total=%d", nrow(tests)),
  "specification_amendments=1-2 dynamic event-study trend/seasonality rank and inference",
  "gate=D_registry_analysis"
)
writeLines(log_lines, file.path(log_dir, "13_analyze_registry.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
