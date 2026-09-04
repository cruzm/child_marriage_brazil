#!/usr/bin/env Rscript
# Build the public-input, denominator, power, and external-readiness components
# of Registry/SAR R0. This script estimates no policy effect.

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

started <- Sys.time()
lock <- read_yaml(file.path(root, "config", "registry_sar_r0_lock.yml"))
audit_dir <- file.path(root, "outputs", "audit")
analysis_dir <- file.path(root, "outputs", "analysis")
data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
log_dir <- file.path(root, "outputs", "logs")
for (d in c(audit_dir, analysis_dir, data_dir, table_dir, log_dir)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}
log_path <- file.path(log_dir, "36_registry_sar_r0_local.log")
writeLines(character(), log_path)
log_line <- function(...) {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S%z"),
                 paste0(...))
  cat(msg, "\n")
  cat(msg, "\n", file = log_path, append = TRUE)
}

test_row <- function(component, criterion, passed, observed, threshold = "") {
  data.table(component = component, criterion = criterion,
             passed = isTRUE(passed), observed = as.character(observed),
             threshold = as.character(threshold))
}

input_specs <- list(
  registry_counts = list(
    path = file.path(root, lock$public_inputs$registry_counts$file),
    required = c("year", "uf_code", "sex", "age", "persons_married"),
    role = "planning counts only; age/year at registration"
  ),
  pnadc_quarterly = list(
    path = file.path(root, lock$public_inputs$pnadc_quarterly_population$file),
    required = c("year", "quarter", "geography_level", "geography_value",
                 "age", "sex", "population", "population_se",
                 "unweighted_n", "population_cv"),
    role = "selected aggregate exposure candidate"
  ),
  pnadc_annual = list(
    path = file.path(root, lock$public_inputs$pnadc_annual_population$file),
    required = c("year", "geography_level", "geography_value", "age", "sex",
                 "population", "population_se", "unweighted_n",
                 "population_cv"),
    role = "annual-frequency population cross-check"
  )
)

input_rows <- lapply(names(input_specs), function(id) {
  spec <- input_specs[[id]]
  exists <- file.exists(spec$path)
  z <- if (exists) fread(spec$path) else data.table()
  complete <- exists && all(spec$required %in% names(z))
  data.table(
    input_id = id,
    relative_path = if (exists) sub(paste0("^", root, "/"), "", spec$path) else
      sub(paste0("^", root, "/"), "", spec$path),
    exists = exists,
    sha256 = if (exists) digest(spec$path, algo = "sha256", file = TRUE) else NA_character_,
    rows = if (exists) nrow(z) else NA_integer_,
    required_columns = paste(spec$required, collapse = ";"),
    schema_complete = complete,
    role = spec$role
  )
})
input_audit <- rbindlist(input_rows)
if (!all(input_audit$exists & input_audit$schema_complete)) {
  stop("R0 public input audit failed")
}

registry <- fread(input_specs$registry_counts$path)
quarterly <- fread(input_specs$pnadc_quarterly$path)
annual <- fread(input_specs$pnadc_annual$path)

years_pre <- as.integer(unlist(lock$periods$planning_pre_years))
years_post <- as.integer(unlist(lock$periods$planning_post_years))
years_all <- c(years_pre, years_post)
target_ages <- as.integer(unlist(lock$public_inputs$registry_counts$ages))
target_sexes <- c(lock$causal_design$primary_sex,
                  unlist(lock$causal_design$sex_sensitivities))

reg_target <- registry[
  year %in% years_all & age %in% target_ages & sex %in% target_sexes
]
if (!nrow(reg_target) || any(!is.finite(reg_target$persons_married)) ||
    any(reg_target$persons_married < 0)) {
  stop("Invalid Registry planning counts")
}
reg_target[, era := fifelse(year %in% years_pre, "pre", "post")]
counts <- reg_target[, .(
  registered_person_events = sum(persons_married)
), by = .(sex, era, age)]
counts[, cell := sprintf("%s_age%d", era, age)]
counts_wide <- dcast(counts, sex ~ cell, value.var = "registered_person_events")
needed_count_columns <- c("pre_age15", "pre_age16", "post_age15", "post_age16")
if (!all(needed_count_columns %in% names(counts_wide)) ||
    any(!is.finite(as.matrix(counts_wide[, ..needed_count_columns]))) ||
    any(as.matrix(counts_wide[, ..needed_count_columns]) <= 0)) {
  stop("Incomplete four-cell Registry planning counts")
}

