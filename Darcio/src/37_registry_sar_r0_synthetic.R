#!/usr/bin/env Rscript
# Generate an explicitly synthetic exact-age cell panel, recover a known policy
# interaction, and finalize the Registry/SAR R0 local-readiness artifacts.

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
  library(fixest)
  library(yaml)
})

started <- Sys.time()
lock <- read_yaml(file.path(root, "config", "registry_sar_r0_lock.yml"))
set.seed(as.integer(lock$synthetic_dry_run$seed))
setFixest_nthreads(min(4L, parallel::detectCores()))

audit_dir <- file.path(root, "outputs", "audit")
analysis_dir <- file.path(root, "outputs", "analysis")
data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
log_dir <- file.path(root, "outputs", "logs")
for (d in c(audit_dir, analysis_dir, data_dir, table_dir, log_dir)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}
log_path <- file.path(log_dir, "37_registry_sar_r0_synthetic.log")
writeLines(character(), log_path)
log_line <- function(...) {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S%z"),
                 paste0(...))
  cat(msg, "\n")
  cat(msg, "\n", file = log_path, append = TRUE)
}

component_paths <- c(
  input_audit = file.path(audit_dir, "REGISTRY_SAR_R0_INPUT_AUDIT.csv"),
  denominator_audit = file.path(audit_dir, "REGISTRY_SAR_R0_DENOMINATOR_AUDIT.csv"),
  local_tests = file.path(audit_dir, "REGISTRY_SAR_R0_LOCAL_COMPONENT_TESTS.csv"),
  external_checklist = file.path(audit_dir, "REGISTRY_SAR_R0_EXTERNAL_CHECKLIST.csv"),
  exposure = file.path(data_dir, "REGISTRY_SAR_R0_PNADC_EXPOSURE.csv"),
  exposure_dictionary = file.path(data_dir, "REGISTRY_SAR_R0_PNADC_EXPOSURE_DICTIONARY.csv"),
  power = file.path(table_dir, "REGISTRY_SAR_R0_POWER_ENVELOPE.csv")
)
if (!all(file.exists(component_paths))) {
  stop("Run src/36_registry_sar_r0_local.R before the synthetic dry run")
}

local_tests <- fread(component_paths[["local_tests"]])
if (!all(local_tests$passed)) stop("Local R0 component test is not clean")
exposure <- fread(component_paths[["exposure"]])
power <- fread(component_paths[["power"]])
external <- fread(component_paths[["external_checklist"]])
schema <- fread(file.path(root, "config", "registry_sar_canonical_schema.csv"))

first_month <- as.IDate(lock$synthetic_dry_run$first_month)
last_month <- as.IDate(lock$synthetic_dry_run$last_month)
omitted_month <- as.IDate(lock$synthetic_dry_run$omitted_transition_month)
month_dates <- as.IDate(seq(as.Date(first_month), as.Date(last_month), by = "month"))
calendar <- data.table(month_start = month_dates)
calendar <- calendar[month_start != omitted_month]
calendar[, `:=`(
  celebration_period = format(month_start, "%Y-%m"),
  year = as.integer(format(month_start, "%Y")),
  month = as.integer(format(month_start, "%m"))
)]
calendar[, quarter := (month - 1L) %/% 3L + 1L]
calendar[, next_month := as.IDate(ifelse(
  month == 12L,
  sprintf("%04d-01-01", year + 1L),
  sprintf("%04d-%02d-01", year, month + 1L)
))]
calendar[, days_in_month := as.integer(next_month - month_start)]
calendar[, post_law := as.integer(month_start >= as.IDate("2019-04-01"))]

x_limits <- as.integer(unlist(lock$synthetic_dry_run$age_distance_days))
grid <- CJ(
  celebration_period = calendar$celebration_period,
  age_distance_day = seq.int(x_limits[1], x_limits[2]),
  sorted = TRUE
)
grid <- merge(grid, calendar[, .(celebration_period, month_start, year, month,
                                  quarter, days_in_month, post_law)],
              by = "celebration_period", all.x = TRUE, sort = FALSE)
