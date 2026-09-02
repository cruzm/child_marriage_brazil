#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(sandwich)
  library(lmtest)
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

registry <- fread(file.path(data_dir, "REGISTRY_PERSON_EVENTS_MONTHLY.csv"))[
  age %in% 15:19
]
denom <- fread(file.path(data_dir, "QUARTERLY_DENOMINATORS_AGE_SEX.csv"))[
  geography_level %in% c("region", "Brazil") & age %in% 15:19,
  .(year, quarter, geography_level, geography_value, age, sex,
    population, population_se)
]
region_codes <- c(
  "North" = "1", "Northeast" = "2", "Southeast" = "3",
  "South" = "4", "Central-West" = "5"
)
registry[, `:=`(
  quarter = as.integer(ceiling(month / 3)),
  geography_value = unname(region_codes[region])
)]
region_counts <- registry[, .(
  persons_married = sum(persons_married),
  opposite_sex_people = sum(opposite_sex_people),
  same_sex_people = sum(same_sex_people)
), by = .(year, month, quarter, geography_value, age, sex)]
brazil_counts <- region_counts[, .(
  persons_married = sum(persons_married),
  opposite_sex_people = sum(opposite_sex_people),
  same_sex_people = sum(same_sex_people)
), by = .(year, month, quarter, age, sex)][, geography_value := "Brazil"]

make_panel <- function(counts, level) {
  d <- merge(
    counts,
    denom[geography_level == level,
          .(year, quarter, geography_value, age, sex, population, population_se)],
    by = c("year", "quarter", "geography_value", "age", "sex"), all = TRUE
  )
  d[, `:=`(
    geography_level = level,
    period = sprintf("%dM%02d", year, month),
    month_index = (year - 2013L) * 12L + month,
    trend_2019m02 = (year - 2019L) * 12L + month - 2L,
    treated_age = as.integer(age == 15L),
    partial_march_2019 = as.integer(year == 2019L & month == 3L),
    post_april_2019 = as.integer(year > 2019L | (year == 2019L & month >= 4L)),
    formal_marriage_rate_100k = 100000 * persons_married / population,
    offset_log_population = log(population)
  )]
  d[, event_time := fifelse(
    year < 2019L | (year == 2019L & month <= 2L),
    (year - 2019L) * 12L + month - 3L,
    fifelse(year == 2019L & month == 3L, NA_integer_,
            (year - 2019L) * 12L + month - 4L)
  )]
  setorder(d, year, month, geography_value, sex, age)
  d
}
region_panel <- make_panel(region_counts, "region")
brazil_panel <- make_panel(brazil_counts, "Brazil")

fit_monthly <- function(sex_value, controls, trends, level = "region") {
  panel <- if (level == "region") region_panel else brazil_panel
  ages <- sort(unique(c(15L, controls)))
  d <- copy(panel[
    sex == sex_value & age %in% ages &
      (year < 2019L | (year == 2019L & month != 3L)) & year <= 2019L
  ])
  d[, treat_post := treated_age * post_april_2019]
  trend_names <- character()
  if (trends) for (a in setdiff(ages, max(controls))) {
    nm <- paste0("trend_age_", a)
    d[, (nm) := trend_2019m02 * as.integer(age == a)]
    trend_names <- c(trend_names, nm)
  }
  rhs <- paste(c("treat_post", trend_names), collapse = " + ")
  fe <- if (level == "region") {
    "geography_value^age + geography_value^period + age^month"
  } else "age^month + period"
  f <- as.formula(paste("persons_married ~", rhs, "|", fe))
  model <- fepois(f, offset = ~offset_log_population, data = d, warn = FALSE)
  ct <- coeftable(model, vcov = ~period)
  beta <- unname(ct["treat_post", "Estimate"])
  se <- unname(ct["treat_post", "Std. Error"])
  data.table(
    estimate = beta, std_error = se, statistic = beta / se,
    p_value = 2 * pnorm(-abs(beta / se)),
    ci_lower = beta - qnorm(0.975) * se,
    ci_upper = beta + qnorm(0.975) * se,
    rate_ratio = exp(beta), percent_change = 100 * (exp(beta) - 1),
    sex = sex_value, controls = paste(controls, collapse = "-"),
    age_specific_trends = trends, geography = level,
    pre_start = "2013M01", baseline = "2019M02", omitted = "2019M03",
    post = "2019M04-2019M12", observations = nobs(model),
    periods = uniqueN(d$period), period_clusters = uniqueN(d$period),
    dropped_observations = nrow(d) - nobs(model),
    timing_semantics = "month of registration, not occurrence/celebration"
  )
}

