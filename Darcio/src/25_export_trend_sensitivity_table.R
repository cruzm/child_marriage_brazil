#!/usr/bin/env Rscript
# 25_export_trend_sensitivity_table.R — LaTeX fragment for the registry
# trend-sensitivity extension (frozen lock v1.0.0). Reads only the canonical
# CSVs produced by src/24_trend_sensitivity_registry.R.

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages(library(data.table))

root <- file.path(normalizePath(getwd(), mustWork = TRUE), "Darcio")
m <- fread(file.path(root, "outputs", "tables", "REGISTRY_TREND_SENSITIVITY_MODELS.csv"))
setorder(m, rolling_window_rmse)

fmt <- function(x, d = 1) formatC(x, format = "f", digits = d)
lbl <- c(global_linear = "Global linear trend", local_linear_12 = "Local linear (12q)",
         local_linear_16 = "Local linear (16q)", global_quadratic = "Global quadratic",
         seasonal_level = "Seasonal level (no trend)")

rows <- m[, sprintf("%s & %s & %s & %d/6 & %s & %s & [%s; %s] & %s \\\\",
  lbl[model_id], fmt(rolling_window_rmse, 3), fmt(rolling_window_max_abs_error, 3),
  windows_within_1_20, calibration_tier, fmt(target_percent_change),
  fmt(ci_lower_percent), fmt(ci_upper_percent), fmt(p_value, 2))]

out <- c(
"\\begin{table}[!htbp]",
"\\centering",
"\\caption{Post-result forecast validation of counterfactual trend models (frozen lock v1.0.0). Calibration gate: \\emph{failed} --- no candidate reaches the qualified tier; the locked PPML remains primary and the cross-model range is a specification envelope, not a confidence set.}",
"\\label{tab:trend_sensitivity}",
"\\begingroup\\small",
"\\begin{tabular}{lccclccc}",
"  \\hline",
" Candidate & RMSE & Max $|$err$|$ & $\\le$1.20 & Tier & 2019Q2--Q4 \\% & Forecast 95\\% & $p$ \\\\ ",
"  \\hline",
rows,
"  \\hline",
"\\end{tabular}",
"\\endgroup",
"\\par\\smallskip\\begingroup\\footnotesize Six overlapping three-quarter rolling windows, 2017Q1--2018Q2, models fit strictly before each window; RMSE of window-mean errors (log scale). Intervals: circular moving-block bootstrap (1,999 draws) of the three-quarter mean forecast error. Inverse-RMSE$^2$ ensemble: $+3.0\\%$ (point only). All-model envelope: $[-33.7\\%, +12.8\\%]$.\\endgroup",
"\\end{table}")
writeLines(out, file.path(root, "outputs", "tables", "TABLE_13_TREND_SENSITIVITY.tex"))
file.copy(file.path(root, "outputs", "tables", "TABLE_13_TREND_SENSITIVITY.tex"),
          file.path(root, "paper", "tables", "TABLE_13_TREND_SENSITIVITY.tex"),
          overwrite = TRUE)
cat("written: TABLE_13_TREND_SENSITIVITY.tex (outputs/tables + paper/tables)\n")
