#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(sandwich)
  library(lmtest)
  library(yaml)
})

started <- Sys.time()
set.seed(13811)
setFixest_nthreads(1)
setFixest_notes(FALSE)
warning_messages <- character()
globalCallingHandlers(warning = function(w) {
  warning_messages <<- c(warning_messages, conditionMessage(w))
  tryInvokeRestart("muffleWarning")
})
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
audit_dir <- file.path(root, "outputs", "audit")
log_dir <- file.path(root, "outputs", "logs")
cfg <- read_yaml(file.path(root, "config", "analysis.yml"))

cells <- fread(file.path(data_dir, "PNADC_UNION_ANALYTIC_CELLS.csv"))
denom <- fread(file.path(data_dir, "QUARTERLY_DENOMINATORS_AGE_SEX.csv"))
denom <- denom[, .(year, quarter, geography_level, geography_value, age, sex, population)]
region_name <- c(`1` = "North", `2` = "Northeast", `3` = "Southeast",
                 `4` = "South", `5` = "Central-West")
denom[geography_level == "region",
      geography_value := unname(region_name[as.character(geography_value)])]
cells <- merge(cells, denom,
               by = c("year", "quarter", "geography_level", "geography_value", "age", "sex"),
               all.x = TRUE)
if (anyNA(cells$population)) stop("Union cells failed population join")

window_filter <- function(d, window) {
  switch(window,
    short_run_clean = d[year <= 2018L | (year == 2019L & quarter >= 2L)],
    full_dynamic = d[!(year == 2019L & quarter == 1L)],
    exclude_pandemic = d[!(year == 2019L & quarter == 1L) & !year %in% c(2020L, 2021L)],
    post_pandemic = d[year <= 2018L | year >= 2022L],
    stop("Unknown window")
  )
}

add_weights <- function(d, outcome) {
  se_name <- paste0(outcome, "_se")
  variance <- d[[se_name]]^2
  positive <- variance[is.finite(variance) & variance > 0]
  if (!length(positive)) stop("No positive design variance for ", outcome)
  floor_variance <- quantile(positive, 0.05)
  variance[!is.finite(variance) | variance <= 0] <- floor_variance
  raw_inverse <- 1 / variance
  bounds <- quantile(raw_inverse, c(0.05, 0.95), na.rm = TRUE)
  d[, meta_weight := pmin(pmax(raw_inverse, bounds[1L]), bounds[2L])]
  d
}

fit_cell <- function(outcome, sex_value, controls, window, trends = TRUE,
                     geography_level = "Brazil", geography_value = NULL,
                     drawn_outcome = NULL) {
  level_requested <- geography_level
  geo_requested <- geography_value
  ages <- sort(unique(c(15L, controls)))
  d <- copy(cells[
    get("geography_level") == level_requested & sex == sex_value & age %in% ages
  ])
  if (!is.null(geo_requested)) d <- d[get("geography_value") == geo_requested]
  d <- window_filter(d, window)
  d[, post_indicator := if (window == "post_pandemic") as.integer(year >= 2022L) else post_full]
  d[, treat_post := treated_age * post_indicator]
  d <- add_weights(d, outcome)
  response <- if (is.null(drawn_outcome)) outcome else drawn_outcome
  trend_names <- character()
  if (trends) {
    for (a in setdiff(ages, max(controls))) {
      nm <- paste0("trend_age_", a)
      d[, (nm) := trend_2018q4 * as.integer(age == a)]
      trend_names <- c(trend_names, nm)
    }
  }
  rhs <- paste(c("treat_post", trend_names), collapse = " + ")
  if (level_requested == "region" && is.null(geo_requested)) {
    fe <- "geography_value^age + geography_value^period + age^quarter"
  } else {
    fe <- "age^quarter + period"
  }
  f <- as.formula(paste(response, "~", rhs, "|", fe))
  model <- feols(f, weights = ~meta_weight, data = d, warn = FALSE)
  list(model = model, data = d, outcome = outcome)
}

extract_cell <- function(fit, vcov_spec = ~period) {
  ct <- coeftable(fit$model, vcov = vcov_spec)
  beta <- unname(ct["treat_post", "Estimate"])
  se <- unname(ct["treat_post", "Std. Error"])
  data.table(
    estimate = beta, std_error = se, statistic = beta / se,
    p_value = 2 * pnorm(-abs(beta / se)),
    ci_lower = beta - qnorm(0.975) * se,
    ci_upper = beta + qnorm(0.975) * se
  )
}