grid[, `:=`(
  below16 = as.integer(age_distance_day < 0L),
  age = fifelse(age_distance_day < 0L, 15L, 16L),
  sex = "combined",
  synthetic = TRUE
)]

denom <- exposure[sex == "combined", .(
  year, quarter, age, population_stock, population_stock_se
)]
grid <- merge(grid, denom, by = c("year", "quarter", "age"),
              all.x = TRUE, sort = FALSE)
if (anyNA(grid$population_stock)) stop("Synthetic denominator join failed")
days_per_year <- as.numeric(lock$denominator$conversion_days_per_year)
grid[, population_person_time :=
       population_stock * days_in_month / days_per_year]
grid[, population_person_time_se :=
       population_stock_se * days_in_month / days_per_year]

grid[, `:=`(
  x_scaled = age_distance_day / 180,
  below_x = below16 * age_distance_day / 180,
  post_x = post_law * age_distance_day / 180,
  treatment = below16 * post_law,
  treatment_x = below16 * post_law * age_distance_day / 180
)]
true_beta <- log(as.numeric(lock$synthetic_dry_run$true_treatment_irr))
grid[, period_component :=
       0.10 * sin(2 * pi * (month - 1) / 12) - 0.012 * (year - 2013)]
grid[, expected_events := population_person_time * exp(
  -11.0 - 2.20 * below16 + 0.08 * x_scaled - 0.05 * below_x +
    0.02 * post_x + true_beta * treatment + 0.03 * treatment_x +
    period_component
)]
grid[, marriage_events := rpois(.N, expected_events)]
grid[, log_population_person_time := log(population_person_time)]

fit <- fepois(
  marriage_events ~ below16 + x_scaled + below_x + post_x + treatment +
    treatment_x | celebration_period,
  offset = ~log_population_person_time,
  vcov = ~celebration_period,
  data = grid,
  warn = FALSE,
  notes = FALSE
)
ct <- coeftable(fit)
if (!"treatment" %in% rownames(ct)) stop("Synthetic treatment coefficient absent")
estimate <- unname(coef(fit)["treatment"])
standard_error <- unname(se(fit)["treatment"])
ci <- as.numeric(confint(fit, parm = "treatment", level = 0.95)[1, 1:2])
tolerance <- as.numeric(
  lock$synthetic_dry_run$coefficient_tolerance_log_points
)
within_tolerance <- abs(estimate - true_beta) <= tolerance
truth_in_ci <- ci[1] <= true_beta && ci[2] >= true_beta
recovery_pass <- within_tolerance &&
  (!isTRUE(lock$synthetic_dry_run$require_true_value_in_95_ci) || truth_in_ci)

recovery <- data.table(
  model_id = "SYNTHETIC_PPML_DIFF_IN_DISC",
  synthetic = TRUE,
  n_cells = nrow(grid),
  n_events = sum(grid$marriage_events),
  n_calendar_clusters = uniqueN(grid$celebration_period),
  true_log_irr = true_beta,
  estimated_log_irr = estimate,
  standard_error = standard_error,
  ci95_low = ci[1],
  ci95_high = ci[2],
  true_irr = exp(true_beta),
  estimated_irr = exp(estimate),
  absolute_error_log_points = abs(estimate - true_beta),
  tolerance_log_points = tolerance,
  true_value_in_ci95 = truth_in_ci,
  recovery_pass = recovery_pass,
  interpretation = "software recovery test only; not empirical evidence"
)
if (!recovery_pass) stop("Synthetic recovery gate failed")

