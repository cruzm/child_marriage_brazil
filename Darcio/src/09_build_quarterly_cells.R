#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(survey)
  library(parallel)
  library(yaml)
})

started <- Sys.time()
root <- file.path(normalizePath(getwd(), mustWork = TRUE), "Darcio")
cfg <- read_yaml(file.path(root, "config", "analysis.yml"))
input_dir <- file.path(root, "outputs", "data", "pnadc_quarterly_adolescents")
data_dir <- file.path(root, "outputs", "data")
audit_dir <- file.path(root, "outputs", "audit")
log_dir <- file.path(root, "outputs", "logs")
files <- list.files(input_dir, "part-0\\.parquet$", recursive = TRUE, full.names = TRUE)
if (length(files) != 48L) stop("Expected 48 quarterly partitions; found ", length(files))
workers <- min(4L, max(1L, floor(detectCores() / 2L)))
test_mode <- identical(Sys.getenv("QUARTERLY_CELL_TEST"), "1")
resume_mode <- identical(Sys.getenv("QUARTERLY_CELL_RESUME"), "1")
if (test_mode) {
  files <- files[1L]
  workers <- 1L
}
options(survey.lonely.psu = "adjust")

one_variable_svyby <- function(x, groups, estimate, standard_error) {
  z <- as.data.table(x)
  se_col <- grep("^se($|\\.)", names(z), value = TRUE)[1L]
  est_col <- setdiff(names(z), c(groups, se_col))[1L]
  if (is.na(se_col) || is.na(est_col)) stop("Unexpected one-variable svyby schema")
  setnames(z, c(est_col, se_col), c(estimate, standard_error))
  z[, c(groups, estimate, standard_error), with = FALSE]
}

population_cells <- function(d, des, combined) {
  groups <- c("uf", "age", if (!combined) "sex_code" else character())
  f <- as.formula(paste("~", paste(groups, collapse = "+")))
  z <- one_variable_svyby(
    svyby(~one, f, des, svytotal, vartype = "se", na.rm = TRUE),
    groups, "population", "population_se"
  )
  z <- merge(z, d[, .(unweighted_n = .N), by = groups], by = groups)
  z[, sex := if (combined) "combined" else fifelse(sex_code == 1L, "male", "female")]
  z[, region := fcase(
    uf %between% c(11L, 17L), "1",
    uf %between% c(21L, 29L), "2",
    uf %between% c(31L, 35L), "3",
    uf %between% c(41L, 43L), "4",
    uf %between% c(50L, 53L), "5",
    default = NA_character_
  )]
  if (anyNA(z$region)) stop("Unknown UF in population cells")
  uf_cells <- z[, .(
    geography_level = "UF", geography_value = as.character(uf), age, sex,
    population, population_se, unweighted_n
  )]
  region_cells <- z[, .(
    geography_level = "region", geography_value = unique(region),
    population = sum(population), population_se = sqrt(sum(population_se^2)),
    unweighted_n = sum(unweighted_n)
  ), by = .(region, age, sex)][, region := NULL]
  brazil_cells <- z[, .(
    geography_level = "Brazil", geography_value = "Brazil",
    population = sum(population), population_se = sqrt(sum(population_se^2)),
    unweighted_n = sum(unweighted_n)
  ), by = .(age, sex)]
  rbindlist(list(uf_cells, region_cells, brazil_cells), use.names = TRUE)
}

union_cells <- function(d, des, level, combined) {
  groups <- c(if (level == "region") "region" else character(),
              "age", if (!combined) "sex_code" else character())
  f <- as.formula(paste("~", paste(groups, collapse = "+")))
  z <- as.data.table(svyby(
    ~union_conservative + union_expanded, f, des, svymean,
    vartype = "se", na.rm = TRUE
  ))
  se_cols <- grep("^se($|\\.)", names(z), value = TRUE)
  if (length(se_cols) != 2L) stop("Unexpected multi-outcome svyby schema: ", paste(names(z), collapse = ","))
  setnames(z, se_cols, c("union_conservative_se", "union_expanded_se"))
  counts <- d[, .(
    unweighted_n = .N,
    union_conservative_unweighted_n = sum(union_conservative),
    union_expanded_unweighted_n = sum(union_expanded),
    union_expanded_ambiguous_unweighted_n = sum(union_expanded_ambiguous)
  ), by = groups]
  z <- merge(z, counts, by = groups)
  z[, `:=`(
    sex = if (combined) "combined" else fifelse(sex_code == 1L, "male", "female"),
    geography_level = level,
    geography_value = if (level == "region") as.character(region) else "Brazil"
  )]
  z[, .(
    geography_level, geography_value, age, sex,
    union_conservative, union_conservative_se,
    union_expanded, union_expanded_se,
    unweighted_n, union_conservative_unweighted_n,
    union_expanded_unweighted_n, union_expanded_ambiguous_unweighted_n
  )]
}