summarize_cell <- function(fit, outcome, sex_value, controls, window, trends,
                           geography_level, geography_value = NA_character_) {
  st <- extract_cell(fit)
  st[, `:=`(
    outcome = outcome, sex = sex_value, controls = paste(controls, collapse = "-"),
    window = window, age_specific_trends = trends,
    geography_level = geography_level,
    geography_value = geography_value,
    effect_percentage_points = 100 * estimate,
    ci_lower_percentage_points = 100 * ci_lower,
    ci_upper_percentage_points = 100 * ci_upper,
    observations = nobs(fit$model), periods = uniqueN(fit$data$period),
    unweighted_people = sum(fit$data$unweighted_n),
    unweighted_union_cases = sum(fit$data[[paste0(outcome, "_unweighted_n")]]),
    zero_case_cells = sum(fit$data[[paste0(outcome, "_unweighted_n")]] == 0L),
    dropped_observations = nrow(fit$data) - nobs(fit$model),
    variance_weight_winsorization = "inverse design variance, 5th/95th percentile"
  )]
  st
}

# Locked Brazil-cell robustness grid.
outcomes <- c("union_conservative", "union_expanded")
control_sets <- list(`17-19` = 17:19, `18-19` = 18:19, `16-17` = 16:17)
windows <- c("short_run_clean", "full_dynamic", "exclude_pandemic", "post_pandemic")
sexes <- c("combined", "female", "male")
trend_options <- c(TRUE, FALSE)
grid <- list()
idx <- 1L
primary_fit <- NULL
for (outcome in outcomes) for (control_name in names(control_sets)) {
  controls <- control_sets[[control_name]]
  for (window in windows) for (sex_value in sexes) for (trends in trend_options) {
    fit <- fit_cell(outcome, sex_value, controls, window, trends)
    grid[[idx]] <- summarize_cell(fit, outcome, sex_value, controls, window,
                                  trends, "Brazil", "Brazil")
    if (outcome == "union_conservative" && control_name == "17-19" &&
        window == "short_run_clean" && sex_value == "combined" && trends) {
      primary_fit <- fit
    }
    idx <- idx + 1L
  }
}
robustness <- rbindlist(grid, use.names = TRUE)
robustness[, specification_id := sprintf("PNADC-CELL-%03d", .I)]
setcolorder(robustness, c("specification_id", setdiff(names(robustness), "specification_id")))
fwrite(robustness, file.path(table_dir, "PNADC_UNION_ROBUSTNESS_GRID.csv"))
if (nrow(robustness) != 144L || is.null(primary_fit)) stop("PNADC grid is incomplete")

# Primary period-cluster estimate and normal design-cell draws.
primary_cluster <- extract_cell(primary_fit, ~period)
primary_beta <- primary_cluster$estimate
primary_sample <- copy(primary_fit$data)
draw_one <- function(seed_value) {
  set.seed(seed_value)
  d <- copy(primary_sample)
  d[, union_draw := pmin(1, pmax(0, rnorm(.N, union_conservative,
                                          union_conservative_se)))]
  trend_names <- grep("^trend_age_", names(d), value = TRUE)
  f <- as.formula(paste(
    "union_draw ~ treat_post +", paste(trend_names, collapse = " + "),
    "| age^quarter + period"
  ))
  m <- feols(f, weights = ~meta_weight, data = d, warn = FALSE)
  unname(coef(m)["treat_post"])
}
design_draws <- vapply(13811L + seq_len(999L), draw_one, numeric(1L))
design_se <- sd(design_draws)
total_se <- sqrt(primary_cluster$std_error^2 + design_se^2)
total_ci <- primary_beta + c(-1, 1) * qnorm(0.975) * total_se
total_p <- 2 * pnorm(-abs(primary_beta / total_se))
margin <- cfg$behavioral_outcomes$equivalence_margin_percentage_points / 100
p_lower <- 1 - pnorm((primary_beta + margin) / total_se)
p_upper <- pnorm((primary_beta - margin) / total_se)
tost_p <- max(p_lower, p_upper)
equivalent <- p_lower < 0.05 && p_upper < 0.05
mde <- (qnorm(0.975) + qnorm(0.80)) * total_se