synthetic_output <- grid[, .(
  celebration_period,
  age_distance_day,
  below16,
  post_law,
  sex,
  marriage_events,
  population_person_time,
  population_person_time_se,
  synthetic,
  expected_events
)]
required_analytic <- schema[
  level == "analytic_cell" & required == TRUE, field
]
schema_tests <- data.table(
  criterion = c(
    "all required analytic fields exist",
    "synthetic marker is true in every row",
    "synthetic cell keys are unique",
    "counts and exposures are finite and nonnegative",
    "no direct-identifier field is present"
  ),
  passed = c(
    all(required_analytic %in% names(synthetic_output)),
    all(synthetic_output$synthetic),
    !anyDuplicated(synthetic_output,
                   by = c("celebration_period", "age_distance_day", "sex")),
    all(is.finite(synthetic_output$marriage_events) &
          synthetic_output$marriage_events >= 0 &
          is.finite(synthetic_output$population_person_time) &
          synthetic_output$population_person_time > 0),
    !any(tolower(names(synthetic_output)) %in%
           c("name", "nome", "cpf", "rg", "address", "endereco",
             "event_key", "birth_date"))
  ),
  observed = c(
    paste(required_analytic, collapse = ";"),
    sum(synthetic_output$synthetic),
    anyDuplicated(synthetic_output,
                  by = c("celebration_period", "age_distance_day", "sex")),
    sprintf("events=%d;min_exposure=%.3f", sum(synthetic_output$marriage_events),
            min(synthetic_output$population_person_time)),
    paste(names(synthetic_output), collapse = ";")
  )
)
if (!all(schema_tests$passed)) stop("Synthetic schema audit failed")

synthetic_path <- file.path(data_dir,
                            "REGISTRY_SAR_R0_SYNTHETIC_CELLS.csv.gz")
fwrite(synthetic_output, synthetic_path, compress = "gzip")
fwrite(recovery,
       file.path(table_dir, "REGISTRY_SAR_R0_SYNTHETIC_RECOVERY.csv"))
fwrite(schema_tests,
       file.path(audit_dir, "REGISTRY_SAR_R0_SYNTHETIC_SCHEMA_AUDIT.csv"))
software <- data.table(
  component = c("R", "data.table", "digest", "fixest", "yaml"),
  version = c(as.character(getRversion()),
              as.character(packageVersion("data.table")),
              as.character(packageVersion("digest")),
              as.character(packageVersion("fixest")),
              as.character(packageVersion("yaml")))
)
fwrite(software, file.path(audit_dir, "REGISTRY_SAR_R0_SOFTWARE.csv"))

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
denominator_audit <- fread(component_paths[["denominator_audit"]])
input_audit <- fread(component_paths[["input_audit"]])
inquiry_path <- file.path(root, "paper", "ledgers",
                          "IBGE_SAR_TECHNICAL_INQUIRY_READY.md")
inquiry_lines <- readLines(inquiry_path, warn = FALSE)

local_ok <- all(local_tests$passed) && all(denominator_audit$passed) &&
  isTRUE(recovery_pass) && file.exists(inquiry_path) &&
  any(grepl("READY_NOT_SENT", inquiry_lines, fixed = TRUE))
external_pending <- all(external$current_status %in%
                          c("PENDING_IBGE", "PENDING_USER"))
overall_status <- if (local_ok && external_pending) {
  "LOCAL_READY_EXTERNAL_PENDING"
} else {
  "LOCAL_NOT_READY"
}

gate_status <- data.table(
  gate = c(
    "R0_LOCK", "R0_PUBLIC_INPUTS", "R0_DENOMINATOR",
    "R0_POWER", "R0_SYNTHETIC_PIPELINE", "R0_TECHNICAL_INQUIRY",
    "R0_IBGE_FIELD_CONFIRMATION", "R0_INSTITUTIONAL_AND_SEND",
    "R0_LOCAL_OVERALL", "CAUSAL_IDENTIFICATION"
  ),
  domain = c(
    rep("local", 6), "external", "external", "overall", "causal"
  ),
  status = c(
    "PASS", "PASS", "PASS", "PROVISIONAL_PASS", "PASS",
    "READY_NOT_SENT", "PENDING_IBGE", "PENDING_USER",
    overall_status, "NOT_EVALUATED"
  ),
  binding = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE,
              TRUE, TRUE, TRUE, TRUE),
  evidence = c(
    "frozen hashes and semantic checks",
    sprintf("%d public aggregate inputs audited", nrow(input_audit)),
    sprintf("%d denominator criteria passed", nrow(denominator_audit)),
    sprintf("base MDE %.3f%%; stress MDE %.3f%%",
            base_row$mde_decline_percent, stress_row$mde_decline_percent),
    sprintf("true %.4f; estimate %.4f; error %.4f log point",
            true_beta, estimate, abs(estimate - true_beta)),
    "message and attachment list prepared locally; no transmission",
    "annual retention, SEADE, flags, and disclosure rules require IBGE reply",
    "identity, signatory, and explicit authorization remain outside repository",
    "all local components pass; all external criteria remain explicitly pending",
    "R0 contains no restricted outcome and estimates no policy effect"
  )
)
if (!identical(overall_status, lock$protocol$terminal_local_status)) {
  stop("R0 did not reach its bounded local-ready status")
}

