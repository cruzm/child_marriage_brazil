#!/usr/bin/env Rscript
# Read-only acceptance checks for Gate G3. This validator consumes aggregate
# artifacts, manifests, logs, and raw-file hashes. It never reads person-level
# columns or re-estimates an outcome model.

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
analysis_dir <- file.path(root, "outputs", "analysis")
figure_dir <- file.path(root, "outputs", "figures")
log_dir <- file.path(root, "outputs", "logs")

paths <- c(
  schema = file.path(audit_dir, "SINASC_DAILY_G3_SCHEMA_AUDIT.csv"),
  reconciliation = file.path(audit_dir,
                             "SINASC_DAILY_G3_SAMPLE_RECONCILIATION.csv"),
  sample_audit = file.path(audit_dir, "SINASC_DAILY_G3_SAMPLE_AUDIT.csv"),
  software = file.path(audit_dir, "SINASC_DAILY_G3_SOFTWARE.csv"),
  model_registry = file.path(audit_dir,
                             "SINASC_DAILY_G3_MODEL_REGISTRY.csv"),
  gate = file.path(audit_dir, "SINASC_DAILY_G3_GATE_STATUS.csv"),
  primary = file.path(table_dir, "SINASC_DAILY_PRIMARY.csv"),
  secondary = file.path(table_dir, "SINASC_DAILY_SECONDARY.csv"),
  sensitivity = file.path(table_dir, "SINASC_DAILY_SENSITIVITY.csv"),
  rdrobust = file.path(table_dir, "SINASC_DAILY_RDROBUST.csv"),
  report = file.path(analysis_dir, "SINASC_DAILY_RESULTS.md"),
  rd_figure_pdf = file.path(figure_dir, "FIGURE_14_SINASC_DAILY_RD.pdf"),
  rd_figure_png = file.path(figure_dir, "FIGURE_14_SINASC_DAILY_RD.png"),
  sensitivity_figure_pdf = file.path(
    figure_dir, "FIGURE_SINASC_DAILY_G3_SENSITIVITY.pdf"
  ),
  sensitivity_figure_png = file.path(
    figure_dir, "FIGURE_SINASC_DAILY_G3_SENSITIVITY.png"
  ),
  manifest = file.path(audit_dir, "SINASC_DAILY_G3_OUTPUT_MANIFEST.csv")
)
if (!all(file.exists(paths))) {
  stop("Missing G3 artifact(s): ",
       paste(names(paths)[!file.exists(paths)], collapse = ", "))
}

schema <- fread(paths[["schema"]])
reconciliation <- fread(paths[["reconciliation"]])
sample_audit <- fread(paths[["sample_audit"]])
software <- fread(paths[["software"]])
model_registry <- fread(paths[["model_registry"]])
gate <- fread(paths[["gate"]])
primary <- fread(paths[["primary"]])
secondary <- fread(paths[["secondary"]])
sensitivity <- fread(paths[["sensitivity"]])
rdrobust <- fread(paths[["rdrobust"]])
manifest <- fread(paths[["manifest"]])
report_text <- paste(readLines(paths[["report"]], warn = FALSE),
                     collapse = "\n")

test <- function(name, condition, observed) {
  data.table(test = name, passed = isTRUE(condition),
             observed = paste(as.character(observed), collapse = ","))
}