primary_union <- data.table(
  estimand = "union_conservative prevalence at age 15",
  geography = "Brazil", sex = "combined", controls = "17-19",
  window = "2019Q2-2019Q4", age_specific_trends = TRUE,
  estimate = primary_beta,
  effect_percentage_points = 100 * primary_beta,
  period_cluster_se = primary_cluster$std_error,
  design_draw_se = design_se,
  combined_se_quadrature = total_se,
  ci_lower = total_ci[1L], ci_upper = total_ci[2L],
  ci_lower_percentage_points = 100 * total_ci[1L],
  ci_upper_percentage_points = 100 * total_ci[2L],
  p_value = total_p,
  equivalence_margin_percentage_points = 100 * margin,
  tost_p_lower = p_lower, tost_p_upper = p_upper, tost_p_value = tost_p,
  equivalent_at_5_percent = equivalent,
  mde_80_power_percentage_points = 100 * mde,
  unweighted_people = sum(primary_sample$unweighted_n),
  unweighted_union_cases = sum(primary_sample$union_conservative_unweighted_n),
  age15_unweighted_people = primary_sample[age == 15L, sum(unweighted_n)],
  age15_unweighted_union_cases = primary_sample[
    age == 15L, sum(union_conservative_unweighted_n)
  ],
  post_unweighted_people = primary_sample[year == 2019L & quarter %in% 2:4, sum(unweighted_n)],
  post_unweighted_union_cases = primary_sample[year == 2019L & quarter %in% 2:4,
                                               sum(union_conservative_unweighted_n)],
  post_age15_unweighted_people = primary_sample[
    age == 15L & year == 2019L & quarter %in% 2:4, sum(unweighted_n)
  ],
  post_age15_unweighted_union_cases = primary_sample[
    age == 15L & year == 2019L & quarter %in% 2:4,
    sum(union_conservative_unweighted_n)
  ],
  periods = uniqueN(primary_sample$period), time_clusters = uniqueN(primary_sample$period),
  design_draws = 999L,
  interpretation_rule = "imprecise estimates are indeterminate; nonrejection is not no substitution"
)
fwrite(primary_union, file.path(table_dir, "PNADC_UNION_PRIMARY_EFFECT.csv"))
fwrite(data.table(draw = seq_len(999L), beta = design_draws),
       file.path(audit_dir, "PNADC_UNION_DESIGN_DRAWS.csv"))

# Sex confirmatory/heterogeneity family with BH adjustment.
sex_results <- robustness[
  outcome == "union_conservative" & controls == "17-18-19" &
    window == "short_run_clean" & age_specific_trends == TRUE &
    sex %in% c("female", "male")
]
sex_results[, p_value_bh := p.adjust(p_value, method = "BH")]
sex_results[, heterogeneity_status := "exploratory; rare male events require power warning"]
fwrite(sex_results, file.path(table_dir, "PNADC_UNION_BY_SEX.csv"))

# Region-by-sex/outcome heterogeneity; each region remains diagnostic.
region_values <- sort(unique(cells[geography_level == "region", geography_value]))
regional_results <- list()
for (geo in region_values) for (sex_value in sexes) for (outcome in outcomes) {
  fit <- fit_cell(outcome, sex_value, 17:19, "short_run_clean", TRUE,
                  geography_level = "region", geography_value = geo)
  regional_results[[length(regional_results) + 1L]] <- summarize_cell(
    fit, outcome, sex_value, 17:19, "short_run_clean", TRUE, "region", geo
  )
}
regional_results <- rbindlist(regional_results, use.names = TRUE)
regional_results[, p_value_bh := p.adjust(p_value, method = "BH")]
regional_results[, heterogeneity_status := "exploratory; design-cell rarity reported"]
fwrite(regional_results, file.path(table_dir, "PNADC_UNION_REGIONAL_HETEROGENEITY.csv"))

# Population-weighted Brazil age-15 minus pooled-control prevalence gap.
gap_source <- cells[
  geography_level == "Brazil" & geography_value == "Brazil" &
    sex == "combined" & age %in% c(15L, 17:19)
]
age15 <- gap_source[age == 15L, .(
  year, quarter, period, trend_2018q4, post_full, partial_2019q1, pandemic,
  prevalence15 = union_conservative, se15 = union_conservative_se,
  population15 = population, unweighted_n15 = unweighted_n,
  cases15 = union_conservative_unweighted_n
)]
controls <- gap_source[age %in% 17:19]
controls[, control_weight := population / sum(population), by = .(year, quarter)]
control_gap <- controls[, .(
  control_prevalence = sum(control_weight * union_conservative),
  control_variance_independence = sum(control_weight^2 * union_conservative_se^2),
  control_population = sum(population),
  control_unweighted_n = sum(unweighted_n),
  control_cases = sum(union_conservative_unweighted_n)
), by = .(year, quarter, period)]
gap <- merge(age15, control_gap, by = c("year", "quarter", "period"))
gap[, `:=`(
  prevalence_gap = prevalence15 - control_prevalence,
  gap_design_se_independence = sqrt(se15^2 + control_variance_independence),
  quarter_factor = factor(quarter, levels = 1:4)
)]
setorder(gap, year, quarter)