fwrite(gate_status, file.path(audit_dir, "REGISTRY_SAR_R0_GATE_STATUS.csv"))

combined_counts <- power[
  sex == "combined" & bandwidth_days == 90 &
    allocation_multiplier == 1 & variance_inflation_factor == 1
][1]
combined_denom <- denominator_audit[component == "combined"]
max_cv <- as.numeric(combined_denom[
  criterion == "maximum quarterly population CV", observed
])
max_diff <- as.numeric(combined_denom[
  criterion == "maximum annual-quarterly relative difference", observed
])

report <- c(
  "# Registry/SAR exact-date redesign — R0 local readiness",
  "",
  sprintf("**R0 status: `%s`.**", overall_status),
  "**Causal-identification status: `NOT_EVALUATED`.**",
  "**External request: `READY_NOT_SENT`.**",
  "",
  sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "R0 completes the work that can be done without restricted RC.2 files. It",
  "does not estimate a reform effect. Public Registry counts screen power only;",
  "the synthetic coefficient tests software only.",
  "",
  "## Public count and power screen",
  "",
  sprintf(paste0("For combined sexes, the public registration-age cells contain ",
                 "%s age-15 and %s age-16 person-events in 2013-2018, versus ",
                 "%s and %s in 2019-2024."),
          format(combined_counts$pre_age15, big.mark = ",", scientific = FALSE),
          format(combined_counts$pre_age16, big.mark = ",", scientific = FALSE),
          format(combined_counts$post_age15, big.mark = ",", scientific = FALSE),
          format(combined_counts$post_age16, big.mark = ",", scientific = FALSE)),
  sprintf(paste0("The frozen base screen gives an 80%%-power decline MDE of ",
                 "%.2f%% at 90 days (threshold 20%%). The stress screen gives ",
                 "%.2f%% at 180 days (threshold 30%%). Both pass provisionally."),
          base_row$mde_decline_percent, stress_row$mde_decline_percent),
  "These are not exact-window counts: the public source records completed age",
  "and year at registration rather than exact age and date at celebration.",
  "",
  "## Denominator package",
  "",
  sprintf(paste0("The selected national quarterly PNADC exposure contains %d ",
                 "cells for ages 15/16 and combined/female/male populations. ",
                 "For the combined primary population, maximum CV is %.3f%% ",
                 "and the largest annual-versus-quarterly difference is %.3f%%."),
          nrow(exposure), 100 * max_cv, 100 * max_diff),
  "The exported file converts each population stock into approximate exact-age-",
  "day stocks and quarterly person-time. This smooth allocation is explicit;",
  "survey uncertainty must remain in the restricted analysis.",
  "",
  "## Synthetic pipeline",
  "",
  sprintf(paste0("The PPML dry run used %s synthetic cells and %s simulated ",
                 "events. It recovered a true log IRR of %.4f as %.4f ",
                 "(95%% CI [%.4f, %.4f]). Recovery passes the frozen tolerance."),
          format(recovery$n_cells, big.mark = ",", scientific = FALSE),
          format(recovery$n_events, big.mark = ",", scientific = FALSE),
          recovery$true_log_irr, recovery$estimated_log_irr,
          recovery$ci95_low, recovery$ci95_high),
  "Every synthetic row is marked `synthetic=TRUE`; this output is barred from",
  "substantive tables and figures.",
  "",
  "## Binding external items",
  "",
  "IBGE must confirm annual field retention, SEADE coverage, edit/imputation",
  "flags, an internal deduplication key, import of the aggregate exposure, and",
  "disclosure-reviewed exports. Researcher identity, institutional signatory,",
  "and explicit sending authorization remain pending outside version control.",
  "After access, date validity (>=99%), residence validity (>=95%), public-total",
  "reconciliation, exact-window power, counterfactual placebos, and final",
  "inference must pass before any causal-core decision.",
  "",
  "## Decision",
  "",
  "The local package is ready for external transmission. The paper's causal",
  "score does not change at R0 because no new identifying evidence has been",
  "observed. SINASC remains complementary and inconclusive.",
  "",
  "## Main artifacts",
  "",
  "- `config/registry_sar_r0_lock.yml`",
  "- `paper/ledgers/REGISTRY_SAR_R0_PROTOCOL.md`",
  "- `paper/ledgers/IBGE_SAR_TECHNICAL_INQUIRY_READY.md`",
  "- `outputs/tables/REGISTRY_SAR_R0_POWER_ENVELOPE.csv`",
  "- `outputs/data/REGISTRY_SAR_R0_PNADC_EXPOSURE.csv`",
  "- `outputs/tables/REGISTRY_SAR_R0_SYNTHETIC_RECOVERY.csv`",
  "- `outputs/audit/REGISTRY_SAR_R0_GATE_STATUS.csv`"
)
report_path <- file.path(analysis_dir, "REGISTRY_SAR_R0_RESULTS.md")
writeLines(report, report_path)

