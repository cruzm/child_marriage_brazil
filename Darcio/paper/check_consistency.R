#!/usr/bin/env Rscript

# Fail when the manuscript drifts from the canonical result CSVs. This check is
# intentionally narrow: it verifies headline numbers and stale post-Amendment-A1
# values, not every claim in the paper.

cwd <- normalizePath(getwd(), mustWork = TRUE)
root <- if (file.exists(file.path(cwd, "paper", "main.tex"))) {
  cwd
} else if (file.exists(file.path(cwd, "Darcio", "paper", "main.tex"))) {
  file.path(cwd, "Darcio")
} else {
  stop("Run from the Darcio directory or its parent")
}

read_one <- function(name) {
  path <- file.path(root, "outputs", "tables", name)
  if (!file.exists(path)) stop("Missing canonical table: ", path)
  read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
}

main_path <- file.path(root, "paper", "main.tex")
manuscript <- paste(readLines(main_path, warn = FALSE), collapse = "\n")

registry <- read_one("REGISTRY_PRIMARY_EFFECT.csv")[1, ]
trend <- read_one("REGISTRY_TREND_SPECIFICATION_DIVERGENCE.csv")[1, ]
union <- read_one("PNADC_UNION_PRIMARY_EFFECT.csv")[1, ]
status <- read_one("SINASC_STATUS_PRIMARY.csv")
status <- status[status$specification == "S1_married", ][1, ]
status_rob <- read_one("SINASC_STATUS_ROBUSTNESS.csv")
status_rob <- status_rob[status_rob$specification == "S1_no_trend", ][1, ]
fertility <- read_one("SINASC_FERTILITY_S4.csv")
fertility <- fertility[fertility$specification == "S4_fertility_age15", ][1, ]
placebos <- read_one("SINASC_PLACEBO_DATES.csv")
missingness <- read_one("SINASC_MISSINGNESS_DIAGNOSTIC.csv")[1, ]
trend_models <- read_one("REGISTRY_TREND_SENSITIVITY_MODELS.csv")
trend_summary <- read_one("REGISTRY_TREND_SENSITIVITY_SUMMARY.csv")[1, ]
trend_best <- trend_models[trend_models$model_id == "global_linear", ][1, ]
trend_seasonal <- trend_models[trend_models$model_id == "seasonal_level", ][1, ]
daily <- read_one("SINASC_DAILY_PRIMARY.csv")
daily_tau <- daily[daily$estimand == "TAU", ][1, ]
daily_delay <- daily[daily$estimand == "DELAY90", ][1, ]
daily_sensitivity <- read_one("SINASC_DAILY_SENSITIVITY.csv")
daily_placebos <- read_one("SINASC_DAILY_PLACEBOS.csv")
daily_temporal <- daily_placebos[daily_placebos$test_family == "temporal_placebo", ][1, ]

signed <- function(x, digits) sprintf(paste0("%+.", digits, "f"), x)
tex_pct <- function(x, digits = 1L) paste0("$", signed(x, digits), "\\%$")
tex_pct_interval <- function(lo, hi, digits = 1L) {
  paste0("$[", signed(lo, digits), "\\%, ", signed(hi, digits), "\\%]$")
}
tex_pp <- function(x, digits = 3L) paste0("$", signed(x, digits), "$")
tex_pp_interval <- function(lo, hi, digits = 3L) {
  paste0("$[", signed(lo, digits), ", ", signed(hi, digits), "]$")
}

expected <- c(
  registry_primary = tex_pct(registry$percent_change),
  registry_no_trend = tex_pct(trend$percent_change),
  registry_forecast_best = tex_pct(trend_best$target_percent_change),
  registry_forecast_ensemble = tex_pct(trend_summary$ensemble_percent_change),
  registry_forecast_envelope = tex_pct_interval(
    trend_summary$all_model_percent_lower, trend_summary$all_model_percent_upper
  ),
  registry_forecast_seasonal_interval = tex_pct_interval(
    trend_seasonal$ci_lower_percent, trend_seasonal$ci_upper_percent
  ),
  union_primary = paste0("$", signed(100 * union$estimate, 3L), "$"),
  sinasc_primary = tex_pct(status$pct_change),
  sinasc_no_trend = tex_pct(status_rob$pct_change),
  sinasc_fertility = tex_pct(fertility$pct_change),
  sinasc_fertility_p = sprintf("$p=%.3f$", fertility$p_value),
  sinasc_missing_p = sprintf("$p=%.3f$", missingness$p_value),
  placebo_2017 = tex_pct(placebos$pct_change[placebos$specification == "placebo_2017"]),
  placebo_2018 = tex_pct(placebos$pct_change[placebos$specification == "placebo_2018"]),
  daily_tau = tex_pp(daily_tau$estimate_pp),
  daily_tau_interval = tex_pp_interval(daily_tau$ci95_low_pp, daily_tau$ci95_high_pp),
  daily_mde = paste0("$", sprintf("%.3f", daily_tau$mde80_pp), "$"),
  daily_delay = tex_pp(daily_delay$estimate_pp),
  daily_delay_interval = tex_pp_interval(
    daily_delay$ci95_low_pp, daily_delay$ci95_high_pp
  ),
  daily_sensitivity_range = tex_pp_interval(
    min(daily_sensitivity$estimate_pp), max(daily_sensitivity$estimate_pp)
  ),
  daily_temporal = tex_pp(daily_temporal$estimate_pp),
  daily_temporal_interval = tex_pp_interval(
    daily_temporal$ci90_low_pp, daily_temporal$ci90_high_pp
  ),
  real_data_rule = "simulated observation enters the empirical evidence"
)

