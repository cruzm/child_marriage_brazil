#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(digest)
  library(yaml)
})

started <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
analysis_dir <- file.path(root, "outputs", "analysis")
audit_dir <- file.path(root, "outputs", "audit")
log_dir <- file.path(root, "outputs", "logs")
lock_path <- file.path(root, "config", "specification_lock.yml")
document_path <- file.path(analysis_dir, "ESTIMANDS_AND_SPECIFICATIONS.md")
hash_path <- file.path(analysis_dir, "SPECIFICATION_LOCK_SHA256.txt")

lock <- read_yaml(lock_path)
hash_lines <- readLines(hash_path, warn = FALSE)
expected_doc <- sub(" .*", "", grep("ESTIMANDS_AND_SPECIFICATIONS", hash_lines, value = TRUE))
expected_yml <- sub(" .*", "", grep("specification_lock.yml", hash_lines, value = TRUE))
actual_doc <- digest(document_path, algo = "sha256", file = TRUE)
actual_yml <- digest(lock_path, algo = "sha256", file = TRUE)

tests <- rbindlist(list(
  data.table(test = "human-readable specification hash matches", passed = identical(actual_doc, expected_doc), observed = actual_doc),
  data.table(test = "machine-readable lock hash matches", passed = identical(actual_yml, expected_yml), observed = actual_yml),
  data.table(test = "lock says frozen before post estimation", passed = isTRUE(lock$frozen_before_post_reform_estimation), observed = as.character(lock$frozen_before_post_reform_estimation)),
  data.table(test = "lock records no effects seen", passed = identical(lock$effect_estimates_seen_before_lock, FALSE), observed = as.character(lock$effect_estimates_seen_before_lock)),
  data.table(test = "direct treatment age is 15", passed = identical(as.integer(lock$treatment_and_controls$treated_age), 15L), observed = as.character(lock$treatment_and_controls$treated_age)),
  data.table(test = "primary controls are 17-19", passed = identical(as.integer(unlist(lock$treatment_and_controls$primary_controls)), 17:19), observed = paste(unlist(lock$treatment_and_controls$primary_controls), collapse = ",")),
  data.table(test = "2019Q1 is omitted", passed = identical(lock$timing$omitted_partial_period, "2019Q1"), observed = lock$timing$omitted_partial_period),
  data.table(test = "full post begins 2019Q2", passed = identical(lock$timing$first_full_post_period, "2019Q2"), observed = lock$timing$first_full_post_period),
  data.table(test = "primary geography is region", passed = identical(lock$data$denominator_primary$selected_geography, "region"), observed = lock$data$denominator_primary$selected_geography),
  data.table(test = "primary inference clusters by period", passed = identical(lock$inference$primary_ppml_vcov, "cluster by quarter-period"), observed = lock$inference$primary_ppml_vcov),
  data.table(test = "municipality forbidden", passed = identical(lock$geographic_compatibility$municipality_allowed, FALSE), observed = as.character(lock$geographic_compatibility$municipality_allowed)),
  data.table(test = "conventional RD not specified", passed = !grepl("regression discontinuity|conventional RD", lock$registry_primary_model$family, ignore.case = TRUE), observed = lock$registry_primary_model$family)
), use.names = TRUE)
fwrite(tests, file.path(audit_dir, "GATE_C_ACCEPTANCE_TESTS.csv"))
if (!all(tests$passed)) stop("Specification-lock acceptance test failed")

summary_lines <- c(
  "# Gate C — specification lock complete",
  "",
  sprintf("Validated: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  sprintf("- Frozen at: %s", lock$frozen_at),
  sprintf("- Human-readable specification SHA-256: `%s`", actual_doc),
  sprintf("- Machine-readable YAML SHA-256: `%s`", actual_yml),
  sprintf("- Acceptance tests: %d/%d passed.", sum(tests$passed), nrow(tests)),
  "- Primary estimand: civil-registration incidence at age 15 per 100,000 age-15 residents, both sexes combined.",
  "- Primary window: 2013T1–2018T4 versus 2019T2–T4; 2019T1 omitted.",
  "- Primary model: region-level age-based PPML DiD with population offset, age-specific seasonality and trends.",
  "- Primary inference: clustering by quarter-period, triangulated with HAC, temporal block bootstrap, two-way clustering, and placebos.",
  "- Any amendment must be documented before re-estimation in `SPECIFICATION_AMENDMENTS.md`.",
  ""
)
writeLines(summary_lines, file.path(analysis_dir, "GATE_C_SPECIFICATION_LOCK.md"))

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("tests_passed=%d", sum(tests$passed)),
  sprintf("tests_total=%d", nrow(tests)),
  sprintf("specification_md_sha256=%s", actual_doc),
  sprintf("specification_yml_sha256=%s", actual_yml),
  "gate=C_complete"
)
writeLines(log_lines, file.path(log_dir, "11_validate_specification_lock.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
