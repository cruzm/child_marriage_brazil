#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(digest)
  library(ggplot2)
  library(yaml)
})

started <- Sys.time()
cwd <- normalizePath(getwd(), mustWork = TRUE)
root <- if (file.exists(file.path(cwd, "config", "registry_trend_sensitivity_lock.yml"))) {
  cwd
} else if (file.exists(file.path(cwd, "Darcio", "config", "registry_trend_sensitivity_lock.yml"))) {
  file.path(cwd, "Darcio")
} else {
  stop("Run from the Darcio directory or its parent")
}

data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
figure_dir <- file.path(root, "outputs", "figures")
audit_dir <- file.path(root, "outputs", "audit")
analysis_dir <- file.path(root, "outputs", "analysis")
log_dir <- file.path(root, "outputs", "logs")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(analysis_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

lock_path <- file.path(root, "config", "registry_trend_sensitivity_lock.yml")
protocol_path <- file.path(analysis_dir, "REGISTRY_TREND_SENSITIVITY_PROTOCOL.md")
hash_path <- file.path(analysis_dir, "REGISTRY_TREND_SENSITIVITY_LOCK_SHA256.txt")
lock <- read_yaml(lock_path)

hash_lines <- readLines(hash_path, warn = FALSE)
expected_lock_hash <- sub(" .*", "", grep("registry_trend_sensitivity_lock.yml", hash_lines, value = TRUE))
expected_protocol_hash <- sub(" .*", "", grep("REGISTRY_TREND_SENSITIVITY_PROTOCOL.md", hash_lines, value = TRUE))
actual_lock_hash <- digest(lock_path, algo = "sha256", file = TRUE)
actual_protocol_hash <- digest(protocol_path, algo = "sha256", file = TRUE)
if (!identical(actual_lock_hash, expected_lock_hash)) stop("Trend-sensitivity YAML lock hash mismatch")
if (!identical(actual_protocol_hash, expected_protocol_hash)) stop("Trend-sensitivity prose protocol hash mismatch")
if (!isTRUE(lock$extension$post_result_protocol)) stop("Protocol must be labeled post-result")
if (!isTRUE(lock$extension$frozen_before_extension_estimation)) stop("Protocol was not frozen before extension estimation")

candidate_ids <- c(
  "seasonal_level", "global_linear", "global_quadratic",
  "local_linear_12", "local_linear_16"
)
locked_candidate_ids <- vapply(lock$candidate_models, `[[`, character(1L), "id")
if (!identical(candidate_ids, locked_candidate_ids)) stop("Candidate models differ from frozen order")

panel <- fread(file.path(data_dir, "REGISTRY_QUARTERLY_PANEL_BRAZIL.csv"))
panel[, `:=`(
  year = as.integer(year), quarter = as.integer(quarter), age = as.integer(age),
  period_index = as.integer(period_index), period = as.character(period)
)]
source <- panel[sex == "combined" & age %in% c(15L, 17:19)]
age15 <- source[age == 15L, .(
  year, quarter, period, period_index,
  rate15 = formal_marriage_rate_100k,
  count15 = persons_married,
  population15 = population
)]
controls <- source[age %in% 17:19, .(
  control_count = sum(persons_married),
  control_population = sum(population)
), by = .(year, quarter, period, period_index)]
gap <- merge(age15, controls, by = c("year", "quarter", "period", "period_index"))
setorder(gap, period_index)
gap[, control_rate := 100000 * control_count / control_population]
if (any(!is.finite(gap$rate15) | !is.finite(gap$control_rate) |
        gap$rate15 <= 0 | gap$control_rate <= 0)) {
  stop("Nonpositive or invalid rate; frozen zero rule forbids correction")
}
gap[, `:=`(
  log_rate_gap = log(rate15) - log(control_rate),
  quarter_factor = factor(quarter, levels = 1:4),
  date = as.Date(sprintf("%d-%02d-15", year, (quarter - 1L) * 3L + 2L))
)]

pre <- copy(gap[year <= 2018L])
partial <- copy(gap[year == 2019L & quarter == 1L])
target <- copy(gap[year == 2019L & quarter %in% 2:4])

model_formula <- function(model_id, outcome = "log_rate_gap") {
  rhs <- switch(model_id,
    seasonal_level = "quarter_factor",
    global_linear = "period_index + quarter_factor",
    global_quadratic = "period_index + I(period_index^2) + quarter_factor",
    local_linear_12 = "period_index + quarter_factor",
    local_linear_16 = "period_index + quarter_factor",
    stop("Unknown model: ", model_id)
  )
  as.formula(paste(outcome, "~", rhs))
}

select_training <- function(d, model_id) {
  n_local <- if (model_id == "local_linear_12") {
    12L
  } else if (model_id == "local_linear_16") {
    16L
  } else {
    NA_integer_
  }
  out <- copy(d)
  if (!is.na(n_local)) {
    if (nrow(out) < n_local) stop("Insufficient local training observations for ", model_id)
    out <- tail(out, n_local)
  }
  out
}

fit_candidate <- function(model_id, available, outcome = "log_rate_gap") {
  training <- select_training(available, model_id)
  fit <- lm(model_formula(model_id, outcome), data = training)
  if (fit$rank < length(coef(fit)) || anyNA(coef(fit))) stop("Rank-deficient fit: ", model_id)
  list(fit = fit, training = training)
}

window_starts <- unlist(lock$windows$rolling_origin$common_window_starts, use.names = FALSE)
placebo_rows <- vector("list", length(candidate_ids) * length(window_starts))
row_id <- 0L
for (model_id in candidate_ids) {
  for (window_start in window_starts) {
    start_index <- pre[period == window_start, period_index]
    if (length(start_index) != 1L) stop("Missing frozen placebo start: ", window_start)
    holdout <- pre[period_index >= start_index & period_index <= start_index + 2L]
    available <- pre[period_index < start_index]
    fitted <- fit_candidate(model_id, available)
    prediction <- as.numeric(predict(fitted$fit, newdata = holdout))
    if (length(prediction) != 3L || any(!is.finite(prediction))) stop("Invalid rolling forecast")
    errors <- holdout$log_rate_gap - prediction
    row_id <- row_id + 1L
    placebo_rows[[row_id]] <- data.table(
      model_id = model_id,
      window_start = window_start,
      window_end = holdout$period[nrow(holdout)],
      training_start = fitted$training$period[1L],
      training_end = fitted$training$period[nrow(fitted$training)],
      training_periods = nrow(fitted$training),
      forecast_periods = nrow(holdout),
      mean_actual_gap = mean(holdout$log_rate_gap),
      mean_forecast_gap = mean(prediction),
      window_log_error = mean(errors),
      window_percent_error = 100 * (exp(mean(errors)) - 1),
      point_rmse = sqrt(mean(errors^2)),
      information_leak = max(fitted$training$period_index) >= min(holdout$period_index)
    )
  }
}
placebos <- rbindlist(placebo_rows)
if (nrow(placebos) != length(candidate_ids) * length(window_starts)) {
  stop("Rolling-origin implementation did not produce the frozen model-window grid")
}

strong_mean <- as.numeric(lock$calibration_tiers$strong$absolute_mean_error_max)
strong_max <- as.numeric(lock$calibration_tiers$strong$maximum_absolute_window_error_max)
strong_windows_required <- as.integer(lock$calibration_tiers$strong$windows_required_within_1_15)
qualified_mean <- as.numeric(lock$calibration_tiers$qualified$absolute_mean_error_max)
qualified_max <- as.numeric(lock$calibration_tiers$qualified$maximum_absolute_window_error_max)
qualified_window <- as.numeric(lock$calibration_tiers$qualified$window_absolute_error_threshold)
qualified_windows_required <- as.integer(lock$calibration_tiers$qualified$windows_required_within_1_20)

metrics <- placebos[, .(
  rolling_window_rmse = sqrt(mean(window_log_error^2)),
  rolling_window_mae = mean(abs(window_log_error)),
  rolling_window_mean_error = mean(window_log_error),
  rolling_window_max_abs_error = max(abs(window_log_error)),
  windows_within_1_15 = sum(abs(window_log_error) <= strong_max + 1e-12),
  windows_within_1_20 = sum(abs(window_log_error) <= qualified_window + 1e-12),
  placebo_windows = .N
), by = model_id]
metrics[, calibration_tier := fifelse(
  abs(rolling_window_mean_error) <= strong_mean + 1e-12 &
    rolling_window_max_abs_error <= strong_max + 1e-12 &
    windows_within_1_15 >= strong_windows_required,
  "strong",
  fifelse(
    abs(rolling_window_mean_error) <= qualified_mean + 1e-12 &
      rolling_window_max_abs_error <= qualified_max + 1e-12 &
      windows_within_1_20 >= qualified_windows_required,
    "qualified", "fail"
  )
)]
metrics[, tier_order := fcase(calibration_tier == "strong", 1L,
                              calibration_tier == "qualified", 2L,
                              default = 3L)]
setorder(metrics, rolling_window_rmse, model_id)
metrics[, rolling_rank := seq_len(.N)]

circular_blocks <- function(values, target_n, block_length) {
  starts <- sample.int(length(values), ceiling(target_n / block_length), replace = TRUE)
  out <- unlist(lapply(starts, function(s) {
    values[((s - 1L + 0:(block_length - 1L)) %% length(values)) + 1L]
  }), use.names = FALSE)
  out[seq_len(target_n)]
}

bootstrap_replications <- as.integer(lock$bootstrap$replications)
block_length <- as.integer(lock$bootstrap$block_length_quarters)
set.seed(as.integer(lock$bootstrap$random_seed))
model_results <- vector("list", length(candidate_ids))
bootstrap_errors <- vector("list", length(candidate_ids))

for (m in seq_along(candidate_ids)) {
  model_id <- candidate_ids[m]
  fitted <- fit_candidate(model_id, pre)
  prediction <- as.numeric(predict(fitted$fit, newdata = target))
  observed_effect <- mean(target$log_rate_gap - prediction)
  residual_pool <- residuals(fitted$fit)
  residual_pool <- residual_pool - mean(residual_pool)
  train_fitted <- as.numeric(predict(fitted$fit, newdata = fitted$training))
  target_counterfactual <- prediction
  n_train <- nrow(fitted$training)
  n_target <- nrow(target)
  draw_error <- numeric(bootstrap_replications)
  for (b in seq_len(bootstrap_replications)) {
    e <- circular_blocks(residual_pool, n_train + n_target, block_length)
    boot_train <- copy(fitted$training)
    boot_train[, boot_y := train_fitted + e[seq_len(n_train)]]
    boot_fit <- lm(model_formula(model_id, "boot_y"), data = boot_train)
    boot_prediction <- as.numeric(predict(boot_fit, newdata = target))
    null_target <- target_counterfactual + e[n_train + seq_len(n_target)]
    draw_error[b] <- mean(null_target - boot_prediction)
  }
  if (any(!is.finite(draw_error))) stop("Nonfinite bootstrap draw: ", model_id)
  q <- quantile(draw_error, c(0.975, 0.025), names = FALSE)
  ci_lower <- observed_effect - q[1L]
  ci_upper <- observed_effect - q[2L]
  p_value <- (1 + sum(abs(draw_error) >= abs(observed_effect))) /
    (1 + bootstrap_replications)
  model_results[[m]] <- data.table(
    model_id = model_id,
    target_training_start = fitted$training$period[1L],
    target_training_end = fitted$training$period[nrow(fitted$training)],
    target_training_periods = n_train,
    target_log_effect = observed_effect,
    target_percent_change = 100 * (exp(observed_effect) - 1),
    bootstrap_se = sd(draw_error),
    ci_lower_log = ci_lower,
    ci_upper_log = ci_upper,
    ci_lower_percent = 100 * (exp(ci_lower) - 1),
    ci_upper_percent = 100 * (exp(ci_upper) - 1),
    p_value = p_value,
    bootstrap_replications = bootstrap_replications,
    block_length = block_length
  )
  bootstrap_errors[[m]] <- data.table(
    model_id = model_id,
    draw = seq_len(bootstrap_replications),
    mean_forecast_error = draw_error
  )
}

models <- merge(metrics, rbindlist(model_results), by = "model_id", sort = FALSE)
if (nrow(models) != length(candidate_ids)) stop("Target implementation did not produce five model rows")
models[, inverse_mse_weight_raw := 1 / pmax(rolling_window_rmse^2, 1e-12)]
models[, ensemble_weight := inverse_mse_weight_raw / sum(inverse_mse_weight_raw)]
setorder(models, tier_order, rolling_window_rmse, model_id)

best_tier <- min(models$tier_order)
selected <- models[tier_order == best_tier][order(rolling_window_rmse, model_id)][1L]
gate_status <- switch(as.character(best_tier),
  `1` = "strong",
  `2` = "qualified_with_reservations",
  `3` = "failed"
)
ensemble_log_effect <- sum(models$ensemble_weight * models$target_log_effect)
calibrated <- models[calibration_tier %in% c("strong", "qualified")]

summary <- data.table(
  protocol_status = "post-result sensitivity; original lock unchanged",
  gate_status = gate_status,
  selected_model = selected$model_id,
  selected_calibration_tier = selected$calibration_tier,
  selected_rolling_rmse = selected$rolling_window_rmse,
  selected_log_effect = selected$target_log_effect,
  selected_percent_change = selected$target_percent_change,
  selected_ci_lower_percent = selected$ci_lower_percent,
  selected_ci_upper_percent = selected$ci_upper_percent,
  selected_p_value = selected$p_value,
  ensemble_log_effect = ensemble_log_effect,
  ensemble_percent_change = 100 * (exp(ensemble_log_effect) - 1),
  all_model_log_lower = min(models$target_log_effect),
  all_model_log_upper = max(models$target_log_effect),
  all_model_percent_lower = min(models$target_percent_change),
  all_model_percent_upper = max(models$target_percent_change),
  calibrated_models = nrow(calibrated),
  calibrated_model_log_lower = if (nrow(calibrated)) min(calibrated$target_log_effect) else NA_real_,
  calibrated_model_log_upper = if (nrow(calibrated)) max(calibrated$target_log_effect) else NA_real_,
  calibrated_model_percent_lower = if (nrow(calibrated)) min(calibrated$target_percent_change) else NA_real_,
  calibrated_model_percent_upper = if (nrow(calibrated)) max(calibrated$target_percent_change) else NA_real_,
  causal_status = "specification envelope; not a confidence set, identified set, or causal bound"
)

fwrite(models, file.path(table_dir, "REGISTRY_TREND_SENSITIVITY_MODELS.csv"))
fwrite(placebos, file.path(table_dir, "REGISTRY_TREND_SENSITIVITY_PLACEBOS.csv"))
fwrite(summary, file.path(table_dir, "REGISTRY_TREND_SENSITIVITY_SUMMARY.csv"))
fwrite(rbindlist(bootstrap_errors), file.path(audit_dir, "REGISTRY_TREND_SENSITIVITY_BOOTSTRAP_DRAWS.csv"))

display_names <- c(
  global_linear = "Global linear",
  local_linear_12 = "Local linear (12 quarters)",
  local_linear_16 = "Local linear (16 quarters)",
  global_quadratic = "Global quadratic",
  seasonal_level = "Seasonal level"
)
table_models <- models[order(rolling_rank)]
table_rows <- vapply(seq_len(nrow(table_models)), function(i) {
  x <- table_models[i]
  sprintf(
    "%s & %.3f & %s & %+.1f [%+.1f, %+.1f] & %.3f \\\\",
    display_names[[x$model_id]], x$rolling_window_rmse, x$calibration_tier,
    x$target_percent_change, x$ci_lower_percent, x$ci_upper_percent, x$p_value
  )
}, character(1L))
table_lines <- c(
  "\\begin{table}[!htbp]",
  "\\centering",
  "\\caption{Post-result rolling-origin sensitivity to the counterfactual trend.}",
  "\\label{tab:trend_sensitivity}",
  "\\begingroup\\footnotesize",
  "\\begin{tabular}{@{}lccrc@{}}",
  "\\toprule",
  "Model & Pre-window RMSE & Tier & Target change [95\\% interval] & $p$ \\\\",
  "\\midrule",
  table_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\par\\smallskip",
  "\\begin{minipage}{0.96\\linewidth}\\footnotesize",
  "\\emph{Notes:} The target is the mean actual-minus-forecast national log-rate gap in 2019Q2--Q4, transformed to percent. RMSE uses six frozen three-quarter rolling windows before 2019. All candidates fail the frozen qualified tier. Intervals use 1,999 four-quarter moving-block bootstrap draws and are model-specific forecast intervals. This post-result exercise does not produce a causal bound.",
  "\\end{minipage}",
  "\\endgroup",
  "\\end{table}"
)
writeLines(table_lines, file.path(table_dir, "TABLE_13_TREND_SENSITIVITY.tex"))

plot_placebos <- placebos[, .(
  model_id,
  label = window_start,
  order = match(window_start, window_starts),
  log_error = window_log_error,
  series = "Pre-2019 rolling placebo"
)]
plot_target <- models[, .(
  model_id,
  label = "2019Q2--Q4",
  order = length(window_starts) + 1L,
  log_error = target_log_effect,
  series = "Target"
)]
plot_data <- rbind(plot_placebos, plot_target)
plot_data[, label := factor(label, levels = c(window_starts, "2019Q2--Q4"))]
p <- ggplot(plot_data, aes(label, log_error, group = 1L)) +
  annotate("rect", xmin = -Inf, xmax = Inf,
           ymin = -qualified_window, ymax = qualified_window,
           fill = "grey85", alpha = 0.55) +
  geom_hline(yintercept = 0, linewidth = 0.35, colour = "grey25") +
  geom_line(data = plot_data[series == "Pre-2019 rolling placebo"],
            colour = "#2166AC", linewidth = 0.45) +
  geom_point(aes(shape = series, colour = series), size = 2.0) +
  facet_wrap(~model_id, ncol = 2L) +
  scale_colour_manual(values = c("Pre-2019 rolling placebo" = "#2166AC", "Target" = "#B2182B")) +
  scale_shape_manual(values = c("Pre-2019 rolling placebo" = 16L, "Target" = 17L)) +
  labs(
    title = "Pre-period forecast performance and the 2019 target deviation",
    subtitle = "Three-quarter mean errors; grey band is the frozen +/-log(1.20) qualified-window threshold",
    x = "Forecast-window start", y = "Actual minus forecast log-rate gap",
    colour = NULL, shape = NULL,
    caption = "Post-result sensitivity protocol v1.0.0. The target points are not placebo observations."
  ) +
  theme_minimal(base_size = 10) +
  theme(
    panel.grid.minor = element_blank(), legend.position = "bottom",
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_text(face = "bold")
  )
ggsave(file.path(figure_dir, "FIGURE_13_REGISTRY_TREND_SENSITIVITY.pdf"), p,
       width = 9, height = 7, device = cairo_pdf)
ggsave(file.path(figure_dir, "FIGURE_13_REGISTRY_TREND_SENSITIVITY.png"), p,
       width = 9, height = 7, dpi = 300, bg = "white")

fmt <- function(x, digits = 3L) formatC(x, format = "f", digits = digits)
fmt_signed <- function(x, digits = 1L) sprintf(paste0("%+.", digits, "f"), x)
model_lines <- unlist(lapply(seq_len(nrow(models)), function(i) {
  x <- models[i]
  sprintf(
    "- `%s`: pre-window RMSE %.3f; tier **%s**; target %s%% (95%% forecast interval [%s%%, %s%%], p=%s); ensemble weight %.3f.",
    x$model_id, x$rolling_window_rmse, x$calibration_tier,
    fmt_signed(x$target_percent_change), fmt_signed(x$ci_lower_percent),
    fmt_signed(x$ci_upper_percent), fmt(x$p_value), x$ensemble_weight
  )
}))
calibrated_line <- if (nrow(calibrated)) {
  sprintf(
    "The calibrated-model point envelope is [%s%%, %s%%].",
    fmt_signed(summary$calibrated_model_percent_lower),
    fmt_signed(summary$calibrated_model_percent_upper)
  )
} else {
  "No candidate passes the qualified calibration tier, so no calibrated-model envelope is reported."
}
report_lines <- c(
  "# Registry trend sensitivity — results",
  "",
  sprintf("**Run:** %s  ", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "**Protocol:** frozen post-result protocol v1.0.0; original specification lock unchanged.  ",
  sprintf("**Gate:** `%s`.", gate_status),
  "",
  "## Main result",
  "",
  sprintf(
    "The frozen selection rule chooses `%s` (%s). Its 2019Q2--Q4 forecast deviation is %s%% (95%% model-specific forecast interval [%s%%, %s%%], p=%s).",
    selected$model_id, selected$calibration_tier,
    fmt_signed(selected$target_percent_change), fmt_signed(selected$ci_lower_percent),
    fmt_signed(selected$ci_upper_percent), fmt(selected$p_value)
  ),
  sprintf(
    "The fixed pre-period-weighted ensemble gives %s%%. The all-model point envelope is [%s%%, %s%%]. %s",
    fmt_signed(summary$ensemble_percent_change),
    fmt_signed(summary$all_model_percent_lower), fmt_signed(summary$all_model_percent_upper),
    calibrated_line
  ),
  "",
  "This is a specification envelope, not a confidence set, identified set, or causal bound. Rolling-origin performance can expose poor extrapolation; it cannot prove the untreated 2019 path.",
  "",
  "## Candidate models",
  "",
  model_lines,
  "",
  "## Binding interpretation",
  "",
  "- The locked regional PPML remains the primary estimate.",
  "- The extension was designed after the original outcomes and diagnostics were known.",
  "- Model selection and ensemble weights use only pre-2019 rolling forecasts.",
  "- Every candidate and every common placebo window is retained in the exported CSVs.",
  "- Model-specific bootstrap intervals describe forecast uncertainty under each functional form; they do not solve the single-national-event identification problem.",
  ""
)
writeLines(report_lines, file.path(analysis_dir, "REGISTRY_TREND_SENSITIVITY_RESULTS.md"))

tests <- rbindlist(list(
  data.table(test = "YAML lock hash matches", passed = identical(actual_lock_hash, expected_lock_hash), observed = actual_lock_hash),
  data.table(test = "prose protocol hash matches", passed = identical(actual_protocol_hash, expected_protocol_hash), observed = actual_protocol_hash),
  data.table(test = "protocol labeled post-result", passed = isTRUE(lock$extension$post_result_protocol), observed = as.character(lock$extension$post_result_protocol)),
  data.table(test = "24 pre quarters", passed = nrow(pre) == 24L, observed = as.character(nrow(pre))),
  data.table(test = "one omitted partial quarter", passed = nrow(partial) == 1L && partial$period == "2019Q1", observed = paste(partial$period, collapse = ",")),
  data.table(test = "three target quarters", passed = nrow(target) == 3L && identical(target$period, c("2019Q2", "2019Q3", "2019Q4")), observed = paste(target$period, collapse = ",")),
  data.table(test = "five frozen candidate models", passed = setequal(models$model_id, candidate_ids) && nrow(models) == 5L, observed = paste(models$model_id, collapse = ",")),
  data.table(test = "six windows per model", passed = all(placebos[, .N, by = model_id]$N == 6L), observed = paste(placebos[, .N, by = model_id]$N, collapse = ",")),
  data.table(test = "no rolling information leakage", passed = !any(placebos$information_leak), observed = as.character(sum(placebos$information_leak))),
  data.table(test = "all forecasts finite", passed = all(is.finite(placebos$window_log_error)) && all(is.finite(models$target_log_effect)), observed = as.character(all(is.finite(placebos$window_log_error)) && all(is.finite(models$target_log_effect)))),
  data.table(test = "1999 bootstrap draws per model", passed = all(models$bootstrap_replications == 1999L) && nrow(rbindlist(bootstrap_errors)) == 5L * 1999L, observed = paste(models$bootstrap_replications, collapse = ",")),
  data.table(test = "ensemble weights positive and sum to one", passed = all(models$ensemble_weight > 0) && abs(sum(models$ensemble_weight) - 1) < 1e-12, observed = sprintf("%.15f", sum(models$ensemble_weight))),
  data.table(test = "results label envelope noncausal", passed = grepl("not a confidence set, identified set, or causal bound", paste(report_lines, collapse = " "), fixed = TRUE), observed = summary$causal_status)
), use.names = TRUE, fill = TRUE)
fwrite(tests, file.path(audit_dir, "REGISTRY_TREND_SENSITIVITY_ACCEPTANCE_TESTS.csv"))
if (!all(tests$passed)) stop("Registry trend-sensitivity acceptance test failed")

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("protocol_yaml_sha256=%s", actual_lock_hash),
  sprintf("protocol_md_sha256=%s", actual_protocol_hash),
  sprintf("gate_status=%s", gate_status),
  sprintf("selected_model=%s", selected$model_id),
  sprintf("selected_percent_change=%.12f", selected$target_percent_change),
  sprintf("ensemble_percent_change=%.12f", summary$ensemble_percent_change),
  sprintf("all_model_envelope_percent=[%.12f,%.12f]", summary$all_model_percent_lower, summary$all_model_percent_upper),
  sprintf("tests_passed=%d", sum(tests$passed)),
  sprintf("tests_total=%d", nrow(tests)),
  "status=complete"
)
writeLines(log_lines, file.path(log_dir, "24_analyze_registry_trend_sensitivity.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
