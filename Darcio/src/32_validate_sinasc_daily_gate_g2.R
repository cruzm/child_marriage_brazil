#!/usr/bin/env Rscript
# Read-only acceptance checks for Gate G2. This validator consumes only public
# aggregate artifacts and manifests. It does not read person-level data, fit a
# model, or construct any G3 estimand.

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
table_dir <- file.path(root, "outputs", "tables")
paths <- c(
  schema = file.path(audit_dir, "SINASC_DAILY_G2_SCHEMA_AUDIT.csv"),
  sample_counts = file.path(audit_dir, "SINASC_DAILY_G2_SAMPLE_COUNTS.csv"),
  leap_exclusions = file.path(audit_dir,
                              "SINASC_DAILY_G2_LEAP_EXCLUSIONS.csv"),
  model_registry = file.path(audit_dir,
                             "SINASC_DAILY_G2_MODEL_REGISTRY.csv"),
  placebos = file.path(table_dir, "SINASC_DAILY_PLACEBOS.csv"),
  annual = file.path(table_dir, "SINASC_DAILY_G2_ANNUAL_JUMPS.csv"),
  leave_one_out = file.path(table_dir,
                            "SINASC_DAILY_G2_LEAVE_ONE_OUT.csv"),
  gate = file.path(audit_dir, "SINASC_DAILY_G2_GATE_STATUS.csv"),
  report = file.path(root, "outputs", "analysis",
                     "SINASC_DAILY_GATE_G2.md"),
  figure_pdf = file.path(root, "outputs", "figures",
                         "FIGURE_SINASC_DAILY_G2_ANNUAL_JUMPS.pdf"),
  figure_png = file.path(root, "outputs", "figures",
                         "FIGURE_SINASC_DAILY_G2_ANNUAL_JUMPS.png"),
  manifest = file.path(audit_dir, "SINASC_DAILY_G2_OUTPUT_MANIFEST.csv")
)
if (!all(file.exists(paths))) {
  stop("Missing G2 artifact(s): ",
       paste(names(paths)[!file.exists(paths)], collapse = ", "))
}

schema <- fread(paths[["schema"]])
sample_counts <- fread(paths[["sample_counts"]])
leap_exclusions <- fread(paths[["leap_exclusions"]])
model_registry <- fread(paths[["model_registry"]])
placebos <- fread(paths[["placebos"]])
annual <- fread(paths[["annual"]])
leave_one_out <- fread(paths[["leave_one_out"]])
gate <- fread(paths[["gate"]])
output_manifest <- fread(paths[["manifest"]])
report_text <- paste(readLines(paths[["report"]], warn = FALSE),
                     collapse = " ")

test <- function(name, condition, observed) {
  data.table(test = name, passed = isTRUE(condition),
             observed = paste(as.character(observed), collapse = ","))
}

