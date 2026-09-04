#!/usr/bin/env Rscript
# Acceptance checks for the complete local Registry/SAR R0 package.

options(stringsAsFactors = FALSE)
cwd <- normalizePath(getwd(), mustWork = TRUE)
root <- if (file.exists(file.path(cwd, "config", "registry_sar_r0_lock.yml"))) {
  cwd
} else {
  file.path(cwd, "Darcio")
}
if (!dir.exists(root)) stop("Cannot locate the Darcio project directory")

.libPaths(c(file.path(root, "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(digest)
  library(yaml)
})

lock <- read_yaml(file.path(root, "config", "registry_sar_r0_lock.yml"))
audit_dir <- file.path(root, "outputs", "audit")
analysis_dir <- file.path(root, "outputs", "analysis")
data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
log_dir <- file.path(root, "outputs", "logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
log_path <- file.path(log_dir, "38_validate_registry_sar_r0.log")

paths <- c(
  hashes = file.path(root, "paper", "ledgers", "REGISTRY_SAR_R0_LOCK_SHA256.txt"),
  inquiry = file.path(root, "paper", "ledgers", "IBGE_SAR_TECHNICAL_INQUIRY_READY.md"),
  input = file.path(audit_dir, "REGISTRY_SAR_R0_INPUT_AUDIT.csv"),
  denominator = file.path(audit_dir, "REGISTRY_SAR_R0_DENOMINATOR_AUDIT.csv"),
  local_tests = file.path(audit_dir, "REGISTRY_SAR_R0_LOCAL_COMPONENT_TESTS.csv"),
  external = file.path(audit_dir, "REGISTRY_SAR_R0_EXTERNAL_CHECKLIST.csv"),
  schema_audit = file.path(audit_dir, "REGISTRY_SAR_R0_SYNTHETIC_SCHEMA_AUDIT.csv"),
  software = file.path(audit_dir, "REGISTRY_SAR_R0_SOFTWARE.csv"),
  gate = file.path(audit_dir, "REGISTRY_SAR_R0_GATE_STATUS.csv"),
  exposure = file.path(data_dir, "REGISTRY_SAR_R0_PNADC_EXPOSURE.csv"),
  dictionary = file.path(data_dir, "REGISTRY_SAR_R0_PNADC_EXPOSURE_DICTIONARY.csv"),
  synthetic = file.path(data_dir, "REGISTRY_SAR_R0_SYNTHETIC_CELLS.csv.gz"),
  power = file.path(table_dir, "REGISTRY_SAR_R0_POWER_ENVELOPE.csv"),
  recovery = file.path(table_dir, "REGISTRY_SAR_R0_SYNTHETIC_RECOVERY.csv"),
  report = file.path(analysis_dir, "REGISTRY_SAR_R0_RESULTS.md"),
  manifest = file.path(audit_dir, "REGISTRY_SAR_R0_OUTPUT_MANIFEST.csv")
)
if (!all(file.exists(paths))) {
  stop("Missing R0 artifact(s): ", paste(names(paths)[!file.exists(paths)],
                                          collapse = ", "))
}

input <- fread(paths[["input"]])
denominator <- fread(paths[["denominator"]])
local_tests <- fread(paths[["local_tests"]])
external <- fread(paths[["external"]])
schema_audit <- fread(paths[["schema_audit"]])
gate <- fread(paths[["gate"]])
exposure <- fread(paths[["exposure"]])
dictionary <- fread(paths[["dictionary"]])
synthetic <- fread(paths[["synthetic"]])
power <- fread(paths[["power"]])
recovery <- fread(paths[["recovery"]])
manifest <- fread(paths[["manifest"]])
report_lines <- readLines(paths[["report"]], warn = FALSE)
inquiry_lines <- readLines(paths[["inquiry"]], warn = FALSE)
hash_lines <- readLines(paths[["hashes"]], warn = FALSE)

test <- function(name, condition, observed) {
  data.table(test = name, passed = isTRUE(condition), observed = as.character(observed))
}
expected_hash <- function(relative_path) {
  hit <- grep(paste0(relative_path, "$"), hash_lines, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub("[[:space:]].*$", "", hit)
}
hash_ok <- function(relative_path) {
  path <- file.path(root, relative_path)
  file.exists(path) && identical(
    digest(path, algo = "sha256", file = TRUE), expected_hash(relative_path)
  )
}

manifest_paths <- file.path(root, manifest$artifact)
manifest_actual <- vapply(manifest_paths, digest, character(1),
                          algo = "sha256", file = TRUE)
base <- lock$power$base_screen
stress <- lock$power$stress_screen
base_row <- power[
  sex == base$sex & bandwidth_days == as.integer(base$bandwidth_days) &
    abs(allocation_multiplier - as.numeric(base$allocation_multiplier)) < 1e-12 &
    abs(variance_inflation_factor -
          as.numeric(base$variance_inflation_factor)) < 1e-12
]
stress_row <- power[
  sex == stress$sex & bandwidth_days == as.integer(stress$bandwidth_days) &
    abs(allocation_multiplier - as.numeric(stress$allocation_multiplier)) < 1e-12 &
    abs(variance_inflation_factor -
          as.numeric(stress$variance_inflation_factor)) < 1e-12
]

required_exposure <- c(
  "year", "quarter", "quarter_start", "days_in_quarter", "geography",
  "age", "side", "sex", "population_stock", "population_stock_se",
  "unweighted_n", "population_cv", "exact_age_day_stock",
  "exact_age_day_stock_se", "population_person_time",
  "population_person_time_se", "denominator_source", "approximation"
)
required_synthetic <- c(
  "celebration_period", "age_distance_day", "below16", "post_law", "sex",
  "marriage_events", "population_person_time", "synthetic"
)
forbidden_names <- c("name", "nome", "cpf", "rg", "address", "endereco",
                     "event_key", "birth_date", "celebration_date")
external_statuses <- c("PENDING_IBGE", "PENDING_USER")

expected_power_rows <- length(unique(power$sex)) *
  length(unlist(lock$power$bandwidth_days)) *
  length(unlist(lock$power$within_age_allocation_multipliers)) *
  length(unlist(lock$power$variance_inflation_factors))

tests <- rbindlist(list(
  test("all sixteen required R0 artifacts exist", all(file.exists(paths)),
       length(paths)),
  test("four frozen lock hashes pass",
       all(vapply(c(
         "config/registry_sar_r0_lock.yml",
         "config/registry_sar_canonical_schema.csv",
         "paper/ledgers/REGISTRY_SAR_R0_PROTOCOL.md",
         "paper/ledgers/REGISTRY_SAR_R0_AMENDMENTS.md"
       ), hash_ok, logical(1))), "4/4"),
  test("public input audit passes existence and schema",
       all(input$exists & input$schema_complete),
       sprintf("%d/%d", sum(input$exists & input$schema_complete), nrow(input))),
  test("all local component tests pass", all(local_tests$passed),
       sprintf("%d/%d", sum(local_tests$passed), nrow(local_tests))),
  test("all denominator criteria pass", all(denominator$passed),
       sprintf("%d/%d", sum(denominator$passed), nrow(denominator))),
  test("exposure schema is complete", all(required_exposure %in% names(exposure)),
       paste(names(exposure), collapse = ",")),
  test("exposure has exactly 288 national quarterly cells",
       nrow(exposure) == 288L && uniqueN(exposure[, .(year, quarter)]) == 48L &&
         setequal(exposure$age, c(15L, 16L)) &&
         setequal(exposure$sex, c("combined", "female", "male")),
       sprintf("rows=%d periods=%d", nrow(exposure),
               uniqueN(exposure[, .(year, quarter)]))),
  test("exposure cells are unique and positive",
       !anyDuplicated(exposure, by = c("year", "quarter", "age", "sex")) &&
         all(is.finite(exposure$population_person_time) &
               exposure$population_person_time > 0),
       anyDuplicated(exposure, by = c("year", "quarter", "age", "sex"))),
  test("exposure contains no direct identifiers",
       !any(tolower(names(exposure)) %in% forbidden_names),
       paste(names(exposure), collapse = ",")),
  test("exposure dictionary covers every field",
       setequal(dictionary$variable, names(exposure)) &&
         all(dictionary$restricted == FALSE),
       sprintf("%d/%d", nrow(dictionary), ncol(exposure))),
  test("power grid is complete", nrow(power) == expected_power_rows,
       sprintf("%d/%d", nrow(power), expected_power_rows)),
  test("power grid is planning-only", all(power$planning_only),
       sum(power$planning_only)),
  test("base power screen provisionally passes",
       nrow(base_row) == 1L && base_row$mde_decline_percent <=
         as.numeric(base$maximum_decline_mde_percent),
       if (nrow(base_row)) base_row$mde_decline_percent else NA),
  test("stress power screen provisionally passes",
       nrow(stress_row) == 1L && stress_row$mde_decline_percent <=
         as.numeric(stress$maximum_decline_mde_percent),
       if (nrow(stress_row)) stress_row$mde_decline_percent else NA),
  test("synthetic schema is complete", all(required_synthetic %in% names(synthetic)),
       paste(names(synthetic), collapse = ",")),
  test("every dry-run row is marked synthetic", all(synthetic$synthetic),
       sprintf("%d/%d", sum(synthetic$synthetic), nrow(synthetic))),
  test("synthetic cells contain no direct identifiers",
       !any(tolower(names(synthetic)) %in% forbidden_names),
       paste(names(synthetic), collapse = ",")),
  test("all synthetic schema checks pass", all(schema_audit$passed),
       sprintf("%d/%d", sum(schema_audit$passed), nrow(schema_audit))),
  test("synthetic recovery is unique and passes",
       nrow(recovery) == 1L && recovery$synthetic && recovery$recovery_pass,
       if (nrow(recovery)) recovery$absolute_error_log_points else NA),
  test("synthetic truth is within frozen tolerance",
       abs(recovery$estimated_log_irr - recovery$true_log_irr) <=
         as.numeric(lock$synthetic_dry_run$coefficient_tolerance_log_points),
       recovery$absolute_error_log_points),
  test("synthetic truth lies in 95 percent interval",
       recovery$ci95_low <= recovery$true_log_irr &&
         recovery$ci95_high >= recovery$true_log_irr,
       sprintf("[%.6f,%.6f] truth=%.6f", recovery$ci95_low,
               recovery$ci95_high, recovery$true_log_irr)),
  test("all external checks remain pending",
       all(external$current_status %in% external_statuses) &&
         all(external$blocking),
       paste(unique(external$current_status), collapse = ",")),
  test("no external response evidence is fabricated",
       all(is.na(external$evidence_after_response) |
             external$evidence_after_response == ""),
       sum(!is.na(external$evidence_after_response) &
             external$evidence_after_response != "")),
  test("technical inquiry is explicitly ready and unsent",
       any(grepl("READY_NOT_SENT", inquiry_lines, fixed = TRUE)) &&
         any(grepl("No request has been transmitted", inquiry_lines,
                   fixed = TRUE)),
       "READY_NOT_SENT"),
  test("local overall status is bounded",
       gate[gate == "R0_LOCAL_OVERALL", status] ==
         "LOCAL_READY_EXTERNAL_PENDING",
       gate[gate == "R0_LOCAL_OVERALL", status]),
  test("causal identification remains not evaluated",
       gate[gate == "CAUSAL_IDENTIFICATION", status] == "NOT_EVALUATED",
       gate[gate == "CAUSAL_IDENTIFICATION", status]),
  test("no causal-pass status appears",
       !any(gate$status %in% unlist(lock$gate_logic$forbidden_terminal_statuses)),
       paste(gate$status, collapse = ",")),
  test("report states local status and causal limitation",
       any(grepl("LOCAL_READY_EXTERNAL_PENDING", report_lines, fixed = TRUE)) &&
         any(grepl("Causal-identification status: `NOT_EVALUATED`", report_lines,
                   fixed = TRUE)) &&
         any(grepl("does not estimate a reform effect", report_lines,
                   fixed = TRUE)),
       "scope statements present"),
  test("output manifest contains no restricted data",
       all(manifest$contains_restricted_data == FALSE),
       sum(manifest$contains_restricted_data)),
  test("output manifest hashes every listed artifact",
       all(file.exists(manifest_paths)) &&
         identical(unname(manifest_actual), unname(manifest$sha256)),
       sprintf("%d/%d", sum(manifest_actual == manifest$sha256), nrow(manifest)))
), use.names = TRUE)

fwrite(tests, file.path(audit_dir, "REGISTRY_SAR_R0_ACCEPTANCE_TESTS.csv"))
writeLines(c(
  sprintf("registry_sar_r0_validation checks=%d passed=%d failed=%d",
          nrow(tests), sum(tests$passed), sum(!tests$passed)),
  sprintf("status=%s",
          gate[gate == "R0_LOCAL_OVERALL", status]),
  sprintf("causal_status=%s",
          gate[gate == "CAUSAL_IDENTIFICATION", status])
), log_path)

print(tests)
if (!all(tests$passed)) {
  stop(sprintf("Registry/SAR R0 validation failed %d/%d checks",
               sum(!tests$passed), nrow(tests)))
}
cat(sprintf(
  "registry_sar_r0_validation_ok checks=%d status=%s causal=%s\n",
  nrow(tests), gate[gate == "R0_LOCAL_OVERALL", status],
  gate[gate == "CAUSAL_IDENTIFICATION", status]
))

