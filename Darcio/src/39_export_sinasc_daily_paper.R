#!/usr/bin/env Rscript

# Export the exact-age SINASC paper table from canonical, observed-data outputs.
# This script reads no R0 recovery artifact and no simulated or synthetic dataset.

cwd <- normalizePath(getwd(), mustWork = TRUE)
root <- if (file.exists(file.path(cwd, "paper", "main.tex"))) {
  cwd
} else if (file.exists(file.path(cwd, "Darcio", "paper", "main.tex"))) {
  file.path(cwd, "Darcio")
} else {
  stop("Run from the Darcio directory or its parent")
}

table_dir <- file.path(root, "outputs", "tables")
audit_dir <- file.path(root, "outputs", "audit")

inputs <- c(
  primary = file.path(table_dir, "SINASC_DAILY_PRIMARY.csv"),
  placebos = file.path(table_dir, "SINASC_DAILY_PLACEBOS.csv"),
  sensitivity = file.path(table_dir, "SINASC_DAILY_SENSITIVITY.csv"),
  g0 = file.path(audit_dir, "SINASC_DAILY_GATE_STATUS.csv"),
  g1 = file.path(audit_dir, "SINASC_DAILY_G1_GATE_STATUS.csv"),
  g2 = file.path(audit_dir, "SINASC_DAILY_G2_GATE_STATUS.csv"),
  g3 = file.path(audit_dir, "SINASC_DAILY_G3_GATE_STATUS.csv")
)

if (any(grepl("SYNTHETIC|RECOVERY", basename(inputs), ignore.case = TRUE))) {
  stop("A prohibited software-test artifact entered the paper-table input list")
}
missing_inputs <- inputs[!file.exists(inputs)]
if (length(missing_inputs)) {
  stop("Missing canonical SINASC daily input(s): ",
       paste(missing_inputs, collapse = ", "))
}

read_csv <- function(path) {
  read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
}

primary <- read_csv(inputs[["primary"]])
placebos <- read_csv(inputs[["placebos"]])
sensitivity <- read_csv(inputs[["sensitivity"]])
g0 <- read_csv(inputs[["g0"]])
g1 <- read_csv(inputs[["g1"]])
g2 <- read_csv(inputs[["g2"]])
g3 <- read_csv(inputs[["g3"]])

one_row <- function(data, column, value, label) {
  out <- data[data[[column]] == value, , drop = FALSE]
  if (nrow(out) != 1L) stop("Expected one row for ", label, "; found ", nrow(out))
  out
}

tau <- one_row(primary, "estimand", "TAU", "TAU")
delay <- one_row(primary, "estimand", "DELAY90", "DELAY90")
temporal <- one_row(placebos, "test_family", "temporal_placebo", "temporal placebo")
age_placebos <- placebos[placebos$test_family == "age_placebo", , drop = FALSE]
age_placebos <- age_placebos[order(age_placebos$cutoff_age), , drop = FALSE]
if (!identical(age_placebos$cutoff_age, c(15L, 17L, 19L))) {
  stop("Expected placebo cutoffs 15, 17, and 19")
}

gate_status <- function(data, criterion) {
  row <- one_row(data, "criterion", criterion, criterion)
  as.character(row$status[[1]])
}

current_gates <- c(
  G0 = gate_status(g0, "G0_OVERALL"),
  G1 = gate_status(g1, "G1_OVERALL"),
  G2 = gate_status(g2, "G2_OVERALL"),
  G3 = gate_status(g3, "G3_OVERALL")
)
expected_gates <- c(G0 = "PASS", G1 = "PASS", G2 = "QUALIFIED", G3 = "INCONCLUSIVE")
if (!identical(current_gates, expected_gates)) {
  stop("Gate status changed; revise the manuscript before exporting: ",
       paste(names(current_gates), current_gates, collapse = ", "))
}

if (!all(sensitivity$identified) || nrow(sensitivity) != 13L) {
  stop("The complete 13-row frozen sensitivity set must identify")
}

signed <- function(x, digits = 3L) sprintf(paste0("%+.", digits, "f"), x)
plain <- function(x, digits = 3L) sprintf(paste0("%.", digits, "f"), x)
p_value <- function(x) ifelse(x < 0.001, "$<0.001$", plain(x, 3L))
interval <- function(lo, hi, digits = 3L) {
  sprintf("[%s, %s]", signed(lo, digits), signed(hi, digits))
}
yes_no <- function(x) ifelse(isTRUE(x), "yes", "no")
tex_status <- function(x) paste0("\\textsc{", tolower(x), "}")

