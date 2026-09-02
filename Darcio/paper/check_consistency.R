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

signed <- function(x, digits) sprintf(paste0("%+.", digits, "f"), x)
tex_pct <- function(x, digits = 1L) paste0("$", signed(x, digits), "\\%$")

expected <- c(
  registry_primary = tex_pct(registry$percent_change),
  registry_no_trend = tex_pct(trend$percent_change),
  union_primary = paste0("$", signed(100 * union$estimate, 3L), "$"),
  sinasc_primary = tex_pct(status$pct_change),
  sinasc_no_trend = tex_pct(status_rob$pct_change),
  sinasc_fertility = tex_pct(fertility$pct_change),
  sinasc_fertility_p = sprintf("$p=%.3f$", fertility$p_value),
  sinasc_missing_p = sprintf("$p=%.3f$", missingness$p_value),
  placebo_2017 = tex_pct(placebos$pct_change[placebos$specification == "placebo_2017"]),
  placebo_2018 = tex_pct(placebos$pct_change[placebos$specification == "placebo_2018"])
)

missing_expected <- names(expected)[!vapply(
  expected, function(x) grepl(x, manuscript, fixed = TRUE), logical(1L)
)]

stale <- c(
  "$+30.0\\%$", "$+17.8\\%$", "$+37.0\\%$", "$-23.6\\%$",
  "$+1.8\\%$", "$p=0.24$", "$p=0.58$"
)
present_stale <- stale[vapply(stale, function(x) grepl(x, manuscript, fixed = TRUE), logical(1L))]

if (length(missing_expected) || length(present_stale)) {
  if (length(missing_expected)) {
    message("Missing canonical manuscript values: ", paste(missing_expected, collapse = ", "))
    message("Expected tokens: ", paste(expected[missing_expected], collapse = "; "))
  }
  if (length(present_stale)) {
    message("Stale pre-A1 tokens remain: ", paste(present_stale, collapse = ", "))
  }
  quit(status = 1L)
}

cat(sprintf("paper_consistency_ok checks=%d stale_checks=%d\n",
            length(expected), length(stale)))