control_sets <- list(`17-19` = 17:19, `18-19` = 18:19, `16-17` = 16:17)
monthly_results <- list()
for (control_name in names(control_sets)) for (sex_value in c("combined", "female", "male")) for (trends in c(TRUE, FALSE)) {
  monthly_results[[length(monthly_results) + 1L]] <- fit_monthly(
    sex_value, control_sets[[control_name]], trends, "region"
  )
}
monthly_results <- rbindlist(monthly_results, use.names = TRUE)
monthly_results[, specification_id := sprintf("REG-M-%02d", .I)]
setcolorder(monthly_results, c("specification_id", setdiff(names(monthly_results), "specification_id")))
fwrite(monthly_results, file.path(table_dir, "REGISTRY_MONTHLY_REGISTRATION_ROBUSTNESS.csv"))

brazil_monthly <- rbindlist(lapply(c("combined", "female", "male"), function(s) {
  fit_monthly(s, 17:19, TRUE, "Brazil")
}), use.names = TRUE)
fwrite(brazil_monthly, file.path(table_dir, "REGISTRY_MONTHLY_BRAZIL_SENSITIVITY.csv"))

# Aggregate monthly log-rate-gap HAC and pre-period forecast bootstrap.
source <- brazil_panel[sex == "combined" & age %in% c(15L, 17:19)]
focal <- source[age == 15L, .(
  year, month, period, trend_2019m02, post_april_2019,
  partial_march_2019, rate15 = formal_marriage_rate_100k
)]
control <- source[age %in% 17:19, .(
  control_count = sum(persons_married), control_population = sum(population)
), by = .(year, month, period)]
gap <- merge(focal, control, by = c("year", "month", "period"))
gap[, control_rate := 100000 * control_count / control_population]
if (any(gap$rate15 <= 0 | gap$control_rate <= 0)) stop("Monthly log gap has zero rate")
gap[, `:=`(
  log_rate_gap = log(rate15) - log(control_rate),
  month_factor = factor(month, levels = 1:12)
)]
setorder(gap, year, month)
short <- gap[year < 2019L | (year == 2019L & month != 3L)]
hac_model <- lm(log_rate_gap ~ post_april_2019 + trend_2019m02 + month_factor,
                data = short)
hac_ct <- coeftest(hac_model, vcov. = NeweyWest(hac_model, lag = 12L,
                                                prewhite = FALSE, adjust = TRUE))
hac_beta <- unname(hac_ct["post_april_2019", "Estimate"])
hac_se <- unname(hac_ct["post_april_2019", "Std. Error"])
hac <- data.table(
  estimate = hac_beta, std_error = hac_se, statistic = hac_beta / hac_se,
  p_value = 2 * pnorm(-abs(hac_beta / hac_se)),
  ci_lower = hac_beta - qnorm(0.975) * hac_se,
  ci_upper = hac_beta + qnorm(0.975) * hac_se,
  rate_ratio = exp(hac_beta), percent_change = 100 * (exp(hac_beta) - 1),
  hac_lag_months = 12L, periods = nrow(short),
  timing_semantics = "registration month"
)
fwrite(hac, file.path(table_dir, "REGISTRY_MONTHLY_AGGREGATED_HAC.csv"))