near <- function(x, y, tolerance = 1e-9) {
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

valid_fit_rows <- function(z) {
  all(!z$identified |
        (is.finite(z$estimate_pp) & is.finite(z$std_error_pp) &
           z$std_error_pp > 0 & is.finite(z$p_value) & z$p_value >= 0 &
           z$p_value <= 1 & is.finite(z$ci90_low_pp) &
           is.finite(z$ci90_high_pp) & is.finite(z$ci95_low_pp) &
           is.finite(z$ci95_high_pp) &
           z$ci95_low_pp <= z$ci90_low_pp &
           z$ci90_low_pp <= z$estimate_pp &
           z$estimate_pp <= z$ci90_high_pp &
           z$ci90_high_pp <= z$ci95_high_pp))
}

historical_years <- 2013:2014
primary_pre_years <- 2016:2018
transition_years <- 2019L
pandemic_years <- 2020:2021
primary_post_years <- 2022:2024
analysis_years <- c(historical_years, primary_pre_years, transition_years,
                    pandemic_years, primary_post_years)
primary_years <- c(primary_pre_years, primary_post_years)
placebo_ages <- c(15L, 17L, 19L)
margin_pp <- 0.25

expected_pairs <- rbindlist(list(
  data.table(year = analysis_years, cutoff_age = 16L),
  CJ(year = primary_years, cutoff_age = placebo_ages, unique = TRUE)
), use.names = TRUE)
expected_cells <- expected_pairs[, .(side = c("below", "above")),
                                 by = .(year, cutoff_age)]
expected_files <- ifelse(
  analysis_years <= 2015L,
  sprintf("DNBR%d_csv.zip", analysis_years),
  sprintf("SINASC_%d_csv.zip", analysis_years)
)

# Frozen lock and sequential precondition integrity.
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
amendment_text <- paste(readLines(file.path(
  root, "paper", "ledgers", "SINASC_DAILY_AMENDMENTS.md"
), warn = FALSE), collapse = "\n")

validate_prior_manifest <- function(path) {
  z <- fread(path)
  p <- file.path(root, z$artifact)
  actual <- vapply(p, digest, character(1), algo = "sha256", file = TRUE)
  all(file.exists(p)) && identical(unname(actual), unname(z$sha256))
}
g0_gate <- fread(file.path(audit_dir, "SINASC_DAILY_GATE_STATUS.csv"))
g1_gate <- fread(file.path(audit_dir,
                           "SINASC_DAILY_G1_GATE_STATUS.csv"))
g0_manifest_ok <- validate_prior_manifest(file.path(
  audit_dir, "SINASC_DAILY_G0_OUTPUT_MANIFEST.csv"
))
g1_manifest_ok <- validate_prior_manifest(file.path(
  audit_dir, "SINASC_DAILY_G1_OUTPUT_MANIFEST.csv"
))

# Recompute raw hashes from the immutable annual ZIPs.
raw_manifest_lines <- readLines(file.path(
  root, "data", "raw_external", "sinasc", "SHA256_MANIFEST.txt"
), warn = FALSE)
raw_manifest <- data.table(
  expected_hash = sub("[[:space:]].*$", "", raw_manifest_lines),
  zip_file = sub("^[^[:space:]]+[[:space:]]+", "", raw_manifest_lines)
)
schema_hash_check <- merge(
  schema,
  raw_manifest[zip_file %in% expected_files],
  by = "zip_file", all = TRUE
)
schema_hash_check[, actual_hash := vapply(zip_file, function(f) {
  digest(file.path(root, "data", "raw_external", "sinasc", f),
         algo = "sha256", file = TRUE)
}, character(1))]

# Sample-count consistency and privacy.
published_cells <- sample_counts[privacy_suppressed_married == FALSE]
published_positive <- published_cells[n_births > 0]
sample_share_ok <- near(
  published_positive$married_share_percent,
  100 * published_positive$n_married_events /
    published_positive$n_births
)
primary_reconciliation <- sample_counts[g0_reference_applicable == TRUE]
nonprimary_reconciliation <- sample_counts[g0_reference_applicable == FALSE]

sample_n <- function(years, cutoff) {
  sample_counts[year %in% years & cutoff_age == cutoff, sum(n_births)]
}

# Binding-placebo logic from A003.
placebos[, expected_equivalent := identified &
           ci90_low_pp >= -margin_pp & ci90_high_pp <= margin_pp]
placebos[, expected_raw_reject := identified & p_value < 0.05]
placebos[, expected_magnitude := identified & abs(estimate_pp) >= margin_pp]
temporal <- placebos[test_family == "temporal_placebo"]
age_placebos <- placebos[test_family == "age_placebo"]
age_placebos[, expected_holm := p.adjust(p_value, method = "holm")]

temporal_fail <- temporal$identified &
  (temporal$ci95_low_pp > 0 | temporal$ci95_high_pp < 0) &
  abs(temporal$estimate_pp) >= margin_pp
temporal_pass <- temporal$identified & temporal$expected_equivalent
temporal_status <- if (temporal_pass) {
  "PASS"
} else if (temporal_fail) {
  "FAIL"
} else {
  "QUALIFIED"
}

age_reject_holm <- age_placebos$identified &
  age_placebos$expected_holm < 0.05
age_large <- age_placebos$identified &
  abs(age_placebos$estimate_pp) >= margin_pp
age_fail_large <- any(age_reject_holm & age_large)
age_fail_two <- sum(age_reject_holm) >= 2L
age_fail <- age_fail_large || age_fail_two
age_pass <- all(age_placebos$identified) &&
  all(age_placebos$expected_equivalent)
age_status <- if (age_fail) {
  "FAIL"
} else if (age_pass) {
  "PASS"
} else {
  "QUALIFIED"
}

# Annual and leave-one-out identities and sample sizes.
expected_period <- fifelse(
  analysis_years %in% historical_years, "historical_pre",
  fifelse(analysis_years %in% primary_pre_years, "primary_pre",
          fifelse(analysis_years %in% transition_years, "transition",
                  fifelse(analysis_years %in% pandemic_years, "pandemic",
                          "mature_post")))
)
annual_expected <- data.table(year = analysis_years,
                              period_label = expected_period)
annual_n_expected <- vapply(annual$year, function(y) {
  sample_n(y, 16L)
}, numeric(1))

loo_expected <- CJ(omitted_pre_year = primary_pre_years,
                   omitted_post_year = primary_post_years, unique = TRUE)
loo_n_expected <- vapply(seq_len(nrow(leave_one_out)), function(i) {
  z <- leave_one_out[i]
  kept <- c(setdiff(primary_pre_years, z$omitted_pre_year),
            setdiff(primary_post_years, z$omitted_post_year))
  sample_n(kept, 16L)
}, numeric(1))
loo_year_strings_ok <- all(vapply(seq_len(nrow(leave_one_out)), function(i) {
  z <- leave_one_out[i]
  identical(z$reference_years,
            paste(setdiff(primary_pre_years, z$omitted_pre_year),
                  collapse = ",")) &&
    identical(z$comparison_years,
              paste(setdiff(primary_post_years, z$omitted_post_year),
                    collapse = ","))
}, logical(1)))

registry_expected_ids <- c(
  "temporal_placebo_age16",
  paste0("age_placebo_", placebo_ages),
  paste0("annual_age16_", analysis_years),
  unlist(lapply(primary_pre_years, function(pre) {
    paste0("loo_pre", pre, "_post", primary_post_years)
  }))
)
result_identification <- rbindlist(list(
  placebos[, .(model_id, result_identified = identified)],
  annual[, .(model_id, result_identified = identified)],
  leave_one_out[, .(model_id, result_identified = identified)]
))
registry_check <- merge(model_registry, result_identification,
                        by = "model_id", all = TRUE)

stability_identified <- all(annual$identified) &&
  all(leave_one_out$identified)
overall_expected <- if (temporal_status == "FAIL" || age_status == "FAIL") {
  "FAIL"
} else if (temporal_status == "PASS" && age_status == "PASS" &&
           stability_identified) {
  "PASS"
} else {
  "QUALIFIED"
}
gate_expected_status <- c(
  G0_G1_preconditions = "PASS",
  temporal_placebo_age16 = temporal_status,
  placebo_age_family = age_status,
  annual_jump_diagnostics = ifelse(all(annual$identified),
                                   "DIAGNOSTIC_COMPLETE", "QUALIFIED"),
  leave_one_out_diagnostics = ifelse(all(leave_one_out$identified),
                                     "DIAGNOSTIC_COMPLETE", "QUALIFIED"),
  G2_OVERALL = overall_expected
)
gate_expected_failures <- c(
  G0_G1_preconditions = 0L,
  temporal_placebo_age16 = as.integer(temporal_fail),
  placebo_age_family = as.integer(age_fail),
  annual_jump_diagnostics = 0L,
  leave_one_out_diagnostics = 0L,
  G2_OVERALL = sum(c(temporal_fail, age_fail))
)
gate_reported_status <- setNames(gate$status, gate$criterion)
gate_reported_failures <- setNames(gate$binding_failures, gate$criterion)

# Output-manifest and figure integrity.
manifest_expected_rel <- sub(
  paste0("^", root, "/"), "", paths[names(paths) != "manifest"]
)
manifest_paths <- file.path(root, output_manifest$artifact)
manifest_actual_hash <- vapply(manifest_paths, digest, character(1),
                               algo = "sha256", file = TRUE)
pdf_signature <- rawToChar(readBin(paths[["figure_pdf"]], "raw", n = 4L))
png_signature <- readBin(paths[["figure_png"]], "raw", n = 8L)
expected_png_signature <- as.raw(c(0x89, 0x50, 0x4e, 0x47,
                                   0x0d, 0x0a, 0x1a, 0x0a))

tests <- rbindlist(list(
  test("all twelve G2 artifacts exist", all(file.exists(paths)),
       length(paths)),
  test("frozen lock, protocol, and amendment hashes match registry",
       !anyNA(frozen_expected) &
         identical(unname(frozen_actual), unname(frozen_expected)),
       sprintf("%d/3", sum(frozen_actual == frozen_expected,
                            na.rm = TRUE))),
  test("prospective amendment A003 is present",
       grepl("## A003 — Operational implementation of Gate G2",
             amendment_text, fixed = TRUE) &
         grepl("before its first run", amendment_text, fixed = TRUE),
       "A003"),
  test("G0 and G1 preconditions remain PASS",
       identical(g0_gate[criterion == "G0_OVERALL", status], "PASS") &
         identical(g1_gate[criterion == "G1_OVERALL", status], "PASS"),
       paste(g0_gate[criterion == "G0_OVERALL", status],
             g1_gate[criterion == "G1_OVERALL", status], sep = ",")),
  test("G0 and G1 artifact manifests remain unchanged",
       g0_manifest_ok & g1_manifest_ok,
       paste(g0_manifest_ok, g1_manifest_ok, sep = ",")),
  test("schema covers exactly the eleven required years and filenames",
       nrow(schema) == 11L & identical(schema$year, analysis_years) &
         identical(schema$zip_file, expected_files),
       paste(schema$year, collapse = ",")),
  test("all raw ZIP hashes and required schemas revalidate",
       nrow(schema_hash_check) == 11L &
         all(schema_hash_check$raw_manifest_sha256_match) &
         all(schema_hash_check$required_g2_schema_complete) &
         all(schema_hash_check$raw_sha256 == schema_hash_check$expected_hash) &
         all(schema_hash_check$raw_sha256 == schema_hash_check$actual_hash),
       sprintf("%d/11", sum(schema_hash_check$raw_sha256 ==
                               schema_hash_check$actual_hash))),
  test("schema counts are positive and nested",
       all(schema$n_raw > schema$n_pre_date_candidates) &
         all(schema$n_pre_date_candidates > 0) &
         all(schema$n_retained_h90_across_required_cutoffs > 0),
       sum(schema$n_retained_h90_across_required_cutoffs)),
  test("sample audit has exactly 58 required year-cutoff-side cells",
       nrow(sample_counts) == 58L &
         same_keys(sample_counts, expected_cells,
                   c("year", "cutoff_age", "side")),
       nrow(sample_counts)),
  test("sample birth counts are nonnegative integers",
       all(is.finite(sample_counts$n_births)) &
         all(sample_counts$n_births >= 0) &
         all(sample_counts$n_births == floor(sample_counts$n_births)),
       sum(sample_counts$n_births)),
  test("published married counts and shares respect small-cell privacy",
       all(is.na(sample_counts$n_married_events[
         sample_counts$privacy_suppressed_married])) &
         all(is.na(sample_counts$married_share_percent[
           sample_counts$privacy_suppressed_married])) &
         !any(sample_counts$n_married_events %between% c(1, 9),
              na.rm = TRUE) & sample_share_ok,
       sum(sample_counts$privacy_suppressed_married)),
  test("twelve primary age-16 cells reproduce G0 exactly",
       nrow(primary_reconciliation) == 12L &
         all(primary_reconciliation$g0_birth_count_match) &
         all(primary_reconciliation$g0_married_count_match) &
         all(primary_reconciliation$n_births ==
               primary_reconciliation$g0_n_births) &
         all(primary_reconciliation$n_married_events ==
               primary_reconciliation$g0_n_married_events),
       nrow(primary_reconciliation)),
  test("G0 references are absent outside primary age-16 cells",
       all(is.na(nonprimary_reconciliation$g0_n_births)) &
         all(is.na(nonprimary_reconciliation$g0_n_married_events)) &
         all(is.na(nonprimary_reconciliation$g0_birth_count_match)) &
         all(is.na(nonprimary_reconciliation$g0_married_count_match)),
       nrow(nonprimary_reconciliation)),
  test("leap audit covers all 29 required year-cutoff pairs",
       nrow(leap_exclusions) == 29L &
         same_keys(leap_exclusions, expected_pairs,
                   c("year", "cutoff_age")),
       nrow(leap_exclusions)),
  test("all impossible placebo anniversaries are February 29",
       all(leap_exclusions$n_other_impossible == 0L) &
         all(leap_exclusions$n_impossible_anniversary_excluded ==
               leap_exclusions$n_explained_feb29) &
         all(leap_exclusions$n_age_pair_exact_candidates >=
               leap_exclusions$n_impossible_anniversary_excluded) &
         all(leap_exclusions[cutoff_age == 16L,
                             n_impossible_anniversary_excluded == 0L]),
       sum(leap_exclusions$n_impossible_anniversary_excluded)),
  test("model registry contains exactly the 24 frozen G2 models",
       nrow(model_registry) == 24L &
         !anyDuplicated(model_registry$model_id) &
         setequal(model_registry$model_id, registry_expected_ids) &
         model_registry[test_family == "temporal_placebo", .N] == 1L &
         model_registry[test_family == "age_placebo", .N] == 3L &
         model_registry[test_family == "annual_jump_diagnostic", .N] == 11L &
         model_registry[test_family == "leave_one_out_diagnostic", .N] == 9L,
       nrow(model_registry)),
  test("registry excludes the full primary model and every G3 estimand",
       !any(model_registry$full_primary_age16_policy_model) &
         !any(model_registry$g3_estimand) &
         !any(model_registry$cutoff_age == 16L &
                model_registry$reference_years == "2016,2017,2018" &
                model_registry$comparison_years == "2022,2023,2024"),
       sum(model_registry$g3_estimand)),
  test("model registry identification agrees with result tables",
       nrow(registry_check) == 24L &
         identical(registry_check$identified,
                   registry_check$result_identified),
       sprintf("%d/24", sum(registry_check$identified ==
                               registry_check$result_identified))),
  test("canonical placebo table has one temporal and three age rows",
       nrow(placebos) == 4L & nrow(temporal) == 1L &
         setequal(age_placebos$cutoff_age, placebo_ages) &
         all(placebos$bandwidth_days == 90L),
       nrow(placebos)),
  test("placebo model sample sizes recover public sample counts",
       temporal$n == sample_n(c(historical_years, primary_pre_years), 16L) &
         all(vapply(seq_len(nrow(age_placebos)), function(i) {
           age_placebos$n[i] == sample_n(primary_years,
                                         age_placebos$cutoff_age[i])
         }, logical(1))),
       sum(placebos$n)),
  test("all binding placebo estimates and intervals are identified and valid",
       all(placebos$identified) & valid_fit_rows(placebos),
       sprintf("%d/4", sum(placebos$identified))),
  test("all model-level married counts respect privacy suppression",
       all(unlist(lapply(list(placebos, annual, leave_one_out), function(z) {
         all(is.na(z$n_married[z$privacy_suppressed_n_married])) &&
           !any(z$n_married %between% c(1, 9), na.rm = TRUE)
       }))),
       sum(c(placebos$privacy_suppressed_n_married,
             annual$privacy_suppressed_n_married,
             leave_one_out$privacy_suppressed_n_married))),
  test("placebo equivalence, magnitude, and raw rejection flags recompute",
       near(placebos$equivalence_margin_pp,
            rep(margin_pp, nrow(placebos))) &
         identical(placebos$equivalent_at_90pct,
                   placebos$expected_equivalent) &
         identical(placebos$rejects_raw_at_5pct,
                   placebos$expected_raw_reject) &
         identical(placebos$magnitude_at_least_margin,
                   placebos$expected_magnitude),
       sum(placebos$expected_equivalent)),
  test("Holm adjustment across exactly three placebo ages recomputes",
       all(is.na(temporal$p_value_holm)) &
         near(age_placebos$p_value_holm, age_placebos$expected_holm) &
         identical(age_placebos$rejects_holm_at_5pct,
                   age_reject_holm),
       sum(age_reject_holm)),
  test("temporal placebo decision recomputes from frozen rules",
       identical(temporal$binding_failure, temporal_fail) &
         identical(temporal$family_status, temporal_status),
       temporal_status),
  test("age-placebo family decision recomputes from A003",
       all(age_placebos$family_status == age_status) &
         identical(age_placebos$binding_failure,
                   (age_reject_holm & age_large) | age_fail_two),
       age_status),
  test("annual table contains the eleven required classified years",
       nrow(annual) == 11L &
         same_keys(annual, annual_expected, c("year", "period_label")) &
         all(annual$cutoff_age == 16L) &
         all(annual$bandwidth_days == 90L),
       paste(annual$year, collapse = ",")),
  test("annual models are identified, valid, and recover sample sizes",
       all(annual$identified) & valid_fit_rows(annual) &
         near(annual$n, annual_n_expected),
       sprintf("%d/11", sum(annual$identified))),
  test("leave-one-out table has every 3 by 3 omission pair",
       nrow(leave_one_out) == 9L &
         same_keys(leave_one_out, loo_expected,
                   c("omitted_pre_year", "omitted_post_year")) &
         loo_year_strings_ok &
         all(leave_one_out$cutoff_age == 16L) &
         all(leave_one_out$bandwidth_days == 90L),
       nrow(leave_one_out)),
  test("leave-one-out models identify and recover their sample sizes",
       all(leave_one_out$identified) & valid_fit_rows(leave_one_out) &
         near(leave_one_out$n, loo_n_expected),
       sprintf("%d/9", sum(leave_one_out$identified))),
  test("G2 gate statuses and failure counts recompute mechanically",
       identical(unname(gate_reported_status[names(gate_expected_status)]),
                 unname(gate_expected_status)) &
         identical(as.numeric(gate_reported_failures[
           names(gate_expected_failures)]),
           as.numeric(gate_expected_failures)),
       overall_expected),
  test("report records verdict, A003, and exclusive G2 scope",
       grepl(sprintf("Status: %s", overall_expected), report_text,
             fixed = TRUE) &
         grepl("prospective amendment A003", report_text, fixed = TRUE) &
         grepl("does not estimate the full primary age-16 pre-versus-post coefficient",
               report_text, fixed = TRUE) &
         grepl("No G3 model was run", report_text, fixed = TRUE),
       overall_expected),
  test("annual-jump figures are nonempty PDF and PNG files",
       file.info(paths[["figure_pdf"]])$size > 10000 &
         file.info(paths[["figure_png"]])$size > 10000 &
         identical(pdf_signature, "%PDF") &
         identical(png_signature, expected_png_signature),
       sprintf("pdf=%d;png=%d",
               file.info(paths[["figure_pdf"]])$size,
               file.info(paths[["figure_png"]])$size)),
  test("output manifest lists exactly the eleven generated artifacts",
       nrow(output_manifest) == 11L &
         !anyDuplicated(output_manifest$artifact) &
         setequal(output_manifest$artifact, manifest_expected_rel) &
         all(output_manifest$scope ==
               "G2_only_no_full_primary_or_G3_estimation"),
       nrow(output_manifest)),
  test("output manifest hashes every listed G2 artifact",
       all(file.exists(manifest_paths)) &
         identical(unname(manifest_actual_hash),
                   unname(output_manifest$sha256)),
       sprintf("%d/%d", sum(manifest_actual_hash ==
                               output_manifest$sha256),
               nrow(output_manifest)))
), use.names = TRUE)

print(tests)
if (!all(tests$passed)) {
  stop(sprintf("SINASC daily G2 validation failed %d/%d checks",
               sum(!tests$passed), nrow(tests)))
}
cat(sprintf("sinasc_daily_g2_validation_ok checks=%d status=%s\n",
            nrow(tests), overall_expected))