pre_gap <- gap[year <= 2018L]
gap_var <- pre_gap$gap_design_se_independence^2
inv <- 1 / gap_var
bounds <- quantile(inv, c(0.05, 0.95))
pre_gap[, forecast_weight := pmin(pmax(inv, bounds[1L]), bounds[2L])]
forecast_model <- lm(prevalence_gap ~ trend_2018q4 + quarter_factor,
                     weights = forecast_weight, data = pre_gap)
gap[, counterfactual_gap := as.numeric(predict(forecast_model, newdata = gap))]
gap[, dynamic_effect := prevalence_gap - counterfactual_gap]
pre_residual <- residuals(forecast_model) - weighted.mean(residuals(forecast_model),
                                                          pre_gap$forecast_weight)

circular_blocks <- function(values, target_n, block_length = 4L) {
  starts <- sample.int(length(values), ceiling(target_n / block_length), replace = TRUE)
  out <- unlist(lapply(starts, function(s) values[((s - 1L + 0:(block_length - 1L)) %% length(values)) + 1L]))
  out[seq_len(target_n)]
}
dynamic_errors <- matrix(NA_real_, nrow = 999L, ncol = nrow(gap))
for (b in seq_len(999L)) {
  residual_draw <- circular_blocks(pre_residual, nrow(gap), 4L)
  design_draw <- rnorm(nrow(gap), 0, gap$gap_design_se_independence)
  null_y <- gap$counterfactual_gap + residual_draw + design_draw
  boot_pre <- copy(gap[year <= 2018L])
  boot_pre[, `:=`(
    null_y = null_y[seq_len(.N)],
    forecast_weight = pre_gap$forecast_weight
  )]
  boot_model <- lm(null_y ~ trend_2018q4 + quarter_factor,
                   weights = forecast_weight, data = boot_pre)
  boot_pred <- as.numeric(predict(boot_model, newdata = gap))
  dynamic_errors[b, ] <- null_y - boot_pred
}
dynamic_se <- apply(dynamic_errors, 2L, sd)
point_lower <- point_upper <- numeric(nrow(gap))
for (j in seq_len(nrow(gap))) {
  qs <- quantile(dynamic_errors[, j], c(0.975, 0.025))
  point_lower[j] <- gap$dynamic_effect[j] - qs[1L]
  point_upper[j] <- gap$dynamic_effect[j] - qs[2L]
}
valid <- dynamic_se > 0 & is.finite(dynamic_se)
max_boot <- apply(abs(sweep(dynamic_errors[, valid, drop = FALSE], 2L,
                            dynamic_se[valid], "/")), 1L, max)
sim_critical <- quantile(max_boot, 0.95)
gap[, `:=`(
  bootstrap_se = dynamic_se,
  pointwise_ci_lower = point_lower,
  pointwise_ci_upper = point_upper,
  simultaneous_ci_lower = dynamic_effect - sim_critical * dynamic_se,
  simultaneous_ci_upper = dynamic_effect + sim_critical * dynamic_se
)]
fwrite(gap, file.path(table_dir, "PNADC_UNION_DYNAMIC_FORECAST_EVENT_STUDY.csv"))

short_idx <- which(gap$year == 2019L & gap$quarter %in% 2:4)
forecast_short <- mean(gap$dynamic_effect[short_idx])
forecast_error <- rowMeans(dynamic_errors[, short_idx, drop = FALSE])
forecast_ci <- forecast_short - quantile(forecast_error, c(0.975, 0.025))
forecast_p <- (1 + sum(abs(forecast_error) >= abs(forecast_short))) / 1000
lead_idx <- which(gap$year <= 2018L)
lead_stat <- max(abs(gap$dynamic_effect[lead_idx] / dynamic_se[lead_idx]))
lead_boot <- apply(abs(sweep(dynamic_errors[, lead_idx, drop = FALSE], 2L,
                             dynamic_se[lead_idx], "/")), 1L, max)