# Combined-sex counts must equal the separately tabulated female plus male rows.
sex_identity <- counts_wide[sex == "combined", ..needed_count_columns] -
  (counts_wide[sex == "female", ..needed_count_columns] +
     counts_wide[sex == "male", ..needed_count_columns])
if (any(abs(as.matrix(sex_identity)) > 0)) {
  stop("Combined Registry counts do not equal female plus male counts")
}

power_grid <- CJ(
  sex = target_sexes,
  bandwidth_days = as.integer(unlist(lock$power$bandwidth_days)),
  allocation_multiplier = as.numeric(unlist(lock$power$within_age_allocation_multipliers)),
  variance_inflation_factor = as.numeric(unlist(lock$power$variance_inflation_factors)),
  sorted = TRUE
)
power_grid <- merge(power_grid, counts_wide, by = "sex", all.x = TRUE,
                    sort = FALSE)
days_per_year <- as.numeric(lock$denominator$conversion_days_per_year)
power_grid[, bandwidth_share := pmin(
  1, bandwidth_days / days_per_year * allocation_multiplier
)]
for (nm in needed_count_columns) {
  power_grid[, (paste0("expected_", nm)) := get(nm) * bandwidth_share]
}
expected_columns <- paste0("expected_", needed_count_columns)
alpha <- as.numeric(lock$power$alpha_two_sided)
target_power <- as.numeric(lock$power$target_power)
critical_sum <- qnorm(1 - alpha / 2) + qnorm(target_power)
power_grid[, poisson_log_se := sqrt(
  variance_inflation_factor * rowSums(1 / .SD)
), .SDcols = expected_columns]
power_grid[, `:=`(
  mde_log_irr = critical_sum * poisson_log_se,
  mde_decline_percent = 100 * (1 - exp(-critical_sum * poisson_log_se)),
  mde_increase_percent = 100 * (exp(critical_sum * poisson_log_se) - 1),
  minimum_expected_cell = do.call(pmin, .SD),
  alpha_two_sided = alpha,
  target_power = target_power,
  planning_only = TRUE,
  timing_semantics = "completed age/year at registration; not exact age/date at celebration"
), .SDcols = expected_columns]
setcolorder(power_grid, c(
  "sex", "bandwidth_days", "allocation_multiplier",
  "variance_inflation_factor", needed_count_columns, "bandwidth_share",
  expected_columns, "minimum_expected_cell", "poisson_log_se", "mde_log_irr",
  "mde_decline_percent", "mde_increase_percent", "alpha_two_sided",
  "target_power", "planning_only", "timing_semantics"
))

select_power_row <- function(spec) {
  power_grid[
    sex == spec$sex &
      bandwidth_days == as.integer(spec$bandwidth_days) &
      abs(allocation_multiplier - as.numeric(spec$allocation_multiplier)) < 1e-12 &
      abs(variance_inflation_factor -
            as.numeric(spec$variance_inflation_factor)) < 1e-12
  ]
}
base_power <- select_power_row(lock$power$base_screen)
stress_power <- select_power_row(lock$power$stress_screen)
if (nrow(base_power) != 1L || nrow(stress_power) != 1L) {
  stop("Could not identify frozen power-screen rows")
}
base_power_pass <- base_power$mde_decline_percent <=
  as.numeric(lock$power$base_screen$maximum_decline_mde_percent)
stress_power_pass <- stress_power$mde_decline_percent <=
  as.numeric(lock$power$stress_screen$maximum_decline_mde_percent)

