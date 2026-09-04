#!/usr/bin/env Rscript
# Read-only acceptance checks for Gate G1. This validator consumes only
# aggregated G0/G1 artifacts. It never reads person-level data or estimates a
# marriage-status outcome, a placebo, or a policy effect.

options(stringsAsFactors = FALSE)

cwd <- normalizePath(getwd(), mustWork = TRUE)
root <- if (file.exists(file.path(cwd, "config", "sinasc_daily_lock.yml"))) {
  cwd
} else {
  file.path(cwd, "Darcio")
}
if (!dir.exists(root)) stop("Cannot locate the Darcio project directory")

.libPaths(c(file.path(root, "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(digest)
})

audit_dir <- file.path(root, "outputs", "audit")
paths <- c(
  schema = file.path(audit_dir, "SINASC_DAILY_G1_SCHEMA_AUDIT.csv"),
  sample = file.path(audit_dir, "SINASC_DAILY_G1_SAMPLE_RECONCILIATION.csv"),
  daily = file.path(audit_dir, "SINASC_DAILY_G1_DAILY_COUNTS.csv"),
  weekly = file.path(audit_dir, "SINASC_DAILY_G1_WEEKLY_COUNTS.csv"),
  equal_day = file.path(audit_dir, "SINASC_DAILY_G1_EQUAL_DAY_COUNTS.csv"),
  density = file.path(audit_dir, "SINASC_DAILY_G1_DENSITY.csv"),
  density_binomial = file.path(audit_dir, "SINASC_DAILY_G1_DENSITY_BINOMIAL.csv"),
  continuity = file.path(audit_dir, "SINASC_DAILY_G1_CONTINUITY.csv"),
  status_missingness = file.path(audit_dir, "SINASC_DAILY_G1_STATUS_MISSINGNESS.csv"),
  gate = file.path(audit_dir, "SINASC_DAILY_G1_GATE_STATUS.csv"),
  report = file.path(root, "outputs", "analysis", "SINASC_DAILY_GATE_G1.md"),
  figure_pdf = file.path(root, "outputs", "figures",
                         "FIGURE_SINASC_DAILY_G1_DENSITY.pdf"),
  figure_png = file.path(root, "outputs", "figures",
                         "FIGURE_SINASC_DAILY_G1_DENSITY.png"),
  manifest = file.path(audit_dir, "SINASC_DAILY_G1_OUTPUT_MANIFEST.csv")
)
if (!all(file.exists(paths))) {
  stop("Missing G1 artifact(s): ",
       paste(names(paths)[!file.exists(paths)], collapse = ", "))
}

schema <- fread(paths[["schema"]])
sample_rec <- fread(paths[["sample"]])
daily <- fread(paths[["daily"]])
weekly <- fread(paths[["weekly"]])
equal_day <- fread(paths[["equal_day"]])
density <- fread(paths[["density"]])
density_binomial <- fread(paths[["density_binomial"]])
continuity <- fread(paths[["continuity"]])
status_missingness <- fread(paths[["status_missingness"]])
gate <- fread(paths[["gate"]])
output_manifest <- fread(paths[["manifest"]])
report_text <- paste(readLines(paths[["report"]], warn = FALSE),
                     collapse = " ")
source_text <- paste(readLines(file.path(root, "src",
                                         "29_sinasc_daily_gate_g1.R"),
                               warn = FALSE), collapse = "\n")

test <- function(name, condition, observed) {
  data.table(test = name, passed = isTRUE(condition),
             observed = paste(as.character(observed), collapse = ","))
}

near <- function(x, y, tolerance = 1e-10) {
  length(x) == length(y) &&
    all((is.na(x) & is.na(y)) |
          (!is.na(x) & !is.na(y) &
             abs(x - y) <= tolerance * pmax(1, abs(x), abs(y))))
}

same_keys <- function(x, y, cols) {
  a <- unique(x[, ..cols])
  b <- unique(y[, ..cols])
  encode <- function(z) do.call(paste, c(z, sep = "\r"))
  nrow(a) == nrow(b) && setequal(encode(a), encode(b))
}

expected_years <- c(2016:2018, 2022:2024)
expected_eras <- c(rep("pre", 3L), rep("post", 3L))
expected_bands <- c(30L, 60L, 90L, 180L)
expected_sides <- c("above", "below")
expected_density_eras <- c("pre", "post")
expected_equal_keys <- CJ(era = expected_density_eras,
                          k_days_each_side = c(7L, 14L, 30L),
                          unique = TRUE)
expected_sample_keys <- CJ(year = expected_years,
                           bandwidth_days = expected_bands,
                           side = expected_sides,
                           unique = TRUE)
expected_sample_keys[, era := ifelse(year <= 2018L, "pre", "post")]

# Frozen-protocol and G0 precondition integrity.
hash_registry <- file.path(root, "paper", "ledgers",
                           "SINASC_DAILY_LOCK_SHA256.txt")
frozen_rel <- c(
  "config/sinasc_daily_lock.yml",
  "paper/ledgers/SINASC_DAILY_PROTOCOL.md",
  "paper/ledgers/SINASC_DAILY_AMENDMENTS.md"
)
hash_lines <- readLines(hash_registry, warn = FALSE)
registered_hash <- function(rel) {
  hit <- grep(paste0(rel, "$"), hash_lines, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub("[[:space:]].*$", "", hit)
}
frozen_expected <- vapply(frozen_rel, registered_hash, character(1))
frozen_actual <- vapply(frozen_rel, function(rel) {
  digest(file.path(root, rel), algo = "sha256", file = TRUE)
}, character(1))

g0_gate_path <- file.path(audit_dir, "SINASC_DAILY_GATE_STATUS.csv")
g0_manifest_path <- file.path(audit_dir,
                              "SINASC_DAILY_G0_OUTPUT_MANIFEST.csv")
g0_gate <- fread(g0_gate_path)
g0_manifest <- fread(g0_manifest_path)
g0_files <- file.path(root, g0_manifest$artifact)
g0_actual_hash <- vapply(g0_files, digest, character(1), algo = "sha256",
                         file = TRUE)

# Reconstruct all count-only summaries from the exported daily grid.
daily_for_week <- copy(daily)
daily_for_week[, weekly_bin := ifelse(
  x_days < 0L, -ceiling(abs(x_days) / 7), floor(x_days / 7)
)]
weekly_expected <- daily_for_week[, .(
  bin_start = min(x_days),
  bin_end = max(x_days),
  bin_midpoint = mean(range(x_days)),
  n_calendar_days = .N,
  n_births = sum(n_births),
  births_per_age_day = mean(n_births)
), by = .(era, weekly_bin)]
setorder(weekly_expected, era, weekly_bin)
weekly_check <- merge(
  weekly_expected,
  weekly,
  by = c("era", "weekly_bin"), all = TRUE,
  suffixes = c("_expected", "_reported")
)

equal_expected <- rbindlist(lapply(expected_density_eras, function(e) {
  rbindlist(lapply(c(7L, 14L, 30L), function(k) {
    n_left <- daily[era == e & x_days >= -k & x_days <= -1L,
                    sum(n_births)]
    n_right <- daily[era == e & x_days >= 0L & x_days <= k - 1L,
                     sum(n_births)]
    data.table(
      era = e,
      k_days_each_side = k,
      left_window = sprintf("-%d..-1", k),
      right_window = sprintf("0..%d", k - 1L),
      n_left = as.numeric(n_left),
      n_right = as.numeric(n_right),
      right_left_ratio = n_right / n_left,
      log_right_left_ratio = log(n_right / n_left),
      exact_binomial_p_value = binom.test(
        n_right, n_left + n_right, p = 0.5
      )$p.value
    )
  }))
}))
equal_check <- merge(
  equal_expected, equal_day,
  by = c("era", "k_days_each_side"), all = TRUE,
  suffixes = c("_expected", "_reported")
)

density_check <- copy(density)
density_check[, `:=`(
  expected_log_ratio = log(robust_density_right / robust_density_left),
  expected_rejects = identified & robust_p_value < 0.05,
  expected_exceeds = identified &
    abs(log_right_left_density_ratio) > abs(log(1.05))
)]
density_check[, expected_hard := identified & expected_rejects &
                expected_exceeds]
density_counts <- daily[, .(
  expected_n_full = sum(n_births),
  expected_n_left = sum(n_births[x_days < 0L]),
  expected_n_right = sum(n_births[x_days >= 0L])
), by = era]
density_check <- merge(density_check, density_counts, by = "era", all = TRUE)

binomial_expected_p <- vapply(seq_len(nrow(density_binomial)), function(i) {
  z <- density_binomial[i]
  binom.test(z$n_right, z$n_left + z$n_right, p = 0.5)$p.value
}, numeric(1))

continuity_check <- copy(continuity)
continuity_check[, expected_holm := p.adjust(p_value, method = "holm"),
                 by = family]
continuity_check[, expected_standardized :=
                   abs(above_x_post_pp) / (100 * weighted_sd)]
continuity_check[, expected_hard :=
                   family == "predetermined_hard" & identified &
                   expected_holm < 0.05 & expected_standardized >= 0.10]

expected_hard_ids <- c(
  paste0("race_", c("white", "black", "yellow", "brown", "indigenous")),
  paste0("birthplace_", c("north", "northeast", "southeast", "south",
                            "center_west"))
)
expected_missing_ids <- c("race_unknown", "birthplace_unknown")
expected_composition_ids <- c(
  paste0("school_", c("none", "fundamental_i", "fundamental_ii",
                        "secondary", "higher_incomplete", "higher_complete",
                        "unknown")),
  "primiparous", "primiparity_unknown",
  paste0("residence_", c("north", "northeast", "southeast", "south",
                           "center_west"))
)

status_expected_rejects <- status_missingness$identified &
  status_missingness$p_value < 0.05
status_expected_exceeds <- status_missingness$identified &
  abs(status_missingness$above_x_post_pp) >= 0.50
status_expected_hard <- status_expected_rejects & status_expected_exceeds

density_status <- if (any(!density$identified)) {
  "QUALIFIED"
} else if (any(density_check$expected_hard)) {
  "FAIL"
} else {
  "PASS"
}
hard_family <- continuity_check[family == "predetermined_hard"]
predetermined_status <- if (any(!hard_family$identified)) {
  "QUALIFIED"
} else if (any(hard_family$expected_hard)) {
  "FAIL"
} else {
  "PASS"
}
missing_status <- if (!status_missingness$identified) {
  "QUALIFIED"
} else if (status_expected_hard) {
  "FAIL"
} else {
  "PASS"
}
overall_expected <- if (any(c(density_status, predetermined_status,
                              missing_status) == "FAIL")) {
  "FAIL"
} else if (any(c(density_status, predetermined_status,
                 missing_status) == "QUALIFIED")) {
  "QUALIFIED"
} else {
  "PASS"
}
gate_expected_status <- c(
  G0_precondition = "PASS",
  density_by_primary_era = density_status,
  predetermined_covariate_continuity = predetermined_status,
  status_missingness_continuity = missing_status,
  composition_family = "DIAGNOSTIC_ONLY",
  G1_OVERALL = overall_expected
)
gate_expected_failures <- c(
  G0_precondition = 0L,
  density_by_primary_era = sum(density_check$expected_hard, na.rm = TRUE),
  predetermined_covariate_continuity = sum(hard_family$expected_hard,
                                           na.rm = TRUE),
  status_missingness_continuity = sum(status_expected_hard, na.rm = TRUE),
  composition_family = 0L,
  G1_OVERALL = sum(c(density_check$expected_hard,
                     hard_family$expected_hard,
                     status_expected_hard), na.rm = TRUE)
)
gate_status_reported <- setNames(gate$status, gate$criterion)
gate_failures_reported <- setNames(gate$hard_failures, gate$criterion)

manifest_expected_rel <- sub(
  paste0("^", root, "/"), "", paths[names(paths) != "manifest"]
)
manifest_paths <- file.path(root, output_manifest$artifact)
manifest_actual_hash <- vapply(manifest_paths, digest, character(1),
                               algo = "sha256", file = TRUE)

all_exported <- list(schema, sample_rec, daily, weekly, equal_day, density,
                     density_binomial, continuity, status_missingness, gate)
exported_names <- unique(unlist(lapply(all_exported, names)))
forbidden_fields <- c("married", "MARRIED", "uniao_estavel", "any_union",
                      "tau", "delay90")
married_code_constructed <- grepl(
  "ESTCIVMAE[^\\n]{0,80}==[[:space:]]*['\"]?2['\"]?",
  source_text, perl = TRUE
)

pdf_signature <- rawToChar(readBin(paths[["figure_pdf"]], "raw", n = 4L))
png_signature <- readBin(paths[["figure_png"]], "raw", n = 8L)
expected_png_signature <- as.raw(c(0x89, 0x50, 0x4e, 0x47,
                                   0x0d, 0x0a, 0x1a, 0x0a))

tests <- rbindlist(list(
  test("all fourteen G1 artifacts exist", all(file.exists(paths)),
       length(paths)),
  test("frozen lock, protocol, and amendment hashes match registry",
       !anyNA(frozen_expected) &
         identical(unname(frozen_actual), unname(frozen_expected)),
       sprintf("%d/%d", sum(frozen_actual == frozen_expected,
                             na.rm = TRUE), length(frozen_rel))),
  test("G0 precondition remains PASS",
       identical(g0_gate[criterion == "G0_OVERALL", status], "PASS"),
       g0_gate[criterion == "G0_OVERALL", status]),
  test("G0 artifacts remain unchanged",
       all(file.exists(g0_files)) &
         identical(unname(g0_actual_hash), unname(g0_manifest$sha256)),
       sprintf("%d/%d", sum(g0_actual_hash == g0_manifest$sha256),
               nrow(g0_manifest))),
  test("schema covers exactly the six primary years and eras",
       nrow(schema) == 6L & identical(schema$year, expected_years) &
         identical(schema$era, expected_eras),
       paste(schema$year, schema$era, collapse = ";")),
  test("G1 schema and raw-file hash checks all pass",
       all(schema$required_g1_schema_complete) &
         all(schema$g0_raw_sha256_match) &
         all(schema$n_density_support_inclusive > 0),
       sprintf("schema=%d/6;hash=%d/6",
               sum(schema$required_g1_schema_complete),
               sum(schema$g0_raw_sha256_match))),
  test("sample reconciliation has all 48 frozen cells",
       nrow(sample_rec) == 48L &
         same_keys(sample_rec, expected_sample_keys,
                   c("year", "bandwidth_days", "side", "era")),
       nrow(sample_rec)),
  test("all G1 sample counts reproduce G0",
       all(sample_rec$singleton_count_match) &
         all(sample_rec$valid_status_count_match) &
         all(sample_rec$g1_n_singleton == sample_rec$g0_n_singleton) &
         all(sample_rec$g1_n_valid_status ==
               sample_rec$g0_n_valid_status),
       sprintf("singleton=%d/48;status=%d/48",
               sum(sample_rec$singleton_count_match),
               sum(sample_rec$valid_status_count_match))),
  test("daily grid is complete and unique on -180 through 180",
       nrow(daily) == 722L &
         !anyDuplicated(daily[, .(era, x_days)]) &
         all(vapply(expected_density_eras, function(e) {
           identical(daily[era == e, sort(x_days)], -180:180)
         }, logical(1))),
       nrow(daily)),
  test("daily counts are nonnegative integers with correct sides",
       all(is.finite(daily$n_births)) & all(daily$n_births >= 0) &
         all(daily$n_births == floor(daily$n_births)) &
         all(daily$side == ifelse(daily$x_days < 0L, "below", "above")),
       sum(daily$n_births)),
  test("weekly summaries exactly aggregate the daily grid",
       nrow(weekly_check) == nrow(weekly_expected) &
         near(weekly_check$bin_start_expected,
              weekly_check$bin_start_reported) &
         near(weekly_check$bin_end_expected,
              weekly_check$bin_end_reported) &
         near(weekly_check$bin_midpoint_expected,
              weekly_check$bin_midpoint_reported) &
         near(weekly_check$n_calendar_days_expected,
              weekly_check$n_calendar_days_reported) &
         near(weekly_check$n_births_expected,
              weekly_check$n_births_reported) &
         near(weekly_check$births_per_age_day_expected,
              weekly_check$births_per_age_day_reported),
       nrow(weekly_check)),
  test("equal-day table has the six frozen diagnostic windows",
       nrow(equal_day) == 6L &
         same_keys(equal_day, expected_equal_keys,
                   c("era", "k_days_each_side")) &
         all(equal_day$diagnostic_only),
       nrow(equal_day)),
  test("equal-day counts, ratios, logs, and exact p-values recompute",
       nrow(equal_check) == 6L &
         identical(equal_check$left_window_expected,
                   equal_check$left_window_reported) &
         identical(equal_check$right_window_expected,
                   equal_check$right_window_reported) &
         near(equal_check$n_left_expected, equal_check$n_left_reported) &
         near(equal_check$n_right_expected, equal_check$n_right_reported) &
         near(equal_check$right_left_ratio_expected,
              equal_check$right_left_ratio_reported) &
         near(equal_check$log_right_left_ratio_expected,
              equal_check$log_right_left_ratio_reported) &
         near(equal_check$exact_binomial_p_value_expected,
              equal_check$exact_binomial_p_value_reported),
       sprintf("%d rows", nrow(equal_check))),
  test("density test covers and identifies both primary eras",
       nrow(density) == 2L & setequal(density$era, expected_density_eras) &
         all(density$identified) &
         all(is.finite(density$robust_p_value)) &
         all(density$robust_p_value >= 0 & density$robust_p_value <= 1),
       sprintf("identified=%d/2", sum(density$identified))),
  test("density settings match prospective amendment A002",
       all(density$mass_points_adjusted) &
         all(density$polynomial_p == 2L) &
         all(density$bias_correction_q == 3L) &
         all(density$bandwidth_selector == "comb") &
         all(density$bandwidth_left_days > 0 &
               density$bandwidth_left_days <= 180) &
         all(density$bandwidth_right_days > 0 &
               density$bandwidth_right_days <= 180),
       paste(density$bandwidth_selector, collapse = ",")),
  test("density sample sizes reproduce exported daily counts",
       all(density_check$n_full == density_check$expected_n_full) &
         all(density_check$n_left == density_check$expected_n_left) &
         all(density_check$n_right == density_check$expected_n_right),
       paste(density_check$n_full, collapse = ",")),
  test("density log ratios and frozen threshold recompute",
       near(density_check$log_right_left_density_ratio,
            density_check$expected_log_ratio) &
         near(density_check$abs_log_ratio_threshold,
              rep(abs(log(1.05)), nrow(density_check))),
       paste(round(density_check$log_right_left_density_ratio, 6L),
             collapse = ",")),
  test("density hard-failure conjunction recomputes",
       identical(density_check$rejects_equality_at_5pct,
                 density_check$expected_rejects) &
         identical(density_check$exceeds_five_percent_log_threshold,
                   density_check$expected_exceeds) &
         identical(density_check$density_hard_failure,
                   density_check$expected_hard),
       sum(density_check$expected_hard)),
  test("rddensity binomial diagnostics are complete and internally exact",
       nrow(density_binomial) == 20L &
         all(density_binomial$diagnostic_only) &
         all(density_binomial$p_value >= 0 &
               density_binomial$p_value <= 1) &
         all(vapply(expected_density_eras, function(e) {
           identical(density_binomial[era == e, window_index], 1:10)
         }, logical(1))) &
         near(density_binomial$p_value, binomial_expected_p),
       nrow(density_binomial)),
  test("continuity families contain exactly 10 hard, 2 missingness, and 14 composition indicators",
       nrow(continuity) == 26L &
         setequal(continuity[family == "predetermined_hard", variable_id],
                  expected_hard_ids) &
         setequal(continuity[family == "predetermined_missingness", variable_id],
                  expected_missing_ids) &
         setequal(continuity[family == "composition", variable_id],
                  expected_composition_ids),
       paste(continuity[, .N, by = family][, paste(family, N, sep = "=")],
             collapse = ";")),
  test("continuity family roles and family sizes are frozen",
       all(continuity[family == "predetermined_hard",
                      gate_role == "hard_gate" & holm_family_size == 10L]) &
         all(continuity[family == "predetermined_missingness",
                        gate_role == "diagnostic_only" &
                          holm_family_size == 2L]) &
         all(continuity[family == "composition",
                        gate_role == "diagnostic_only" &
                          holm_family_size == 14L]),
       paste(unique(continuity$holm_family_size), collapse = ",")),
  test("all 26 continuity diagnostics are identified and finite",
       all(continuity$identified) &
         all(is.finite(continuity$above_x_post_pp)) &
         all(is.finite(continuity$std_error_pp)) &
         all(continuity$std_error_pp > 0) &
         all(continuity$p_value >= 0 & continuity$p_value <= 1),
       sprintf("%d/26", sum(continuity$identified))),
  test("Holm p-values and standardized magnitudes recompute",
       near(continuity_check$p_value_holm,
            continuity_check$expected_holm) &
         near(continuity_check$absolute_standardized_magnitude,
              continuity_check$expected_standardized),
       sprintf("max standardized=%.6f",
               max(continuity$absolute_standardized_magnitude))),
  test("predetermined hard-failure conjunction recomputes",
       identical(continuity_check$hard_failure,
                 continuity_check$expected_hard),
       sum(continuity_check$expected_hard)),
  test("status-missingness diagnostic uses the frozen definition",
       nrow(status_missingness) == 1L &
         identical(status_missingness$outcome,
                   "invalid_or_missing_ESTCIVMAE") &
         identical(status_missingness$definition,
                   "ESTCIVMAE outside codes 1-5") &
         near(status_missingness$magnitude_threshold_pp, 0.50),
       status_missingness$outcome),
  test("status-missingness hard-failure conjunction recomputes",
       identical(status_missingness$rejects_at_5pct,
                 status_expected_rejects) &
         identical(status_missingness$exceeds_magnitude_threshold,
                   status_expected_exceeds) &
         identical(status_missingness$hard_failure,
                   status_expected_hard),
       status_expected_hard),
  test("gate status and hard-failure counts recompute from diagnostics",
       identical(unname(gate_status_reported[names(gate_expected_status)]),
                 unname(gate_expected_status)) &
         identical(as.numeric(gate_failures_reported[
           names(gate_expected_failures)]),
           as.numeric(gate_expected_failures)),
       gate_status_reported["G1_OVERALL"]),
  test("G1 report records the recomputed verdict and exclusive scope",
       grepl(sprintf("Status: %s", overall_expected), report_text,
             fixed = TRUE) &
         grepl("not construct or estimate the married-status outcome",
               report_text, fixed = TRUE) &
         grepl("G2 and G3 were not run", report_text, fixed = TRUE),
       overall_expected),
  test("G1 exports contain no marriage-effect field",
       !any(exported_names %chin% forbidden_fields) &
         !married_code_constructed,
       paste(intersect(exported_names, forbidden_fields), collapse = ",")),
  test("density figures are nonempty PDF and PNG files",
       file.info(paths[["figure_pdf"]])$size > 10000 &
         file.info(paths[["figure_png"]])$size > 10000 &
         identical(pdf_signature, "%PDF") &
         identical(png_signature, expected_png_signature),
       sprintf("pdf=%d;png=%d",
               file.info(paths[["figure_pdf"]])$size,
               file.info(paths[["figure_png"]])$size)),
  test("output manifest lists exactly the thirteen generated artifacts",
       nrow(output_manifest) == 13L &
         !anyDuplicated(output_manifest$artifact) &
         setequal(output_manifest$artifact, manifest_expected_rel) &
         all(output_manifest$scope ==
               "G1_only_no_marriage_effect_estimation"),
       nrow(output_manifest)),
  test("output manifest hashes every listed artifact",
       all(file.exists(manifest_paths)) &
         identical(unname(manifest_actual_hash),
                   unname(output_manifest$sha256)),
       sprintf("%d/%d", sum(manifest_actual_hash ==
                               output_manifest$sha256),
               nrow(output_manifest)))
), use.names = TRUE)

print(tests)
if (!all(tests$passed)) {
  stop(sprintf("SINASC daily G1 validation failed %d/%d checks",
               sum(!tests$passed), nrow(tests)))
}
cat(sprintf("sinasc_daily_g1_validation_ok checks=%d status=%s\n",
            nrow(tests), overall_expected))