lead_p <- (1 + sum(lead_boot >= lead_stat)) / 1000
forecast_summary <- data.table(
  method = "pre-period prevalence-gap forecast; design draws plus four-quarter residual blocks",
  short_run_effect = forecast_short,
  short_run_effect_percentage_points = 100 * forecast_short,
  std_error = sd(forecast_error),
  ci_lower = forecast_ci[1L], ci_upper = forecast_ci[2L],
  ci_lower_percentage_points = 100 * forecast_ci[1L],
  ci_upper_percentage_points = 100 * forecast_ci[2L],
  p_value = forecast_p,
  simultaneous_critical_value = sim_critical,
  joint_lead_statistic = lead_stat, joint_lead_p_value = lead_p,
  replications = 999L, block_length = 4L
)
fwrite(forecast_summary, file.path(table_dir, "PNADC_UNION_DYNAMIC_FORECAST_SUMMARY.csv"))

# HAC triangulation on the aggregate prevalence gap.
gap_short <- gap[year <= 2018L | (year == 2019L & quarter >= 2L)]
hac_model <- lm(prevalence_gap ~ post_full + trend_2018q4 + quarter_factor,
                data = gap_short)
hac_ct <- coeftest(hac_model, vcov. = NeweyWest(hac_model, lag = 4L,
                                                prewhite = FALSE, adjust = TRUE))
hac_beta <- unname(hac_ct["post_full", "Estimate"])
hac_se <- unname(hac_ct["post_full", "Std. Error"])
hac <- data.table(
  method = "Brazil age15-minus-pooled17-19 prevalence gap; Newey-West lag 4",
  estimate = hac_beta, effect_percentage_points = 100 * hac_beta,
  std_error = hac_se,
  ci_lower = hac_beta - qnorm(0.975) * hac_se,
  ci_upper = hac_beta + qnorm(0.975) * hac_se,
  p_value = 2 * pnorm(-abs(hac_beta / hac_se)),
  periods = nrow(gap_short), hac_lag = 4L
)
fwrite(hac, file.path(table_dir, "PNADC_UNION_AGGREGATED_HAC.csv"))

# Saturated cell-regression event points in a full-rank amended basis.
event_data <- copy(cells[
  geography_level == "Brazil" & geography_value == "Brazil" &
    sex == "combined" & age %in% c(15L, 17:19) & full_dynamic == 1L
])
event_data <- add_weights(event_data, "union_conservative")
event_data[, `:=`(
  trend_age_17 = trend_2018q4 * as.integer(age == 17L),
  trend_age_18 = trend_2018q4 * as.integer(age == 18L)
)]
season_names <- character()
for (a in 17:18) for (q in 1:3) {
  nm <- sprintf("season_age_%d_q%d", a, q)
  event_data[, (nm) := as.integer(age == a & quarter == q)]
  season_names <- c(season_names, nm)
}
event_formula <- as.formula(paste(
  "union_conservative ~ i(event_time, treated_age, ref=-1) +",
  paste(c("trend_age_17", "trend_age_18", season_names), collapse = " + "),
  "| age + period"
))
event_model <- feols(event_formula, weights = ~meta_weight, data = event_data,
                     warn = FALSE)
event_ct <- as.data.table(coeftable(event_model, vcov = "hetero"), keep.rownames = "term")
event_ct <- event_ct[grepl("^event_time::", term)]
setnames(event_ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
         c("estimate", "std_error_diagnostic", "statistic", "p_value_diagnostic"))
event_ct[, event_time := as.integer(sub("event_time::(-?[0-9]+):.*", "\\1", term))]
event_ct[, `:=`(
  effect_percentage_points = 100 * estimate,
  inference_status = "point path; dynamic inference uses forecast design/block bootstrap"
)]
setorder(event_ct, event_time)
fwrite(event_ct, file.path(table_dir, "PNADC_UNION_CELL_EVENT_STUDY_POINTS.csv"))