near <- function(x, y, tolerance = 1e-8) {
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

valid_fixest_rows <- function(z) {
  all(z$identified) &&
    all(is.finite(z$estimate_pp)) &&
    all(is.finite(z$std_error_pp) & z$std_error_pp > 0) &&
    all(is.finite(z$p_value) & z$p_value >= 0 & z$p_value <= 1) &&
    all(z$ci95_low_pp <= z$ci90_low_pp &
          z$ci90_low_pp <= z$estimate_pp &
          z$estimate_pp <= z$ci90_high_pp &
          z$ci90_high_pp <= z$ci95_high_pp)
}

validate_prior_manifest <- function(path) {
  z <- fread(path)
  p <- file.path(root, z$artifact)
  if (!all(file.exists(p))) return(FALSE)
  actual <- vapply(p, digest, character(1), algo = "sha256", file = TRUE)
  identical(unname(actual), unname(z$sha256))
}

years <- c(2016:2018, 2022:2024)
bands <- c(30L, 60L, 90L, 180L)
sides <- c("below", "above")
expected_reconciliation <- CJ(year = years, bandwidth_days = bands,
                              side = sides, unique = TRUE)
expected_reconciliation[, era := ifelse(year <= 2018L, "pre", "post")]
setcolorder(expected_reconciliation,
            c("year", "era", "bandwidth_days", "side"))

# Frozen-document integrity and prior sequential gates.
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

g0_gate <- fread(file.path(audit_dir, "SINASC_DAILY_GATE_STATUS.csv"))
g1_gate <- fread(file.path(audit_dir, "SINASC_DAILY_G1_GATE_STATUS.csv"))
g2_gate <- fread(file.path(audit_dir, "SINASC_DAILY_G2_GATE_STATUS.csv"))
g0_status <- g0_gate[criterion == "G0_OVERALL", status]
g1_status <- g1_gate[criterion == "G1_OVERALL", status]
g2_status <- g2_gate[criterion == "G2_OVERALL", status]
prior_manifest_ok <- c(
  validate_prior_manifest(file.path(audit_dir,
                                    "SINASC_DAILY_G0_OUTPUT_MANIFEST.csv")),
  validate_prior_manifest(file.path(audit_dir,
                                    "SINASC_DAILY_G1_OUTPUT_MANIFEST.csv")),
  validate_prior_manifest(file.path(audit_dir,
                                    "SINASC_DAILY_G2_OUTPUT_MANIFEST.csv"))
)

# Raw-file hashes are checked without reading any microdata columns.
raw_manifest_lines <- readLines(file.path(
  root, "data", "raw_external", "sinasc", "SHA256_MANIFEST.txt"
), warn = FALSE)
raw_manifest <- data.table(
  expected_hash = sub("[[:space:]].*$", "", raw_manifest_lines),
  zip_file = sub("^[^[:space:]]+[[:space:]]+", "", raw_manifest_lines)
)
expected_files <- sprintf("SINASC_%d_csv.zip", years)
schema_hash <- merge(schema, raw_manifest[zip_file %in% expected_files],
                     by = "zip_file", all = TRUE)
schema_hash[, actual_hash := vapply(zip_file, function(f) {
  digest(file.path(root, "data", "raw_external", "sinasc", f),
         algo = "sha256", file = TRUE)
}, character(1))]

# Primary identities, multiplicity, and mechanical classification.
tau <- primary[estimand == "TAU"]
delay <- primary[estimand == "DELAY90"]
margin <- 0.25
expected_equiv <- primary$identified &
  primary$ci90_low_pp >= -margin & primary$ci90_high_pp <= margin
expected_holm <- p.adjust(setNames(primary$p_value, primary$estimand),
                          method = "holm")
p_named <- setNames(primary$p_value, primary$estimand)
ordered <- order(p_named, names(p_named), na.last = TRUE)
expected_rank <- rep(NA_integer_, 2L)
expected_rank[ordered] <- seq_along(ordered)
names(expected_rank) <- names(p_named)
expected_level <- 1 - 0.05 / (2 - expected_rank + 1)

expected_supported <- tau$identified && tau$ci95_low_pp > 0 &&
  tau$estimate_pp >= margin
expected_contrary <- tau$identified && tau$ci95_high_pp < 0
delay_holm_lower <- delay$holm_ci_low_pp
expected_delayed <- delay$identified && delay$estimate_pp > 0 &&
  expected_holm["DELAY90"] < 0.05 && delay_holm_lower > 0 &&
  !expected_supported
expected_profile <- expected_equiv[primary$estimand == "TAU"] &&
  expected_equiv[primary$estimand == "DELAY90"]
expected_no_jump <- expected_equiv[primary$estimand == "TAU"]
expected_class <- if (!tau$identified || !delay$identified) {
  "INCONCLUSIVE"
} else if (expected_supported) {
  "SUPPORTED_POSITIVE_EFFECT"
} else if (expected_contrary) {
  "CONTRARY_EFFECT"
} else if (expected_delayed) {
  "DELAYED_RESPONSE_SIGNAL"
} else if (expected_profile) {
  "INFORMATIVE_NO_LOCAL_PROFILE"
} else if (expected_no_jump) {
  "INFORMATIVE_NO_JUMP"
} else {
  "INCONCLUSIVE"
}

# Secondary family and frozen sensitivity grid.
expected_secondary_ids <- c("UNIAO_ESTAVEL", "ANY_UNION")
expected_sensitivity_ids <- c(
  "primary_h90", "bandwidth_h30", "bandwidth_h60", "bandwidth_h180",
  "vcov_distance", "vcov_hc1", "precision_region_race_fe",
  "quadratic_h180", "donut_d1", "donut_d3", "donut_d7",
  "sample_include_multiple", "sample_unknown_not_married"
)
primary_sensitivity <- sensitivity[specification_id == "primary_h90"]
donut_sensitivity <- sensitivity[specification_id %chin%
                                   c("donut_d1", "donut_d3", "donut_d7")]

# rdrobust fixed and automatic cross-check identities.
expected_rd_specs <- c("fixed_h30_b60", "fixed_h60_b120",
                       "fixed_h90_b180", "fixed_h180_b360",
                       "full_support_mserd")
rd_era <- rdrobust[row_type == "era_jump"]
rd_diff <- rdrobust[row_type == "post_minus_pre_point_only"]
rd_fixed <- rd_era[auto_bandwidth == FALSE]
rd_auto <- rd_era[auto_bandwidth == TRUE]
rd_difference_ok <- all(vapply(expected_rd_specs, function(s) {
  z <- rdrobust[specification_id == s]
  pre <- z[era == "pre", bias_corrected_jump_pp]
  post <- z[era == "post", bias_corrected_jump_pp]
  diff <- z[era == "post_minus_pre", post_minus_pre_bias_corrected_pp]
  length(pre) == 1L && length(post) == 1L && length(diff) == 1L &&
    near(diff, post - pre)
}, logical(1)))

# Model registry and overall decision.
expected_fixest_models <- c(
  "G3_PRIMARY_TAU", "G3_DELAY90", "G3_SECONDARY_UNIAO_ESTAVEL",
  "G3_SECONDARY_ANY_UNION", "G3_SENS_BW_030", "G3_SENS_BW_060",
  "G3_SENS_BW_180", "G3_SENS_VCOV_DISTANCE", "G3_SENS_VCOV_HC1",
  "G3_SENS_REGION_RACE_FE", "G3_SENS_QUADRATIC_H180",
  "G3_SENS_DONUT_01", "G3_SENS_DONUT_03", "G3_SENS_DONUT_07",
  "G3_SENS_INCLUDE_MULTIPLE", "G3_SENS_UNKNOWN_AS_NOT_MARRIED"
)
expected_rd_models <- as.vector(outer(
  c("H030", "H060", "H090", "H180", "AUTO"),
  c("PRE", "POST"),
  function(a, b) paste("G3_RDROBUST", a, b, sep = "_")
))
expected_models <- c(expected_fixest_models, expected_rd_models)
expected_causal_eligibility <- identical(g0_status, "PASS") &&
  identical(g1_status, "PASS") && identical(g2_status, "PASS") &&
  expected_class %chin% c("SUPPORTED_POSITIVE_EFFECT",
                          "INFORMATIVE_NO_LOCAL_PROFILE")
expected_paper_path <- if (expected_causal_eligibility) {
  "ELIGIBLE_TO_ADVANCE_AS_CAUSAL_CORE"
} else {
  "DO_NOT_ADVANCE_AS_CAUSAL_CORE"
}

# Manifest, binary signatures, and execution-log audit trail.
manifest_expected_rel <- sub(
  paste0("^", root, "/"), "", paths[names(paths) != "manifest"]
)
manifest_paths <- file.path(root, manifest$artifact)
manifest_actual <- vapply(manifest_paths, digest, character(1),
                          algo = "sha256", file = TRUE)
pdf_paths <- paths[grepl("_pdf$", names(paths))]
png_paths <- paths[grepl("_png$", names(paths))]
pdf_signatures <- vapply(pdf_paths, function(p) {
  rawToChar(readBin(p, "raw", n = 4L))
}, character(1))
png_signature_expected <- as.raw(c(0x89, 0x50, 0x4e, 0x47,
                                   0x0d, 0x0a, 0x1a, 0x0a))
png_signatures_ok <- all(vapply(png_paths, function(p) {
  identical(readBin(p, "raw", n = 8L), png_signature_expected)
}, logical(1)))
run_log <- paste(readLines(file.path(log_dir,
                                    "33_sinasc_daily_gate_g3.log"),
                           warn = FALSE), collapse = "\n")
attempt_logs <- file.path(log_dir, sprintf(
  "33_sinasc_daily_gate_g3_attempt%d.log", 1:3
))

software_rd <- software[component == "rdrobust"]
gate_status <- setNames(gate$status, gate$criterion)

tests <- rbindlist(list(
  test("all sixteen G3 artifacts exist", all(file.exists(paths)),
       length(paths)),
  test("frozen lock, protocol, and amendment hashes match registry",
       !anyNA(frozen_expected) &
         identical(unname(frozen_actual), unname(frozen_expected)),
       sprintf("%d/3", sum(frozen_actual == frozen_expected,
                            na.rm = TRUE))),
  test("prospective amendment A004 precedes the first G3 run",
       grepl("## A004 — Operational implementation of Gate G3",
             amendment_text, fixed = TRUE) &
         grepl("No SINASC G3 outcome model", amendment_text, fixed = TRUE),
       "A004"),
  test("prior G0, G1, and G2 verdicts are preserved",
       identical(g0_status, "PASS") & identical(g1_status, "PASS") &
         identical(g2_status, "QUALIFIED"),
       paste(g0_status, g1_status, g2_status, sep = ",")),
  test("all prior-gate output manifests remain unchanged",
       all(prior_manifest_ok), sprintf("%d/3", sum(prior_manifest_ok))),
  test("schema covers exactly the six frozen years and filenames",
       nrow(schema) == 6L & identical(schema$year, years) &
         identical(schema$zip_file, expected_files),
       paste(schema$year, collapse = ",")),
  test("raw hashes and required G3 schemas all revalidate",
       nrow(schema_hash) == 6L &
         all(schema_hash$raw_manifest_sha256_match) &
         all(schema_hash$g0_raw_sha256_match) &
         all(schema_hash$required_g3_schema_complete) &
         all(schema_hash$raw_sha256 == schema_hash$expected_hash) &
         all(schema_hash$raw_sha256 == schema_hash$actual_hash),
       sprintf("%d/6", sum(schema_hash$raw_sha256 ==
                              schema_hash$actual_hash))),
  test("schema counts are positive, nested, and calendar-bounded",
       all(schema$n_raw > schema$n_age15_16_valid_geography_candidates) &
         all(schema$n_age15_16_valid_geography_candidates >
               schema$n_locatable_age_agree) &
         all(schema$n_locatable_age_agree > schema$n_primary_valid_h180) &
         all(schema$full_support_min_days >= -366) &
         all(schema$full_support_max_days <= 366),
       sum(schema$n_locatable_age_agree)),
  test("sample reconciliation contains all 48 frozen G0 cells",
       nrow(reconciliation) == 48L &
         same_keys(reconciliation, expected_reconciliation,
                   c("year", "era", "bandwidth_days", "side")),
       nrow(reconciliation)),
  test("all G3 primary counts reproduce G0 exactly",
       all(reconciliation$birth_count_match) &
         all(reconciliation$married_count_match) &
         all(reconciliation$g3_n_births == reconciliation$g0_n_births) &
         all(reconciliation$g3_n_married_events ==
               reconciliation$g0_n_married_events),
       sprintf("birth=%d/48;married=%d/48",
               sum(reconciliation$birth_count_match),
               sum(reconciliation$married_count_match))),
  test("sample audit has four samples by era and side",
       nrow(sample_audit) == 16L &
         all(sample_audit[, .N, by = sample_id]$N == 4L),
       nrow(sample_audit)),
  test("sample audit and reconciliation respect small-cell privacy",
       all(is.na(sample_audit$n_married_events[
         sample_audit$privacy_suppressed_married])) &
         !any(sample_audit$n_married_events %between% c(1, 9),
              na.rm = TRUE) &
         !any(reconciliation$g3_n_married_events %between% c(1, 9),
              na.rm = TRUE),
       sum(sample_audit$privacy_suppressed_married)),
  test("primary table contains exactly TAU and DELAY90",
       nrow(primary) == 2L &
         identical(primary$estimand, c("TAU", "DELAY90")) &
         all(primary$outcome_id == "MARRIED"),
       paste(primary$estimand, collapse = ",")),
  test("both primary-family estimands identify with valid intervals",
       valid_fixest_rows(primary) & all(primary$n == 126138) &
         all(primary$n_outcome_events == 1342),
       sprintf("%d/2", sum(primary$identified))),
  test("DELAY90 equals TAU plus 45 times the slope kink",
       near(delay$estimate_pp,
            tau$estimate_pp + 45 * tau$slope_kink_phi_pp_per_day),
       delay$estimate_pp - tau$estimate_pp -
         45 * tau$slope_kink_phi_pp_per_day),
  test("MDE80 and relative magnitude recompute exactly",
       near(tau$mde80_pp, 2.8 * tau$std_error_pp) &
         near(tau$estimate_relative_to_pre_below_percent,
              100 * tau$estimate_pp /
                tau$pre_below_weighted_share_percent) &
         is.na(delay$mde80_pp) &
         is.na(delay$estimate_relative_to_pre_below_percent),
       paste(tau$mde80_pp,
             tau$estimate_relative_to_pre_below_percent, sep = ",")),
  test("Holm p-values across TAU and DELAY90 recompute",
       near(setNames(primary$p_value_holm_auxiliary_family,
                     primary$estimand), expected_holm),
       paste(primary$p_value_holm_auxiliary_family, collapse = ",")),
  test("Holm ranks and rank-specific confidence levels recompute",
       identical(setNames(primary$holm_rank, primary$estimand),
                 expected_rank) &
         near(setNames(primary$holm_confidence_level, primary$estimand),
              expected_level) &
         all(primary$holm_ci_low_pp <= primary$estimate_pp &
               primary$estimate_pp <= primary$holm_ci_high_pp),
       paste(primary$holm_confidence_level, collapse = ",")),
  test("equivalence and every classification condition recompute",
       identical(primary$equivalent_at_90pct, expected_equiv) &
         all(primary$supported_positive_condition == expected_supported) &
         all(primary$contrary_effect_condition == expected_contrary) &
         all(primary$delayed_response_condition == expected_delayed) &
         all(primary$informative_no_local_profile_condition ==
               expected_profile) &
         all(primary$informative_no_jump_condition == expected_no_jump),
       paste(expected_supported, expected_contrary, expected_delayed,
             expected_profile, expected_no_jump, sep = ",")),
  test("A004 precedence yields the reported G3 classification",
       all(primary$g3_classification == expected_class) &
         identical(gate_status[["G3_OVERALL"]], expected_class),
       expected_class),
  test("joint Wald test is finite and shared across estimands",
       all(is.finite(primary$joint_wald_statistic)) &
         all(is.finite(primary$joint_wald_p_value)) &
         all(primary$joint_wald_p_value >= 0 &
               primary$joint_wald_p_value <= 1) &
         all(primary$joint_wald_df1 == 2) &
         uniqueN(primary[, .(joint_wald_statistic, joint_wald_p_value,
                             joint_wald_df1, joint_wald_df2)]) == 1L,
       tau$joint_wald_p_value),
  test("secondary table contains exactly the frozen two-outcome family",
       nrow(secondary) == 2L &
         setequal(secondary$outcome_id, expected_secondary_ids) &
         all(secondary$multiplicity_family == "two_secondary_outcomes") &
         valid_fixest_rows(secondary),
       paste(secondary$outcome_id, collapse = ",")),
  test("secondary Holm adjustment and rejection flags recompute",
       near(secondary$p_value_holm,
            p.adjust(secondary$p_value, method = "holm")) &
         identical(secondary$rejects_raw_at_5pct,
                   secondary$p_value < 0.05) &
         identical(secondary$rejects_holm_at_5pct,
                   secondary$p_value_holm < 0.05),
       paste(secondary$p_value_holm, collapse = ",")),
  test("sensitivity table contains the complete thirteen-row frozen set",
       nrow(sensitivity) == 13L &
         !anyDuplicated(sensitivity$specification_id) &
         setequal(sensitivity$specification_id, expected_sensitivity_ids),
       nrow(sensitivity)),
  test("all frozen stacked sensitivities identify with valid intervals",
       valid_fixest_rows(sensitivity),
       sprintf("%d/13", sum(sensitivity$identified))),
  test("primary sensitivity row exactly reproduces TAU",
       nrow(primary_sensitivity) == 1L &
         near(primary_sensitivity$estimate_pp, tau$estimate_pp) &
         near(primary_sensitivity$std_error_pp, tau$std_error_pp) &
         near(primary_sensitivity$ci95_low_pp, tau$ci95_low_pp) &
         near(primary_sensitivity$ci95_high_pp, tau$ci95_high_pp),
       primary_sensitivity$estimate_pp),
  test("G1 heaping trigger displays all three diagnostic donuts",
       nrow(donut_sensitivity) == 3L &
         all(donut_sensitivity$heaping_detected_in_g1) &
         all(donut_sensitivity$diagnostic_cannot_rescue_gate) &
         setequal(donut_sensitivity$donut_days, c(1L, 3L, 7L)),
       paste(donut_sensitivity$donut_days, collapse = ",")),
  test("sample robustness checks expand the primary sample as frozen",
       sensitivity[specification_id == "sample_include_multiple", n] >
         tau$n &
         sensitivity[specification_id == "sample_unknown_not_married", n] >
         tau$n,
       paste(sensitivity[specification_id %chin%
                           c("sample_include_multiple",
                             "sample_unknown_not_married"), n],
             collapse = ",")),
  test("rdrobust table has ten era fits and five point differences",
       nrow(rdrobust) == 15L & nrow(rd_era) == 10L & nrow(rd_diff) == 5L &
         setequal(rdrobust$specification_id, expected_rd_specs) &
         all(rdrobust[, .N, by = specification_id]$N == 3L),
       paste(nrow(rd_era), nrow(rd_diff), sep = "+")),
  test("all rdrobust era fits use frozen settings and identify",
       all(rd_era$identified) & all(rd_era$p == 1L) & all(rd_era$q == 2L) &
         all(rd_era$kernel == "triangular") & all(rd_era$vce == "nn") &
         all(rd_era$nnmatch == 3L) & all(rd_era$masspoints == "adjust") &
         all(is.finite(rd_era$bias_corrected_jump_pp)) &
         all(is.finite(rd_era$robust_std_error_pp) &
               rd_era$robust_std_error_pp > 0) &
         all(rd_era$robust_ci95_low_pp <= rd_era$bias_corrected_jump_pp &
               rd_era$bias_corrected_jump_pp <=
                 rd_era$robust_ci95_high_pp),
       sprintf("%d/10", sum(rd_era$identified))),
  test("fixed rdrobust bandwidths use b equal to twice h",
       nrow(rd_fixed) == 8L &
         near(rd_fixed$requested_b_days, 2 * rd_fixed$requested_h_days) &
         near(rd_fixed$selected_h_left_days, rd_fixed$requested_h_days) &
         near(rd_fixed$selected_h_right_days, rd_fixed$requested_h_days) &
         near(rd_fixed$selected_b_left_days, rd_fixed$requested_b_days) &
         near(rd_fixed$selected_b_right_days, rd_fixed$requested_b_days),
       paste(unique(rd_fixed$requested_h_days), collapse = ",")),
  test("full-support rdrobust diagnostic uses mserd-selected bandwidths",
       nrow(rd_auto) == 2L & all(rd_auto$bandwidth_selector == "mserd") &
         all(is.na(rd_auto$requested_h_days)) &
         all(is.na(rd_auto$requested_b_days)) &
         all(is.finite(rd_auto$selected_h_left_days)) &
         all(is.finite(rd_auto$selected_b_left_days)),
       paste(round(rd_auto$selected_h_left_days, 3), collapse = ",")),
  test("rdrobust post-minus-pre rows are point comparisons only",
       rd_difference_ok & all(rd_diff$identified) &
         !any(rd_diff$difference_inference_available) &
         all(is.na(rd_diff$robust_std_error_pp)) &
         all(is.na(rd_diff$robust_ci95_low_pp)) &
         all(is.na(rd_diff$robust_ci95_high_pp)) &
         all(is.na(rd_diff$robust_p_value)),
       paste(round(rd_diff$post_minus_pre_bias_corrected_pp, 6),
             collapse = ",")),
  test("model registry contains all and only 26 fitted G3 models",
       nrow(model_registry) == 26L & !anyDuplicated(model_registry$model_id) &
         setequal(model_registry$model_id, expected_models) &
         model_registry[estimator == "fixest::feols", .N] == 16L &
         model_registry[estimator == "rdrobust::rdrobust", .N] == 10L,
       nrow(model_registry)),
  test("every registered G3 model is identified",
       all(model_registry$identified),
       sprintf("%d/26", sum(model_registry$identified))),
  test("software audit freezes rdrobust 3.0.0 and source hash",
       nrow(software_rd) == 1L & software_rd$version == "3.0.0" &
         software_rd$frozen_expected_version == "3.0.0" &
         software_rd$frozen_version_match &
         software_rd$source_sha256 ==
           "b1bcd0d6dae4ea0ceadf5fb3c2d62d787fb316c0a19c671c05b5db300d4b27a3",
       paste(software_rd$version, software_rd$source_sha256, sep = ":")),
  test("gate table preserves G2 and recomputes the paper-path decision",
       identical(gate_status[["G2_counterfactual"]], g2_status) &
         identical(gate_status[["CAUSAL_CORE_DECISION"]],
                   expected_paper_path),
       paste(g2_status, expected_paper_path, sep = ":")),
  test("report leads with G3 class, paper path, and qualified G2",
       grepl(sprintf("G3 classification: `%s`", expected_class),
             report_text, fixed = TRUE) &
         grepl(sprintf("Paper-path decision: `%s`", expected_paper_path),
               report_text, fixed = TRUE) &
         grepl("G2 remains `QUALIFIED`", report_text, fixed = TRUE) &
         grepl("does not meet the frozen conditions for an unconditional causal core",
               report_text, fixed = TRUE) &
         grepl("A004 fixed implementation details before this first G3 run",
               report_text, fixed = TRUE),
       paste(expected_class, expected_paper_path, sep = ":")),
  test("both G3 figures are nonempty valid PDF and PNG files",
       all(file.info(pdf_paths)$size > 10000) &
         all(file.info(png_paths)$size > 10000) &
         all(pdf_signatures == "%PDF") & png_signatures_ok,
       paste(file.info(c(pdf_paths, png_paths))$size, collapse = ",")),
  test("output manifest lists exactly the fifteen generated artifacts",
       nrow(manifest) == 15L & !anyDuplicated(manifest$artifact) &
         setequal(manifest$artifact, manifest_expected_rel) &
         all(manifest$scope ==
               "G3_full_frozen_analysis_post_result_protocol"),
       nrow(manifest)),
  test("output manifest hashes every listed G3 artifact",
       all(file.exists(manifest_paths)) &
         identical(unname(manifest_actual), unname(manifest$sha256)),
       sprintf("%d/15", sum(manifest_actual == manifest$sha256))),
  test("final log closes cleanly and three failed attempts are preserved",
       grepl("complete | G3=", run_log, fixed = TRUE) &
         grepl(expected_class, run_log, fixed = TRUE) &
         all(file.exists(attempt_logs)) &
         all(file.info(attempt_logs)$size > 0),
       sprintf("attempt_logs=%d", sum(file.exists(attempt_logs))))
), use.names = TRUE)

print(tests)
if (!all(tests$passed)) {
  stop(sprintf("SINASC daily G3 validation failed %d/%d checks",
               sum(!tests$passed), nrow(tests)))
}
cat(sprintf(
  "sinasc_daily_g3_validation_ok checks=%d classification=%s paper_path=%s\n",
  nrow(tests), expected_class, expected_paper_path
))
