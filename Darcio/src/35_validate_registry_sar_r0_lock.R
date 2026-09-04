#!/usr/bin/env Rscript
# Read-only integrity checks for the Registry/SAR R0 local-readiness lock.

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

paths <- c(
  lock = file.path(root, "config", "registry_sar_r0_lock.yml"),
  protocol = file.path(root, "paper", "ledgers", "REGISTRY_SAR_R0_PROTOCOL.md"),
  amendments = file.path(root, "paper", "ledgers", "REGISTRY_SAR_R0_AMENDMENTS.md"),
  schema = file.path(root, "config", "registry_sar_canonical_schema.csv"),
  hashes = file.path(root, "paper", "ledgers", "REGISTRY_SAR_R0_LOCK_SHA256.txt")
)
if (!all(file.exists(paths))) {
  stop("Missing R0 lock artifact(s): ",
       paste(names(paths)[!file.exists(paths)], collapse = ", "))
}

lock <- read_yaml(paths[["lock"]])
schema <- fread(paths[["schema"]])
protocol_lines <- readLines(paths[["protocol"]], warn = FALSE)
amendment_lines <- readLines(paths[["amendments"]], warn = FALSE)
hash_lines <- readLines(paths[["hashes"]], warn = FALSE)

expected_hash <- function(relative_path) {
  hit <- grep(paste0(relative_path, "$"), hash_lines, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub("[[:space:]].*$", "", hit)
}

actual_hash <- function(path) digest(path, algo = "sha256", file = TRUE)
test <- function(name, condition, observed) {
  data.table(test = name, passed = isTRUE(condition), observed = as.character(observed))
}

required_schema_columns <- c("level", "field", "type", "required", "purpose",
                             "export_rule")
required_restricted <- c("event_key", "celebration_date", "registration_date",
                         "spouse_order", "birth_date", "sex",
                         "residence_municipality", "registry_municipality",
                         "source_flow", "date_edit_flag",
                         "residence_edit_flag")
required_analytic <- c("celebration_period", "age_distance_day", "below16",
                       "post_law", "sex", "marriage_events",
                       "population_person_time", "synthetic")

tests <- rbindlist(list(
  test("machine-readable lock hash",
       identical(actual_hash(paths[["lock"]]),
                 expected_hash("config/registry_sar_r0_lock.yml")),
       actual_hash(paths[["lock"]])),
  test("human-readable protocol hash",
       identical(actual_hash(paths[["protocol"]]),
                 expected_hash("paper/ledgers/REGISTRY_SAR_R0_PROTOCOL.md")),
       actual_hash(paths[["protocol"]])),
  test("amendment ledger hash",
       identical(actual_hash(paths[["amendments"]]),
                 expected_hash("paper/ledgers/REGISTRY_SAR_R0_AMENDMENTS.md")),
       actual_hash(paths[["amendments"]])),
  test("canonical schema hash",
       identical(actual_hash(paths[["schema"]]),
                 expected_hash("config/registry_sar_canonical_schema.csv")),
       actual_hash(paths[["schema"]])),
  test("protocol version is 1.0.0",
       identical(lock$protocol$version, "1.0.0"), lock$protocol$version),
  test("freeze timestamp appears in protocol",
       any(grepl(lock$protocol$frozen_at, protocol_lines, fixed = TRUE)),
       lock$protocol$frozen_at),
  test("freeze timestamp appears in amendment ledger",
       any(grepl(lock$protocol$frozen_at, amendment_lines, fixed = TRUE)),
       lock$protocol$frozen_at),
  test("R0 is explicitly post-public-results",
       isTRUE(lock$protocol$post_public_results),
       lock$protocol$post_public_results),
  test("R0 precedes restricted microdata",
       isTRUE(lock$protocol$pre_restricted_microdata) &&
         identical(lock$protocol$restricted_microdata_seen, FALSE),
       lock$protocol$restricted_microdata_seen),
  test("external request remains unsent",
       identical(lock$protocol$external_request_sent, FALSE),
       lock$protocol$external_request_sent),
  test("terminal local status is bounded",
       identical(lock$protocol$terminal_local_status,
                 "LOCAL_READY_EXTERNAL_PENDING"),
       lock$protocol$terminal_local_status),
  test("design is an event-rate difference in discontinuities",
       grepl("difference in discontinuities for event rates",
             lock$causal_design$design_name, fixed = TRUE),
       lock$causal_design$design_name),
  test("running-variable cutoff is zero",
       identical(as.integer(lock$causal_design$cutoff), 0L),
       lock$causal_design$cutoff),
  test("primary sex and geography are frozen",
       identical(lock$causal_design$primary_sex, "combined") &&
         identical(lock$causal_design$primary_geography, "Brazil"),
       paste(lock$causal_design$primary_sex,
             lock$causal_design$primary_geography, sep = "/")),
  test("public Registry counts are planning-only",
       identical(lock$public_inputs$registry_counts$use,
                 "planning-count and power envelope only"),
       lock$public_inputs$registry_counts$use),
  test("primary denominator candidate is PNADC quarterly national",
       grepl("PNADC quarterly national", lock$denominator$selected_candidate,
             fixed = TRUE), lock$denominator$selected_candidate),
  test("denominator uncertainty is retained",
       grepl("population standard errors",
             lock$denominator$uncertainty_rule, fixed = TRUE),
       lock$denominator$uncertainty_rule),
  test("power bandwidths are 30,90,180,365",
       identical(as.integer(unlist(lock$power$bandwidth_days)),
                 c(30L, 90L, 180L, 365L)),
       paste(unlist(lock$power$bandwidth_days), collapse = ",")),
  test("base power screen is fixed at h90 and 20 percent",
       identical(as.integer(lock$power$base_screen$bandwidth_days), 90L) &&
         identical(as.numeric(lock$power$base_screen$maximum_decline_mde_percent),
                   20),
       paste(lock$power$base_screen$bandwidth_days,
             lock$power$base_screen$maximum_decline_mde_percent, sep = "/")),
  test("stress power screen is fixed at h180 and 30 percent",
       identical(as.integer(lock$power$stress_screen$bandwidth_days), 180L) &&
         identical(as.numeric(lock$power$stress_screen$maximum_decline_mde_percent),
                   30),
       paste(lock$power$stress_screen$bandwidth_days,
             lock$power$stress_screen$maximum_decline_mde_percent, sep = "/")),
  test("synthetic truth is a 0.60 incidence-rate ratio",
       identical(as.numeric(lock$synthetic_dry_run$true_treatment_irr), 0.60),
       lock$synthetic_dry_run$true_treatment_irr),
  test("synthetic publication prohibition is explicit",
       grepl("never use synthetic", lock$synthetic_dry_run$publication_rule,
             fixed = TRUE), lock$synthetic_dry_run$publication_rule),
  test("causal status remains not evaluated",
       identical(lock$gate_logic$causal_status_at_r0, "NOT_EVALUATED"),
       lock$gate_logic$causal_status_at_r0),
  test("forbidden terminal statuses include causal pass",
       all(c("PASS_CAUSAL", "ADVANCE_AS_CAUSAL_CORE") %in%
             unlist(lock$gate_logic$forbidden_terminal_statuses)),
       paste(unlist(lock$gate_logic$forbidden_terminal_statuses), collapse = ",")),
  test("canonical schema columns are complete",
       all(required_schema_columns %in% names(schema)),
       paste(names(schema), collapse = ",")),
  test("restricted canonical fields are complete",
       all(required_restricted %in% schema[level == "restricted_event", field]),
       length(schema[level == "restricted_event"]$field)),
  test("analytic canonical fields are complete",
       all(required_analytic %in% schema[level == "analytic_cell", field]),
       length(schema[level == "analytic_cell"]$field)),
  test("direct identifiers are never requested",
       !any(tolower(schema$field) %in%
              c("name", "nome", "cpf", "rg", "address", "endereco")),
       paste(schema$field, collapse = ","))
), use.names = TRUE)

print(tests)
if (!all(tests$passed)) {
  stop(sprintf("Registry/SAR R0 lock failed %d/%d checks",
               sum(!tests$passed), nrow(tests)))
}
cat(sprintf("registry_sar_r0_lock_ok checks=%d\n", nrow(tests)))