q_target <- quarterly[
  geography_level == "Brazil" & geography_value == "Brazil" &
    year %in% years_all & age %in% target_ages & sex %in% target_sexes
]
q_keys <- c("year", "quarter", "age", "sex")
if (anyDuplicated(q_target, by = q_keys)) stop("Duplicate quarterly exposure keys")
q_target[, quarter_start := as.IDate(sprintf(
  "%04d-%02d-01", year, c(1L, 4L, 7L, 10L)[quarter]
))]
q_target[, next_quarter_start := as.IDate(sprintf(
  "%04d-%02d-01",
  year + as.integer(quarter == 4L),
  c(4L, 7L, 10L, 1L)[quarter]
))]
q_target[, days_in_quarter := as.integer(next_quarter_start - quarter_start)]
q_target[, side := fifelse(age == 15L, "below", "above")]
q_target[, `:=`(
  exact_age_day_stock = population / days_per_year,
  exact_age_day_stock_se = population_se / days_per_year,
  population_person_time = population * days_in_quarter / days_per_year,
  population_person_time_se = population_se * days_in_quarter / days_per_year,
  denominator_source = "IBGE PNADC quarterly calibrated population",
  geography = "Brazil",
  approximation = "smooth allocation within completed age; retain survey uncertainty"
)]
exposure <- q_target[, .(
  year, quarter, quarter_start, days_in_quarter, geography, age, side, sex,
  population_stock = population, population_stock_se = population_se,
  unweighted_n, population_cv, exact_age_day_stock, exact_age_day_stock_se,
  population_person_time, population_person_time_se, denominator_source,
  approximation
)]
setorder(exposure, year, quarter, sex, age)

a_target <- annual[
  geography_level == "Brazil" & geography_value == "Brazil" &
    year %in% years_all & age %in% target_ages & sex %in% target_sexes
]
q_annualized <- q_target[, .(
  quarterly_mean_population = mean(population),
  quarterly_mean_se = sqrt(sum(population_se^2)) / .N
), by = .(year, age, sex)]
annual_compare <- merge(
  q_annualized,
  a_target[, .(year, age, sex, annual_population = population,
               annual_population_se = population_se)],
  by = c("year", "age", "sex"), all = FALSE
)
annual_compare[, relative_difference :=
                 (quarterly_mean_population - annual_population) /
                 annual_population]

denominator_audit <- rbindlist(lapply(target_sexes, function(sx) {
  z <- q_target[sex == sx]
  a <- annual_compare[sex == sx]
  primary <- identical(sx, lock$denominator$primary_precision$sex)
  expected <- if (primary) {
    as.integer(lock$denominator$primary_precision$expected_cells)
  } else {
    as.integer(lock$denominator$sex_sensitivity_precision$expected_cells_each)
  }
  max_cv <- if (primary) {
    as.numeric(lock$denominator$primary_precision$maximum_cv)
  } else {
    as.numeric(lock$denominator$sex_sensitivity_precision$maximum_cv)
  }
  min_n <- if (primary) {
    as.integer(lock$denominator$primary_precision$minimum_unweighted_n)
  } else {
    as.integer(lock$denominator$sex_sensitivity_precision$minimum_unweighted_n)
  }
  max_diff <- as.numeric(
    lock$denominator$annual_quarterly_check$maximum_absolute_relative_difference
  )
  min_common <- as.integer(
    lock$denominator$annual_quarterly_check$minimum_common_age_sex_year_cells_each_sex
  )
  rbindlist(list(
    test_row(sx, "complete quarterly cells", nrow(z) == expected,
             nrow(z), expected),
    test_row(sx, "positive finite population and SE",
             all(is.finite(z$population) & z$population > 0 &
                   is.finite(z$population_se) & z$population_se >= 0),
             sum(is.finite(z$population) & z$population > 0 &
                   is.finite(z$population_se) & z$population_se >= 0),
             expected),
    test_row(sx, "minimum unweighted cell size",
             min(z$unweighted_n) >= min_n, min(z$unweighted_n), min_n),
    test_row(sx, "maximum quarterly population CV",
             max(z$population_cv) <= max_cv,
             sprintf("%.8f", max(z$population_cv)), max_cv),
    test_row(sx, "annual-quarterly common cells",
             nrow(a) >= min_common, nrow(a), min_common),
    test_row(sx, "maximum annual-quarterly relative difference",
             max(abs(a$relative_difference)) <= max_diff,
             sprintf("%.8f", max(abs(a$relative_difference))), max_diff)
  ))
}))

exposure_dictionary <- data.table(
  variable = names(exposure),
  definition = c(
    "calendar year", "calendar quarter", "first day of quarter",
    "calendar days in quarter", "national residence geography",
    "completed-age population cell used for exposure", "age-16 cutoff side",
    "sex population", "quarterly calibrated population estimate",
    "Taylor standard error of population estimate", "unweighted survey count",
    "population standard error divided by estimate",
    "population stock divided by 365.2425",
    "population-stock SE divided by 365.2425",
    "person-time for one exact-age-day accumulated over the quarter",
    "SE of person-time under linear scaling", "official source label",
    "explicit within-completed-age allocation assumption"
  ),
  unit = c(
    "year", "quarter", "date", "days", "text", "years", "text", "text",
    "persons", "persons", "records", "ratio", "persons", "persons",
    "person-days", "person-days", "text", "text"
  ),
  restricted = FALSE,
  import_to_sar = TRUE
)