missing_expected <- names(expected)[!vapply(
  expected, function(x) grepl(x, manuscript, fixed = TRUE), logical(1L)
)]

stale <- c(
  "$+30.0\\%$", "$+17.8\\%$", "$+37.0\\%$", "$-23.6\\%$",
  "$+1.8\\%$", "$p=0.24$", "$p=0.58$"
)
present_stale <- stale[vapply(stale, function(x) grepl(x, manuscript, fixed = TRUE), logical(1L))]

forbidden_claims <- c(
  "ruled out not only by that model-conditional interval",
  "outside the all-model envelope",
  "every forecast-competitive model",
  "all estimates derive from a specification frozen before estimation",
  "pre-frozen forecast-validation"
)
present_forbidden <- forbidden_claims[vapply(
  forbidden_claims, function(x) grepl(x, manuscript, fixed = TRUE), logical(1L)
)]

forbidden_software_test_artifacts <- c(
  "REGISTRY_SAR_R0_SYNTHETIC",
  "REGISTRY_SAR_R0_SYNTHETIC_CELLS",
  "R0 synthetic recovery",
  "known IRR of 0.60"
)
present_software_test_artifacts <- forbidden_software_test_artifacts[vapply(
  forbidden_software_test_artifacts,
  function(x) grepl(x, manuscript, fixed = TRUE),
  logical(1L)
)]

canonical_table_input <- "\\input{../outputs/tables/TABLE_13_TREND_SENSITIVITY.tex}"
canonical_table_used <- grepl(canonical_table_input, manuscript, fixed = TRUE)
duplicate_table_path <- file.path(root, "paper", "tables", "TABLE_13_TREND_SENSITIVITY.tex")
duplicate_table_exists <- file.exists(duplicate_table_path)
daily_table_input <- "\\input{../outputs/tables/TABLE_14_SINASC_DAILY_DESIGN.tex}"
daily_table_used <- grepl(daily_table_input, manuscript, fixed = TRUE)
daily_duplicate_path <- file.path(root, "paper", "tables", "TABLE_14_SINASC_DAILY_DESIGN.tex")
daily_duplicate_exists <- file.exists(daily_duplicate_path)

if (length(missing_expected) || length(present_stale) || length(present_forbidden) ||
    length(present_software_test_artifacts) || !canonical_table_used ||
    duplicate_table_exists || !daily_table_used || daily_duplicate_exists) {
  if (length(missing_expected)) {
    message("Missing canonical manuscript values: ", paste(missing_expected, collapse = ", "))
    message("Expected tokens: ", paste(expected[missing_expected], collapse = "; "))
  }
  if (length(present_stale)) {
    message("Stale pre-A1 tokens remain: ", paste(present_stale, collapse = ", "))
  }
  if (length(present_forbidden)) {
    message("Forbidden design-wide trend claims remain: ",
            paste(present_forbidden, collapse = " | "))
  }
  if (length(present_software_test_artifacts)) {
    message("Synthetic software-test artifacts entered the manuscript: ",
            paste(present_software_test_artifacts, collapse = " | "))
  }
  if (!canonical_table_used) {
    message("Manuscript does not input the canonical output TABLE_13 directly")
  }
  if (duplicate_table_exists) {
    message("Duplicate paper-local TABLE_13 exists: ", duplicate_table_path)
  }
  if (!daily_table_used) {
    message("Manuscript does not input the canonical observed-data TABLE_14 directly")
  }
  if (daily_duplicate_exists) {
    message("Duplicate paper-local TABLE_14 exists: ", daily_duplicate_path)
  }
  quit(status = 1L)
}

cat(sprintf("paper_consistency_ok checks=%d stale_checks=%d\n",
            length(expected) + length(forbidden_claims) +
              length(forbidden_software_test_artifacts) + 4L,
            length(stale) + length(forbidden_claims) +
              length(forbidden_software_test_artifacts)))