primary_rows <- c(
  sprintf("Immediate jump change ($\\tau$) & %s & %s & %s & %s & %s \\\\",
          signed(tau$estimate_pp), plain(tau$std_error_pp),
          interval(tau$ci95_low_pp, tau$ci95_high_pp),
          p_value(tau$p_value), tex_status(tau$g3_classification)),
  sprintf("Delay-sensitive 90-day profile & %s & %s & %s & %s & %s \\\\",
          signed(delay$estimate_pp), plain(delay$std_error_pp),
          interval(delay$ci95_low_pp, delay$ci95_high_pp),
          p_value(delay$p_value_holm_auxiliary_family),
          tex_status(delay$g3_classification))
)

placebo_rows <- c(
  sprintf("Pre-law temporal placebo & 16 & %s & %s & %s & %s \\\\",
          signed(temporal$estimate_pp),
          interval(temporal$ci90_low_pp, temporal$ci90_high_pp),
          p_value(temporal$p_value), yes_no(temporal$equivalent_at_90pct)),
  vapply(seq_len(nrow(age_placebos)), function(i) {
    row <- age_placebos[i, ]
    sprintf("Placebo birthday & %d & %s & %s & %s & %s \\\\",
            row$cutoff_age, signed(row$estimate_pp),
            interval(row$ci90_low_pp, row$ci90_high_pp),
            p_value(row$p_value_holm), yes_no(row$equivalent_at_90pct))
  }, character(1L))
)

gate_labels <- c(
  G0 = "Data integrity and power",
  G1 = "Density, missingness, and composition",
  G2 = "Counterfactual stability",
  G3 = "Informativeness"
)
gate_rows <- vapply(names(current_gates), function(gate) {
  sprintf("%s & %s & %s \\\\", gate, gate_labels[[gate]],
          tex_status(current_gates[[gate]]))
}, character(1L))

sensitivity_low <- min(sensitivity$estimate_pp)
sensitivity_high <- max(sensitivity$estimate_pp)
n_obs <- tau$n
n_events <- tau$n_outcome_events

lines <- c(
  "\\begin{table}[!htbp]",
  "\\centering",
  "\\caption{Exact-age SINASC difference in discontinuities and frozen validation gates.}",
  "\\label{tab:sinasc_daily}",
  "\\begingroup\\scriptsize",
  "\\textit{Panel A. Primary and delay-sensitive estimands (percentage points)}\\par\\smallskip",
  "\\begin{tabular}{@{}lrrrrl@{}}",
  "\\toprule",
  "Estimand & Estimate & SE & 95\\% CI & $p$ & Classification \\\\",
  "\\midrule",
  primary_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\par\\medskip",
  "\\textit{Panel B. Counterfactual diagnostics (percentage points)}\\par\\smallskip",
  "\\begin{tabular}{@{}lrrrrr@{}}",
  "\\toprule",
  "Diagnostic & Cutoff age & Estimate & 90\\% CI & $p$ & Equivalent \\\\",
  "\\midrule",
  placebo_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\par\\medskip",
  "\\textit{Panel C. Mechanical gate verdicts}\\par\\smallskip",
  "\\begin{tabular}{@{}lll@{}}",
  "\\toprule",
  "Gate & Object & Verdict \\\\",
  "\\midrule",
  gate_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\par\\smallskip",
  "\\begin{minipage}{0.98\\linewidth}\\footnotesize",
  sprintf(paste0(
    "\\emph{Notes:} All rows derive from observed official SINASC records. ",
    "The primary sample contains %s singleton live births and %s recorded-married ",
    "outcomes within 90 days of the mother's sixteenth birthday. $\\tau$ is the ",
    "2022--2024 minus 2016--2018 change in the right-minus-left cutoff jump. ",
    "The model uses triangular weights, birth-year and child-calendar-month fixed ",
    "effects, and two-way clustering by municipality and exact birth date. The ",
    "primary $p$ is unadjusted; the delay-sensitive $p$ is Holm-adjusted within the ",
    "two-estimand auxiliary family. Placebo-cutoff $p$-values are Holm-adjusted ",
    "within ages 15, 17, and 19; the temporal-placebo $p$ is unadjusted. Equivalence ",
    "requires the 90\\%% interval to lie inside $\\pm0.25$ points. All 13 frozen ",
    "sensitivity estimates are identified and span [%s, %s] points. Qualified G2 ",
    "and inconclusive G3 prohibit an unconditional causal interpretation."
  ), format(n_obs, big.mark = ","), format(n_events, big.mark = ","),
  signed(sensitivity_low), signed(sensitivity_high)),
  "\\end{minipage}",
  "\\endgroup",
  "\\end{table}"
)

output <- file.path(table_dir, "TABLE_14_SINASC_DAILY_DESIGN.tex")
writeLines(lines, output, useBytes = TRUE)
cat("written: ", output, "\n", sep = "")