external_checklist <- data.table(
  item_id = sprintf("E%02d", 1:11),
  item = c(
    "exact celebration date retained in every 2013-2024 file",
    "both spouses' birth dates retained in every 2013-2024 file",
    "registration date retained and comparable across years",
    "residence municipality retained and comparable across years",
    "SEADE source flow for Sao Paulo included and identifiable",
    "edit, imputation, missingness, source, and collection flags available",
    "internal event key permits deduplication without export",
    "aggregate PNADC exposure import is permitted",
    "aggregate coefficients and diagnostics can undergo disclosure review",
    "researcher and institutional signatory fields are completed",
    "researcher explicitly authorizes external transmission"
  ),
  threshold_or_answer_needed = c(
    "yes; later >=99% valid in target ages", "yes; later >=99% valid",
    "yes", "yes; later >=95% valid", "yes", "yes", "yes", "yes", "yes",
    "completed outside version control", "yes"
  ),
  current_status = c(rep("PENDING_IBGE", 9), "PENDING_USER", "PENDING_USER"),
  blocking = TRUE,
  evidence_after_response = NA_character_
)

input_checks <- rbindlist(list(
  test_row("inputs", "all three public inputs exist",
           all(input_audit$exists), sum(input_audit$exists), 3),
  test_row("inputs", "all required public-input columns exist",
           all(input_audit$schema_complete), sum(input_audit$schema_complete), 3),
  test_row("inputs", "planning years are complete",
           setequal(unique(reg_target$year), years_all),
           paste(sort(unique(reg_target$year)), collapse = ","),
           paste(years_all, collapse = ",")),
  test_row("inputs", "combined counts equal female plus male counts",
           all(abs(as.matrix(sex_identity)) == 0),
           max(abs(as.matrix(sex_identity))), 0),
  test_row("power", "base count-MDE screen",
           base_power_pass,
           sprintf("%.5f%%", base_power$mde_decline_percent),
           sprintf("<=%.1f%%",
                   as.numeric(lock$power$base_screen$maximum_decline_mde_percent))),
  test_row("power", "stress count-MDE screen",
           stress_power_pass,
           sprintf("%.5f%%", stress_power$mde_decline_percent),
           sprintf("<=%.1f%%",
                   as.numeric(lock$power$stress_screen$maximum_decline_mde_percent)))
))
if (!all(input_checks$passed) || !all(denominator_audit$passed)) {
  stop("Registry/SAR R0 local planning checks failed")
}

fwrite(input_audit, file.path(audit_dir, "REGISTRY_SAR_R0_INPUT_AUDIT.csv"))
fwrite(denominator_audit,
       file.path(audit_dir, "REGISTRY_SAR_R0_DENOMINATOR_AUDIT.csv"))
fwrite(external_checklist,
       file.path(audit_dir, "REGISTRY_SAR_R0_EXTERNAL_CHECKLIST.csv"), na = "")
fwrite(exposure, file.path(data_dir, "REGISTRY_SAR_R0_PNADC_EXPOSURE.csv"))
fwrite(exposure_dictionary,
       file.path(data_dir, "REGISTRY_SAR_R0_PNADC_EXPOSURE_DICTIONARY.csv"))
fwrite(power_grid,
       file.path(table_dir, "REGISTRY_SAR_R0_POWER_ENVELOPE.csv"))
fwrite(rbindlist(list(input_checks, denominator_audit), fill = TRUE),
       file.path(audit_dir, "REGISTRY_SAR_R0_LOCAL_COMPONENT_TESTS.csv"))

log_line(sprintf(
  paste0("r0_local_components_complete inputs=%d exposure_rows=%d ",
         "power_rows=%d base_mde=%.5f stress_mde=%.5f elapsed=%.2fs"),
  nrow(input_audit), nrow(exposure), nrow(power_grid),
  base_power$mde_decline_percent, stress_power$mde_decline_percent,
  as.numeric(difftime(Sys.time(), started, units = "secs"))
))