uf_union_diagnostics <- function(d, combined) {
  groups <- c("uf", "age", if (!combined) "sex_code" else character())
  z <- d[, .(
    union_conservative = weighted.mean(union_conservative, quarterly_calibrated_weight),
    union_expanded = weighted.mean(union_expanded, quarterly_calibrated_weight),
    unweighted_n = .N,
    union_conservative_unweighted_n = sum(union_conservative),
    union_expanded_unweighted_n = sum(union_expanded),
    union_expanded_ambiguous_unweighted_n = sum(union_expanded_ambiguous)
  ), by = groups]
  z[, `:=`(
    geography_level = "UF_diagnostic_no_design_se",
    geography_value = as.character(uf),
    sex = if (combined) "combined" else fifelse(sex_code == 1L, "male", "female")
  )]
  z[, .(
    geography_level, geography_value, age, sex,
    union_conservative, union_expanded, unweighted_n,
    union_conservative_unweighted_n, union_expanded_unweighted_n,
    union_expanded_ambiguous_unweighted_n
  )]
}

process_partition <- function(path) {
  t0 <- Sys.time()
  d <- as.data.table(read_parquet(path))
  yr <- unique(d$year)
  qtr <- unique(d$quarter)
  if (length(yr) != 1L || length(qtr) != 1L) stop("Mixed period in ", path)
  if (any(d[, uniqueN(uf), by = stratum]$V1 > 1L)) stop("Survey stratum crosses UF in ", path)
  d[, `:=`(
    one = 1,
    psu_design = factor(paste(year, quarter, upa, sep = "-")),
    stratum_design = factor(paste(year, quarter, stratum, sep = "-"))
  )]
  des <- svydesign(
    ids = ~psu_design, strata = ~stratum_design,
    weights = ~quarterly_calibrated_weight,
    data = d, nest = TRUE, check.strata = FALSE
  )
  pop <- rbindlist(list(
    population_cells(d, des, FALSE), population_cells(d, des, TRUE)
  ), use.names = TRUE)
  unions <- rbindlist(list(
    union_cells(d, des, "region", FALSE), union_cells(d, des, "region", TRUE),
    union_cells(d, des, "Brazil", FALSE), union_cells(d, des, "Brazil", TRUE)
  ), use.names = TRUE)
  uf_diag <- rbindlist(list(
    uf_union_diagnostics(d, FALSE), uf_union_diagnostics(d, TRUE)
  ), use.names = TRUE)
  pop[, `:=`(year = as.integer(yr), quarter = as.integer(qtr))]
  unions[, `:=`(year = as.integer(yr), quarter = as.integer(qtr))]
  uf_diag[, `:=`(year = as.integer(yr), quarter = as.integer(qtr))]
  cat(sprintf("quarter=%dQ%d elapsed_seconds=%.1f\n", yr, qtr,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  list(population = pop, union = unions, uf_diagnostic = uf_diag)
}

if (resume_mode) {
  denom <- fread(file.path(data_dir, "QUARTERLY_DENOMINATORS_AGE_SEX.csv"))
  unions <- fread(file.path(data_dir, "PNADC_UNION_CELL_ESTIMATES.csv"))
  uf_diag <- fread(file.path(audit_dir, "PNADC_UNION_UF_DIAGNOSTICS_NO_DESIGN_SE.csv"))
} else {
  results <- mclapply(files, process_partition, mc.cores = workers, mc.preschedule = FALSE)
  worker_failed <- vapply(results, inherits, logical(1L), "try-error")
  if (any(worker_failed)) {
    cat(paste(as.character(results[worker_failed]), collapse = "\n"), "\n")
    stop("Quarterly worker failed")
  }
  if (test_mode) {
    cat("quarterly_cell_test_ok\n")
    quit(save = "no", status = 0L)
  }
  denom <- rbindlist(lapply(results, `[[`, "population"), use.names = TRUE)
  unions <- rbindlist(lapply(results, `[[`, "union"), use.names = TRUE)
  uf_diag <- rbindlist(lapply(results, `[[`, "uf_diagnostic"), use.names = TRUE)
  rm(results)
  invisible(gc())

  denom[, `:=`(
    population_cv = population_se / population,
    ci_lower = pmax(0, population - qnorm(0.975) * population_se),
    ci_upper = population + qnorm(0.975) * population_se
  )]
  denom[, precision_pass := unweighted_n >= cfg$denominators$minimum_unweighted_cell_n &
    population_cv <= cfg$denominators$maximum_cell_cv]
  setorder(denom, year, quarter, geography_level, geography_value, sex, age)
  fwrite(denom, file.path(data_dir, "QUARTERLY_DENOMINATORS_AGE_SEX.csv"))
  write_parquet(denom, file.path(data_dir, "QUARTERLY_DENOMINATORS_AGE_SEX.parquet"), compression = "zstd")

  unions[, `:=`(
    union_conservative_cv = fifelse(union_conservative > 0, union_conservative_se / union_conservative, NA_real_),
    union_expanded_cv = fifelse(union_expanded > 0, union_expanded_se / union_expanded, NA_real_),
    union_conservative_ci_lower = pmax(0, union_conservative - qnorm(0.975) * union_conservative_se),
    union_conservative_ci_upper = pmin(1, union_conservative + qnorm(0.975) * union_conservative_se),
    union_expanded_ci_lower = pmax(0, union_expanded - qnorm(0.975) * union_expanded_se),
    union_expanded_ci_upper = pmin(1, union_expanded + qnorm(0.975) * union_expanded_se)
  )]
  setorder(unions, year, quarter, geography_level, geography_value, sex, age)
  fwrite(unions, file.path(data_dir, "PNADC_UNION_CELL_ESTIMATES.csv"))
  write_parquet(unions, file.path(data_dir, "PNADC_UNION_CELL_ESTIMATES.parquet"), compression = "zstd")
  fwrite(uf_diag, file.path(audit_dir, "PNADC_UNION_UF_DIAGNOSTICS_NO_DESIGN_SE.csv"))
}

b <- cfg$behavioral_outcomes
precision <- unions[age == 15L, .(
  cells = .N,
  share_n_at_least_threshold = mean(unweighted_n >= b$minimum_unweighted_cell_n_for_diagnostics),
  share_cases_at_least_threshold = mean(union_conservative_unweighted_n >= b$minimum_positive_union_cases_for_diagnostics),
  share_cv_at_most_threshold = mean(!is.na(union_conservative_cv) & union_conservative_cv <= b$maximum_prevalence_cv_for_diagnostics),
  zero_case_cells = sum(union_conservative_unweighted_n == 0L),
  median_unweighted_n = median(unweighted_n),
  median_union_cases = median(union_conservative_unweighted_n),
  median_prevalence_cv = median(union_conservative_cv, na.rm = TRUE)
), by = .(geography_level, sex)]
precision[, primary_behavior_geography := geography_level == b$primary_geography]
fwrite(precision, file.path(audit_dir, "PNADC_UNION_PRECISION_DIAGNOSTICS.csv"))

annual <- fread(file.path(data_dir, "DENOMINATORS_AGE_SEX.csv"))
qmean <- denom[, .(
  quarterly_mean_population = mean(population),
  quarterly_population_sd = sd(population),
  quarterly_mean_design_se = mean(population_se), quarters = uniqueN(quarter)
), by = .(year, geography_level, geography_value, age, sex)]
comparison <- merge(
  annual[, .(year, geography_level, geography_value, age, sex,
             annual_first_visit_population = population, annual_first_visit_se = population_se)],
  qmean, by = c("year", "geography_level", "geography_value", "age", "sex")
)
comparison[, difference := quarterly_mean_population - annual_first_visit_population]
comparison[, relative_difference := difference / annual_first_visit_population]
fwrite(comparison, file.path(audit_dir, "PNADC_ANNUAL_QUARTERLY_DENOMINATOR_COMPARISON.csv"))

valid_pop <- denom[, .(
  population_cells = .N,
  missing_population = sum(is.na(population) | is.na(population_se)),
  negative_population = sum(population < 0, na.rm = TRUE)
), by = .(year, quarter, geography_level)]
valid_union <- unions[, .(
  union_cells = .N,
  missing_union = sum(is.na(union_conservative) | is.na(union_conservative_se) |
                        is.na(union_expanded) | is.na(union_expanded_se)),
  prevalence_out_of_bounds = sum(union_conservative < 0 | union_conservative > 1 |
                                   union_expanded < 0 | union_expanded > 1, na.rm = TRUE)
), by = .(year, quarter, geography_level)]
validation <- merge(valid_pop, valid_union,
                    by = c("year", "quarter", "geography_level"), all = TRUE)
fwrite(validation, file.path(audit_dir, "PNADC_QUARTERLY_CELL_VALIDATION.csv"))
if (any(valid_pop$missing_population != 0L) || any(valid_pop$negative_population != 0L) ||
    any(valid_union$missing_union != 0L) || any(valid_union$prevalence_out_of_bounds != 0L)) {
  stop("Quarterly cell validation failed")
}

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed), sprintf("workers=%d", workers),
  sprintf("input_partitions=%d", length(files)),
  sprintf("denominator_cells=%d", nrow(denom)),
  sprintf("union_design_based_cells=%d", nrow(unions)),
  sprintf("union_uf_diagnostic_cells=%d", nrow(uf_diag)),
  "effects_estimated=0", "weight=V1028 quarterly calibrated",
  "variance=Taylor linearization with quarterly strata and UPAs",
  "population_region_brazil_variance=sum of disjoint UF-stratum variances",
  "union_uf=diagnostic weighted prevalence only; no design-based SE"
)
writeLines(log_lines, file.path(log_dir, "09_build_quarterly_cells.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