pre <- gap[year < 2019L | (year == 2019L & month <= 2L)]
forecast <- lm(log_rate_gap ~ trend_2019m02 + month_factor, data = pre)
gap[, counterfactual_gap := as.numeric(predict(forecast, newdata = gap))]
gap[, dynamic_log_effect := log_rate_gap - counterfactual_gap]
residual <- residuals(forecast) - mean(residuals(forecast))
circular_blocks <- function(values, target_n, block_length = 12L) {
  starts <- sample.int(length(values), ceiling(target_n / block_length), replace = TRUE)
  out <- unlist(lapply(starts, function(s) values[((s - 1L + 0:(block_length - 1L)) %% length(values)) + 1L]))
  out[seq_len(target_n)]
}
errors <- matrix(NA_real_, nrow = 999L, ncol = nrow(gap))
for (b in seq_len(999L)) {
  e <- circular_blocks(residual, nrow(gap), 12L)
  null_y <- gap$counterfactual_gap + e
  boot_pre <- copy(gap[year < 2019L | (year == 2019L & month <= 2L)])
  boot_pre[, null_y := null_y[seq_len(.N)]]
  boot_fit <- lm(null_y ~ trend_2019m02 + month_factor, data = boot_pre)
  errors[b, ] <- null_y - as.numeric(predict(boot_fit, newdata = gap))
}
post_idx <- which(gap$year == 2019L & gap$month %in% 4:12)
forecast_effect <- mean(gap$dynamic_log_effect[post_idx])
forecast_error <- rowMeans(errors[, post_idx, drop = FALSE])
forecast_ci <- forecast_effect - quantile(forecast_error, c(0.975, 0.025))
forecast_summary <- data.table(
  estimate = forecast_effect, std_error = sd(forecast_error),
  ci_lower = forecast_ci[1L], ci_upper = forecast_ci[2L],
  p_value = (1 + sum(abs(forecast_error) >= abs(forecast_effect))) / 1000,
  rate_ratio = exp(forecast_effect),
  percent_change = 100 * (exp(forecast_effect) - 1),
  pre_periods = nrow(pre), post_periods = length(post_idx),
  block_length_months = 12L, replications = 999L,
  timing_semantics = "registration month"
)
fwrite(forecast_summary, file.path(table_dir, "REGISTRY_MONTHLY_FORECAST_SUMMARY.csv"))
fwrite(gap, file.path(table_dir, "REGISTRY_MONTHLY_RAW_GAP.csv"))

primary <- monthly_results[
  sex == "combined" & controls == "17-18-19" & age_specific_trends == TRUE
]
tests <- rbindlist(list(
  data.table(test = "monthly panel complete", passed = nrow(region_panel) == 10800L, observed = as.character(nrow(region_panel))),
  data.table(test = "March 2019 omitted from all fitted samples", passed = all(monthly_results$omitted == "2019M03"), observed = paste(unique(monthly_results$omitted), collapse = ",")),
  data.table(test = "post begins April 2019", passed = all(monthly_results$post == "2019M04-2019M12"), observed = paste(unique(monthly_results$post), collapse = ",")),
  data.table(test = "18 locked monthly region models", passed = nrow(monthly_results) == 18L, observed = as.character(nrow(monthly_results))),
  data.table(test = "primary monthly coefficient finite", passed = nrow(primary) == 1L & is.finite(primary$estimate), observed = as.character(primary$estimate)),
  data.table(test = "monthly region counts reproduce source", passed = sum(region_panel$persons_married) == sum(registry$persons_married), observed = as.character(sum(region_panel$persons_married) - sum(registry$persons_married))),
  data.table(test = "registration timing explicitly labeled", passed = all(grepl("registration", monthly_results$timing_semantics)), observed = "registration month"),
  data.table(test = "999 annual-block bootstrap replications", passed = nrow(errors) == 999L, observed = as.character(nrow(errors)))
), use.names = TRUE)
fwrite(tests, file.path(audit_dir, "REGISTRY_MONTHLY_ACCEPTANCE_TESTS.csv"))
if (!all(tests$passed)) {
  print(tests[passed == FALSE])
  stop("Monthly Registry acceptance test failed")
}

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("monthly_region_models=%d", nrow(monthly_results)),
  sprintf("primary_beta=%.12f", primary$estimate),
  sprintf("primary_percent_change=%.8f", primary$percent_change),
  sprintf("hac_beta=%.12f", hac_beta),
  sprintf("forecast_beta=%.12f", forecast_effect),
  sprintf("bootstrap_replications=%d", nrow(errors)),
  sprintf("tests_passed=%d", sum(tests$passed)),
  sprintf("tests_total=%d", nrow(tests)),
  "timing=registration_month_not_occurrence",
  "gate=D_registry_monthly"
)
writeLines(log_lines, file.path(log_dir, "17_analyze_registry_monthly.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