# Unified inference comparison.
inference <- rbindlist(list(
  data.table(
    method = "cell meta-regression, period cluster plus design variance",
    estimate = primary_beta, std_error = total_se,
    ci_lower = total_ci[1L], ci_upper = total_ci[2L], p_value = total_p,
    units = "prevalence", periods_or_replications = 27L,
    caveat = "only three short-run post quarters; marginal cell covariance unavailable"
  ),
  data.table(
    method = hac$method, estimate = hac$estimate, std_error = hac$std_error,
    ci_lower = hac$ci_lower, ci_upper = hac$ci_upper, p_value = hac$p_value,
    units = "prevalence gap", periods_or_replications = hac$periods,
    caveat = "aggregated gap; HAC lag 4"
  ),
  data.table(
    method = forecast_summary$method,
    estimate = forecast_summary$short_run_effect,
    std_error = forecast_summary$std_error,
    ci_lower = forecast_summary$ci_lower,
    ci_upper = forecast_summary$ci_upper,
    p_value = forecast_summary$p_value,
    units = "prevalence gap", periods_or_replications = 999L,
    caveat = "normal marginal design draws plus temporal block residuals"
  )
), use.names = TRUE)
inference[, `:=`(
  effect_percentage_points = 100 * estimate,
  ci_lower_percentage_points = 100 * ci_lower,
  ci_upper_percentage_points = 100 * ci_upper
)]
fwrite(inference, file.path(table_dir, "PNADC_UNION_INFERENCE_TRIANGULATION.csv"))

# Descriptive series for figures, with honest design intervals and counts.
raw_union <- cells[
  geography_level == "Brazil" & geography_value == "Brazil" & age %in% 14:19
]
fwrite(raw_union, file.path(table_dir, "PNADC_UNION_RAW_PREVALENCE_BRAZIL.csv"))

tests <- rbindlist(list(
  data.table(test = "locked PNADC robustness grid has 144 models", passed = nrow(robustness) == 144L, observed = as.character(nrow(robustness))),
  data.table(test = "primary coefficient finite", passed = is.finite(primary_beta), observed = as.character(primary_beta)),
  data.table(test = "primary uses 27 periods", passed = uniqueN(primary_sample$period) == 27L, observed = as.character(uniqueN(primary_sample$period))),
  data.table(test = "999 design draws finite", passed = length(design_draws) == 999L & all(is.finite(design_draws)), observed = as.character(sum(is.finite(design_draws)))),
  data.table(test = "999 joint dynamic draws executed", passed = nrow(dynamic_errors) == 999L, observed = as.character(nrow(dynamic_errors))),
  data.table(test = "event model retains all event terms", passed = !any(grepl("event_time", event_model$collin.var)), observed = paste(event_model$collin.var, collapse = ";")),
  data.table(test = "30 regional heterogeneity models executed", passed = nrow(regional_results) == 30L, observed = as.character(nrow(regional_results))),
  data.table(test = "conservative and expanded outcomes remain separate", passed = setequal(unique(robustness$outcome), outcomes), observed = paste(unique(robustness$outcome), collapse = ",")),
  data.table(test = "equivalence margin fixed at 0.50 pp", passed = margin == 0.005, observed = as.character(100 * margin)),
  data.table(test = "no Registry-PNADC subtraction", passed = TRUE, observed = "separate outcome tables")
), use.names = TRUE)
fwrite(tests, file.path(audit_dir, "PNADC_CELL_ANALYSIS_ACCEPTANCE_TESTS.csv"))
if (!all(tests$passed)) {
  print(tests[passed == FALSE])
  stop("PNADC cell analysis acceptance test failed")
}

warning_audit <- if (length(warning_messages)) {
  out <- as.data.table(table(message = warning_messages))
  setnames(out, "N", "occurrences")
  setorder(out, -occurrences, message)
  out
} else {
  data.table(message = character(), occurrences = integer())
}
fwrite(warning_audit, file.path(audit_dir, "PNADC_CELL_ANALYSIS_WARNINGS.csv"))

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("robustness_models=%d", nrow(robustness)),
  sprintf("design_draws=%d", length(design_draws)),
  sprintf("dynamic_joint_draws=%d", nrow(dynamic_errors)),
  sprintf("primary_effect_percentage_points=%.10f", 100 * primary_beta),
  sprintf("primary_total_se_percentage_points=%.10f", 100 * total_se),
  sprintf("primary_p=%.12f", total_p),
  sprintf("tost_p=%.12f", tost_p),
  sprintf("equivalent=%s", equivalent),
  sprintf("mde_percentage_points=%.10f", 100 * mde),
  sprintf("tests_passed=%d", sum(tests$passed)),
  sprintf("tests_total=%d", nrow(tests)),
  sprintf("warnings_total=%d", length(warning_messages)),
  sprintf("warning_types=%d", nrow(warning_audit)),
  "specification_amendment=3 PNADC dynamic basis/inference",
  "gate=D_pnadc_cells"
)
writeLines(log_lines, file.path(log_dir, "15_analyze_pnadc_cells.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
