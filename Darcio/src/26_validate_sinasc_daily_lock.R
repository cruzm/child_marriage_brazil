#!/usr/bin/env Rscript
# Read-only integrity check for the frozen SINASC daily protocol.

suppressPackageStartupMessages({
  library(data.table)
  library(digest)
  library(yaml)
})

cwd <- normalizePath(getwd(), mustWork = TRUE)
root <- if (basename(cwd) == "Darcio") cwd else file.path(cwd, "Darcio")
if (!dir.exists(root)) stop("Cannot locate the Darcio project directory")

lock_path <- file.path(root, "config", "sinasc_daily_lock.yml")
doc_path <- file.path(root, "paper", "ledgers", "SINASC_DAILY_PROTOCOL.md")
amend_path <- file.path(root, "paper", "ledgers", "SINASC_DAILY_AMENDMENTS.md")
hash_path <- file.path(root, "paper", "ledgers", "SINASC_DAILY_LOCK_SHA256.txt")

stopifnot(file.exists(lock_path), file.exists(doc_path), file.exists(amend_path), file.exists(hash_path))

lock <- read_yaml(lock_path)
hash_lines <- readLines(hash_path, warn = FALSE)
expected_hash <- function(filename) {
  hit <- grep(paste0(filename, "$"), hash_lines, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub("[[:space:]].*$", "", hit)
}

actual_lock <- digest(lock_path, algo = "sha256", file = TRUE)
actual_doc <- digest(doc_path, algo = "sha256", file = TRUE)
actual_amend <- digest(amend_path, algo = "sha256", file = TRUE)
doc_lines <- readLines(doc_path, warn = FALSE)
amend_lines <- readLines(amend_path, warn = FALSE)

test <- function(name, condition, observed) {
  data.table(test = name, passed = isTRUE(condition), observed = as.character(observed))
}

tests <- rbindlist(list(
  test("machine-readable lock hash", identical(actual_lock, expected_hash("config/sinasc_daily_lock.yml")), actual_lock),
  test("human-readable protocol hash", identical(actual_doc, expected_hash("paper/ledgers/SINASC_DAILY_PROTOCOL.md")), actual_doc),
  test("amendment-ledger hash", identical(actual_amend, expected_hash("paper/ledgers/SINASC_DAILY_AMENDMENTS.md")), actual_amend),
  test("version is 1.0.0", identical(lock$protocol$version, "1.0.0"), lock$protocol$version),
  test("freeze timestamp agrees with protocol", any(grepl(lock$protocol$frozen_at, doc_lines, fixed = TRUE)), lock$protocol$frozen_at),
  test("freeze timestamp agrees with amendment ledger", any(grepl(lock$protocol$frozen_at, amend_lines, fixed = TRUE)), lock$protocol$frozen_at),
  test("protocol is explicitly post-result", isTRUE(lock$protocol$post_result_protocol), lock$protocol$post_result_protocol),
  test("no daily outcome contrast preceded freeze", isTRUE(lock$protocol$frozen_before_any_daily_age_distance_outcome_contrast), lock$protocol$frozen_before_any_daily_age_distance_outcome_contrast),
  test("daily results explicitly not seen", length(lock$not_seen_before_freeze) == 4L, length(lock$not_seen_before_freeze)),
  test("primary pre years are 2016-2018", identical(as.integer(unlist(lock$periods$primary_pre_years)), 2016:2018), paste(unlist(lock$periods$primary_pre_years), collapse = ",")),
  test("primary post years are 2022-2024", identical(as.integer(unlist(lock$periods$primary_post_years)), 2022:2024), paste(unlist(lock$periods$primary_post_years), collapse = ",")),
  test("2015 is excluded", identical(as.integer(unlist(lock$periods$excluded_data_error_years)), 2015L), paste(unlist(lock$periods$excluded_data_error_years), collapse = ",")),
  test("official annual totals are required", grepl("cached-file checksum alone is insufficient", lock$gates$G0_data$pass_requirements$official_annual_total_reconciliation, fixed = TRUE), lock$gates$G0_data$pass_requirements$official_annual_total_reconciliation),
  test("primary sample is singleton births", grepl("GRAVIDEZ = 1", lock$sample$primary$pregnancy_type, fixed = TRUE), lock$sample$primary$pregnancy_type),
  test("running variable uses calendar birthday", grepl("do not divide elapsed days by 365.25", lock$running_variable$construction, fixed = TRUE), lock$running_variable$construction),
  test("primary cutoff is age 16", identical(as.integer(lock$sample$primary$primary_cutoff_age), 16L), lock$sample$primary$primary_cutoff_age),
  test("primary bandwidth is 90 days", identical(as.integer(lock$primary_estimator$bandwidth_days), 90L), lock$primary_estimator$bandwidth_days),
  test("primary outcome is MARRIED", identical(lock$outcomes$primary$id, "MARRIED"), lock$outcomes$primary$id),
  test("one primary outcome has no multiplicity adjustment", grepl("none", lock$outcomes$primary$multiplicity_adjustment, ignore.case = TRUE), lock$outcomes$primary$multiplicity_adjustment),
  test("placebo cutoffs are 15,17,19", identical(as.integer(unlist(lock$running_variable$placebo_ages)), c(15L, 17L, 19L)), paste(unlist(lock$running_variable$placebo_ages), collapse = ",")),
  test("equivalence margin is 0.25 pp", identical(as.numeric(lock$gates$G2_counterfactual$equivalence_margin_pp), 0.25), lock$gates$G2_counterfactual$equivalence_margin_pp),
  test("delay-sensitive estimand is frozen", grepl("DELAY90", lock$estimand$delay_sensitive_secondary$notation, fixed = TRUE), lock$estimand$delay_sensitive_secondary$notation),
  test("stacked model retains inference for difference", grepl("stacked model supplies inference", lock$rdrobust_crosscheck$procedure, ignore.case = TRUE), lock$rdrobust_crosscheck$procedure),
  test("result remains a placeholder", identical(lock$estimand$result_placeholder, "[RESULT TO BE ESTIMATED]"), lock$estimand$result_placeholder),
  test("failed gate forbids recentering", grepl("Do not choose a new", lock$gates$overall_decision$do_not_recenter_paper, fixed = TRUE), lock$gates$overall_decision$do_not_recenter_paper)
), use.names = TRUE)

print(tests)
if (!all(tests$passed)) stop(sprintf("SINASC daily lock failed %d/%d checks", sum(!tests$passed), nrow(tests)))
cat(sprintf("sinasc_daily_lock_ok checks=%d\n", nrow(tests)))