manifest_relative <- c(
  "config/registry_sar_r0_lock.yml",
  "config/registry_sar_canonical_schema.csv",
  "paper/ledgers/REGISTRY_SAR_R0_PROTOCOL.md",
  "paper/ledgers/REGISTRY_SAR_R0_AMENDMENTS.md",
  "paper/ledgers/REGISTRY_SAR_R0_LOCK_SHA256.txt",
  "paper/ledgers/IBGE_SAR_TECHNICAL_INQUIRY_READY.md",
  "paper/ledgers/IBGE_SAR_PROJECT_DRAFT.md",
  "outputs/audit/REGISTRY_SAR_R0_INPUT_AUDIT.csv",
  "outputs/audit/REGISTRY_SAR_R0_DENOMINATOR_AUDIT.csv",
  "outputs/audit/REGISTRY_SAR_R0_LOCAL_COMPONENT_TESTS.csv",
  "outputs/audit/REGISTRY_SAR_R0_EXTERNAL_CHECKLIST.csv",
  "outputs/audit/REGISTRY_SAR_R0_SYNTHETIC_SCHEMA_AUDIT.csv",
  "outputs/audit/REGISTRY_SAR_R0_SOFTWARE.csv",
  "outputs/audit/REGISTRY_SAR_R0_GATE_STATUS.csv",
  "outputs/data/REGISTRY_SAR_R0_PNADC_EXPOSURE.csv",
  "outputs/data/REGISTRY_SAR_R0_PNADC_EXPOSURE_DICTIONARY.csv",
  "outputs/data/REGISTRY_SAR_R0_SYNTHETIC_CELLS.csv.gz",
  "outputs/tables/REGISTRY_SAR_R0_POWER_ENVELOPE.csv",
  "outputs/tables/REGISTRY_SAR_R0_SYNTHETIC_RECOVERY.csv",
  "outputs/analysis/REGISTRY_SAR_R0_RESULTS.md"
)
manifest_paths <- file.path(root, manifest_relative)
if (!all(file.exists(manifest_paths))) {
  stop("Missing R0 manifest artifact(s): ",
       paste(manifest_relative[!file.exists(manifest_paths)], collapse = ", "))
}
manifest <- data.table(
  artifact = manifest_relative,
  bytes = as.numeric(file.info(manifest_paths)$size),
  sha256 = vapply(manifest_paths, digest, character(1),
                  algo = "sha256", file = TRUE),
  contains_restricted_data = FALSE
)
fwrite(manifest,
       file.path(audit_dir, "REGISTRY_SAR_R0_OUTPUT_MANIFEST.csv"))

log_line(sprintf(
  paste0("r0_synthetic_complete status=%s cells=%d events=%d estimate=%.6f ",
         "truth=%.6f elapsed=%.2fs"),
  overall_status, nrow(grid), sum(grid$marriage_events), estimate, true_beta,
  as.numeric(difftime(Sys.time(), started, units = "secs"))
))
